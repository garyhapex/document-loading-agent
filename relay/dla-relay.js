// ============================================================================
// dla-relay.js
// Document Loading Agent -- Invoice Relay
//
// Author  : Claude for Gary D. Hall
// Version : 1.2.0 (11/19/2026)
//
// WHAT IT IS
//   A small program that runs on the PC where Ollama is installed. It sits
//   between the Document Loading Agent (Oracle, in the cloud) and the AI
//   model on this PC. Same idea as the Stick-IT print relay
//   (imaginary-relay.js): there the work is a label for a printer, here the
//   work is an invoice for the model to read.
//
// HOW IT TALKS TO THE DATABASE -- THE RELAY REACHES OUT
//   The relay only ever calls OUT, over HTTPS, to the ORDS address.
//   Nothing calls IN: no listening port, no ngrok, no open door.
//   Every 5 seconds it asks
//     GET  {ORDS}/dla/relay/work
//   If an invoice is waiting, it sends the image to Ollama on this PC
//     POST http://127.0.0.1:11434/api/chat
//   and answers the database with
//     POST {ORDS}/dla/relay/work/{extraction_id}
//   Every call to ORDS carries the header X-DLA-Relay-Token.
//   Database side: db/relay/DLA_04_RELAY_DATABASE.sql (DLA_RELAY_PKG).
//
// ONE INVOICE AT A TIME
//   The model runs on the processor and takes a minute or more per
//   invoice, so the relay does not ask for more work until it has answered
//   the invoice it is holding.
//
// WHAT IT CAN READ (1.1.0)
//   PDF, PNG and JPG. People upload invoices as PDFs, and a vision model
//   can only look at pictures, so the relay turns each PDF page into a
//   picture first and sends the pictures to the model. The database keeps
//   the original PDF. The conversion is done by pdftoppm, a small free
//   program from the Poppler project:
//     winget install --id oschwartz10612.Poppler -e
//   The relay finds pdftoppm by itself (see FINDING PDFTOPPM below). If it
//   is not installed, a PDF is answered with a clear error that says so;
//   pictures still work. Only the first PDF_MAX_PAGES pages are read.
//
// THE WATCHED FOLDER (1.2.0)
//   Optional. When "watch_folder" is set (for example C:\DLA\inbox), the
//   relay also looks in that folder every few seconds. Anyone who saves,
//   scans or copies an invoice into it has "uploaded" it: the relay sends
//   the file to the database
//     POST {ORDS}/dla/relay/documents
//   where it is stored and queued exactly as a drop on the Upload page is,
//   and the model reads it next. Nobody opens the application.
//   What happens to each file:
//     sent OK      -> moved to  {watch_folder}\done
//     refused      -> moved to  {watch_folder}\failed  (reason in the log
//                     and in a .txt beside the file)
//     not readable -> left in place and tried again next time; after
//                     WATCH_MAX_TRIES tries it goes to failed
//   The three real-world problems and how they are handled:
//     1. A file still being written (a scan or a slow copy). A file is only
//        picked up when its size has not changed between two looks and it
//        can be opened for reading. A half-copied file is left alone.
//     2. The same file dropped twice. Each file is moved out of the folder
//        the moment it is sent, so one drop is one read. If someone copies
//        the same invoice in again later it IS read again, on purpose, and
//        the invoice-level duplicate check in the database stops it for a
//        person (that is the agent's job, not the relay's).
//     3. A file that is not an invoice (a .txt, .docx, .xlsx, Thumbs.db).
//        Only .pdf, .png, .jpg and .jpeg are sent. Anything else is moved
//        to failed with a note, so the folder never fills with junk.
//   The two sub-folders are created by the relay if they are missing.
//
// SETTINGS
//   1. dla-relay-settings.json, in the same folder as this file:
//        { "ords_base_url": "https://.../ords/prd_workspace",
//          "relay_token":   "...",
//          "watch_folder":  "C:\\DLA\\inbox" }
//      watch_folder is optional; leave it out and the relay only reads
//      what the Upload page queues. In JSON every backslash is doubled.
//      Optional: "pdftoppm_path", the full path of pdftoppm.exe, only if
//      the relay cannot find it by itself.
//      Optional: "ollama_url" (default http://127.0.0.1:11434). The number
//      form is used on purpose: "localhost" can resolve to the IPv6 address
//      ::1, where Ollama does not listen (ECONNREFUSED ::1:11434).
//      That file holds a secret and is in .gitignore. Never commit it.
//   2. If there is no settings file, the environment variables
//        DLA_ORDS_BASE_URL, DLA_RELAY_TOKEN, DLA_OLLAMA_URL,
//        DLA_WATCH_FOLDER, DLA_PDFTOPPM_PATH
//      (for running under pm2 with an ecosystem file).
//   Without settings the relay says so once a minute and does nothing else.
//
// DEPENDENCIES
//   Node.js only -- https, http, url, fs, path, os, child_process are built
//   in. No npm packages. pdftoppm (Poppler) is needed only for PDFs.
//
/*
cd C:\Users\GHAPEX\OneDrive\Documents\GitHub\document-loading-agent
node relay\dla-relay.js
 */
// ============================================================================

'use strict';

const https   = require('https');
const http    = require('http');
const { URL } = require('url');
const fs      = require('fs');
const path    = require('path');
const os      = require('os');
const { execFile, execFileSync } = require('child_process');

const RELAY_VERSION = '1.2.0';

// ============================================================================
// CONFIGURATION
// ============================================================================

const SETTINGS_FILE = path.join(__dirname, 'dla-relay-settings.json');

function loadSettings() {
    if (fs.existsSync(SETTINGS_FILE)) {
        try {
            // A byte-order mark (Windows editors add one) is not JSON.
            const raw = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8').replace(/^\uFEFF/, ''));
            return { source:      SETTINGS_FILE,
                     error:       null,
                     ordsBaseUrl: raw.ords_base_url ? String(raw.ords_base_url).trim() : null,
                     relayToken:  raw.relay_token   ? String(raw.relay_token).trim()   : null,
                     ollamaUrl:   raw.ollama_url    ? String(raw.ollama_url).trim()    : 'http://127.0.0.1:11434',
                     pdftoppmPath: raw.pdftoppm_path ? String(raw.pdftoppm_path).trim() : null,
                     watchFolder: raw.watch_folder  ? String(raw.watch_folder).trim()  : null };
        } catch (err) {
            return { source: SETTINGS_FILE, error: err.message,
                     ordsBaseUrl: null, relayToken: null, ollamaUrl: 'http://127.0.0.1:11434',
                     pdftoppmPath: null, watchFolder: null };
        }
    }
    return { source:      'environment variables',
             error:       null,
             ordsBaseUrl: process.env.DLA_ORDS_BASE_URL || null,
             relayToken:  process.env.DLA_RELAY_TOKEN   || null,
             ollamaUrl:   process.env.DLA_OLLAMA_URL    || 'http://127.0.0.1:11434',
             pdftoppmPath: process.env.DLA_PDFTOPPM_PATH || null,
             watchFolder: process.env.DLA_WATCH_FOLDER  || null };
}

const SETTINGS = loadSettings();

// How often the relay asks for work when it is idle.
const WORK_POLL_INTERVAL_MS = 5000;

// Time allowed for one ask for work or one answer post. A work answer from
// ORDS carries a whole invoice image, so this is generous.
const ORDS_TIMEOUT_MS = 60000;

// Time allowed for the model to read one invoice. On a processor with no
// graphics card this can be several minutes, more on the first invoice
// after the PC starts (the model has to load).
const OLLAMA_TIMEOUT_MS = 20 * 60 * 1000;

// PDF conversion. 150 dots per inch gives a letter page of about
// 1275 x 1650 pixels: sharp enough to read small print, small enough for
// the model. Each extra page adds to the reading time, so only the first
// few pages of a long PDF are sent.
const PDF_DPI            = 150;
const PDF_MAX_PAGES      = 3;
const PDF_TIMEOUT_MS     = 120000;

// Answer posting: tries and the wait between them.
const ANSWER_TRIES  = 4;
const ANSWER_GAP_MS = 2000;

// The watched folder (1.2.0). How often it is looked at, which file types
// are invoices, and how many times a file that cannot be sent (database
// unreachable, file locked) is tried before it is set aside in "failed".
// A file is sent only after its size is the same on two looks in a row, so
// a file still being copied or scanned waits at least one interval.
const WATCH_POLL_INTERVAL_MS = 5000;
const WATCH_FILE_TYPES       = { '.pdf': 'application/pdf',
                                 '.png': 'image/png',
                                 '.jpg': 'image/jpeg',
                                 '.jpeg': 'image/jpeg' };
const WATCH_MAX_TRIES        = 5;
const WATCH_MAX_FILE_BYTES   = 25 * 1024 * 1024;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function stamp() {
    // Local time on this PC, as YYYY-MM-DD HH:MM:SS.
    return new Date().toLocaleString('sv-SE');
}

function log(tag, message)  { console.log(stamp()  + ' [' + tag + '] ' + message); }
function warn(tag, message) { console.warn(stamp() + ' [' + tag + '] ' + message); }

// ============================================================================
// ONE HTTP HELPER
// Returns { statusCode, json, raw }. json is null when the answer is not
// JSON; the caller checks. Rejects on a network failure or a timeout.
// ============================================================================
function httpRequest(method, fullUrl, headers, bodyObj, timeoutMs) {
    return new Promise((resolve, reject) => {
        let target;
        try {
            target = new URL(fullUrl);
        } catch (err) {
            return reject(new Error('not a valid URL: ' + fullUrl));
        }

        // ORDS on Autonomous Database is always https. Ollama on this PC is
        // plain http on localhost.
        const client  = target.protocol === 'http:' ? http : https;
        const bodyStr = bodyObj ? JSON.stringify(bodyObj) : null;

        const options = {
            hostname: target.hostname,
            port:     target.port || (target.protocol === 'http:' ? 80 : 443),
            path:     target.pathname + target.search,
            method:   method,
            timeout:  timeoutMs,
            headers:  Object.assign({}, headers || {})
        };

        if (bodyStr) {
            options.headers['Content-Type']   = 'application/json';
            options.headers['Content-Length'] = Buffer.byteLength(bodyStr);
        }

        const req = client.request(options, (res) => {
            const chunks = [];
            res.on('data', (chunk) => { chunks.push(chunk); });
            res.on('end', () => {
                const data = Buffer.concat(chunks).toString('utf8');
                let parsed = null;
                try { parsed = JSON.parse(data); } catch (e) { /* leave null, caller checks */ }
                resolve({ statusCode: res.statusCode, json: parsed, raw: data });
            });
        });

        req.on('timeout', () => { req.destroy(new Error('request timed out after ' + Math.round(timeoutMs / 1000) + ' s')); });
        req.on('error', (err) => reject(err));

        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

function ordsUrl(pathPart) {
    return SETTINGS.ordsBaseUrl.replace(/\/+$/, '') + pathPart;
}

function ordsHeaders() {
    return { 'X-DLA-Relay-Token': SETTINGS.relayToken };
}

// ============================================================================
// FINDING PDFTOPPM (1.1.0)
// Looked for once, at start, in this order:
//   1. "pdftoppm_path" in the settings (or DLA_PDFTOPPM_PATH).
//   2. On the PATH (just "pdftoppm").
//   3. Where winget puts the Poppler package:
//        %LOCALAPPDATA%\Microsoft\WinGet\Packages\oschwartz10612.Poppler...
//      searched a few folders deep for pdftoppm.exe.
// Returns the command to run, or null when it is not installed.
// ============================================================================
function findFileDeep(dir, fileName, depth) {
    if (depth < 0) return null;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return null; }
    for (const e of entries) {
        if (e.isFile() && e.name.toLowerCase() === fileName) return path.join(dir, e.name);
    }
    for (const e of entries) {
        if (e.isDirectory()) {
            const hit = findFileDeep(path.join(dir, e.name), fileName, depth - 1);
            if (hit) return hit;
        }
    }
    return null;
}

function works(command) {
    try {
        execFileSync(command, ['-v'], { stdio: 'ignore', timeout: 10000 });
        return true;
    } catch (err) {
        // pdftoppm -v prints its version and some builds exit non-zero; a
        // missing program fails with ENOENT instead.
        return err.code !== 'ENOENT' && err.code !== 'EACCES';
    }
}

function findPdftoppm() {
    if (SETTINGS.pdftoppmPath) {
        return fs.existsSync(SETTINGS.pdftoppmPath) ? SETTINGS.pdftoppmPath : null;
    }
    if (works('pdftoppm')) return 'pdftoppm';

    const local = process.env.LOCALAPPDATA;
    if (local) {
        const packages = path.join(local, 'Microsoft', 'WinGet', 'Packages');
        let dirs = [];
        try { dirs = fs.readdirSync(packages); } catch (e) { /* no winget packages folder */ }
        for (const d of dirs) {
            if (d.toLowerCase().indexOf('poppler') !== -1) {
                const hit = findFileDeep(path.join(packages, d), 'pdftoppm.exe', 6);
                if (hit) return hit;
            }
        }
    }
    return null;
}

const PDFTOPPM = findPdftoppm();

function isPdf(item, buffer) {
    const mime = String(item.mime_type || '').toLowerCase();
    const name = String(item.file_name || '').toLowerCase();
    return mime === 'application/pdf' || name.endsWith('.pdf') ||
           (buffer.length > 4 && buffer.slice(0, 4).toString('latin1') === '%PDF');
}

// Turns a PDF (as a Buffer) into an array of base64 PNG pictures, one per
// page, first page first. Uses a private temporary folder and removes it.
function pdfToImages(buffer) {
    return new Promise((resolve, reject) => {
        if (!PDFTOPPM) {
            return reject(new Error('this file is a PDF and the PDF converter (pdftoppm, from Poppler) is not installed ' +
                                    'on the relay PC. Install it with: winget install --id oschwartz10612.Poppler -e ' +
                                    'and start the relay again.'));
        }

        let dir;
        try {
            dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dla-relay-'));
            fs.writeFileSync(path.join(dir, 'in.pdf'), buffer);
        } catch (err) {
            return reject(new Error('could not write the PDF to a temporary folder: ' + err.message));
        }

        const cleanUp = () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* best effort */ } };

        execFile(PDFTOPPM,
                 ['-png', '-r', String(PDF_DPI), '-f', '1', '-l', String(PDF_MAX_PAGES),
                  path.join(dir, 'in.pdf'), path.join(dir, 'page')],
                 { timeout: PDF_TIMEOUT_MS, windowsHide: true },
                 (err, stdout, stderr) => {
            if (err) {
                cleanUp();
                return reject(new Error('the PDF could not be converted to pictures: ' +
                                        (String(stderr || '').trim().slice(0, 300) || err.message)));
            }
            let images;
            try {
                images = fs.readdirSync(dir)
                           .filter((f) => /^page.*\.png$/i.test(f))
                           .sort()
                           .map((f) => fs.readFileSync(path.join(dir, f)).toString('base64'));
            } catch (readErr) {
                cleanUp();
                return reject(new Error('the converted pictures could not be read: ' + readErr.message));
            }
            cleanUp();
            if (images.length === 0) {
                return reject(new Error('the PDF converted to no pictures. It may be empty or damaged.'));
            }
            resolve(images);
        });
    });
}

// ============================================================================
// THE MODEL
// Sends one invoice image and the prompt to Ollama and returns the model's
// answer text. format:"json" tells Ollama the answer must be JSON.
// ============================================================================
async function askModel(item, images) {

    const resp = await httpRequest(
        'POST',
        SETTINGS.ollamaUrl.replace(/\/+$/, '') + '/api/chat',
        null,
        { model:    item.model,
          stream:   false,
          format:   'json',
          options:  { temperature: 0 },
          messages: [ { role: 'user', content: item.prompt, images: images } ] },
        OLLAMA_TIMEOUT_MS);

    if (resp.statusCode !== 200) {
        const reason = resp.json && resp.json.error ? resp.json.error : String(resp.raw).slice(0, 300);
        throw new Error('Ollama answered HTTP ' + resp.statusCode + ': ' + reason);
    }
    if (!resp.json || !resp.json.message || typeof resp.json.message.content !== 'string') {
        throw new Error('Ollama answered, but not in the expected shape: ' + String(resp.raw).slice(0, 300));
    }

    let text = resp.json.message.content.trim();

    // Some models wrap JSON in a ``` fence even when asked not to.
    if (text.startsWith('```')) {
        text = text.replace(/^```[a-zA-Z]*\s*/, '').replace(/\s*```$/, '').trim();
    }
    return text;
}

// Does one work item and returns the answer object for the database.
async function runWork(item) {
    const started = Date.now();
    try {
        // The field is called image_base64 for history; it holds the whole
        // uploaded file, picture or PDF. ORDS base64 has line breaks.
        const fileB64 = String(item.image_base64 || '').replace(/\s+/g, '');
        if (!fileB64) {
            throw new Error('the work item has no file');
        }
        const buffer = Buffer.from(fileB64, 'base64');
        const mime   = String(item.mime_type || '').toLowerCase();

        let images;
        if (isPdf(item, buffer)) {
            images = await pdfToImages(buffer);
            log('WORK', 'Extraction ' + item.extraction_id + ': PDF converted to ' + images.length +
                        ' picture(s)' + (images.length === PDF_MAX_PAGES ? ' (first ' + PDF_MAX_PAGES + ' pages at most)' : '') + '.');
        } else if (mime.startsWith('image/')) {
            images = [ fileB64 ];
        } else {
            return { status:  'ERROR',
                     message: 'The relay reads PDF, PNG and JPG files. This file is ' +
                              (item.mime_type || 'of unknown type') + '.' };
        }

        const text = await askModel(item, images);
        return { status: 'SUCCESS', raw_response: text, elapsed_ms: Date.now() - started };
    } catch (err) {
        return { status: 'ERROR', message: 'Relay could not get an answer from the model: ' + err.message,
                 elapsed_ms: Date.now() - started };
    }
}

// Posts one answer, trying again on a network failure.
async function postAnswer(extractionId, answer) {
    const url = ordsUrl('/dla/relay/work/' + encodeURIComponent(extractionId));

    for (let attempt = 1; attempt <= ANSWER_TRIES; attempt++) {
        try {
            const resp = await httpRequest('POST', url, ordsHeaders(), answer, ORDS_TIMEOUT_MS);
            if (resp.statusCode === 200) {
                return resp.json && resp.json.message ? resp.json.message : 'accepted';
            }
            warn('WORK', 'Answer for extraction ' + extractionId + ' refused -- HTTP ' + resp.statusCode + ' ' +
                         (resp.json && resp.json.message ? resp.json.message : String(resp.raw).slice(0, 200)));
            // 400 / 401 / 404 will not get better by trying again.
            if (resp.statusCode === 400 || resp.statusCode === 401 || resp.statusCode === 404) return null;
        } catch (err) {
            warn('WORK', 'Answer for extraction ' + extractionId + ' not delivered (try ' +
                         attempt + '/' + ANSWER_TRIES + '): ' + err.message);
        }
        if (attempt < ANSWER_TRIES) await sleep(ANSWER_GAP_MS);
    }
    return null;
}

// ============================================================================
// THE WATCHED FOLDER (1.2.0)
// Every WATCH_POLL_INTERVAL_MS the folder is listed. For each file:
//   - sub-folders and unknown types are dealt with at once
//   - a file whose size changed since the last look is left for next time
//   - a steady file is read, sent to POST documents, and moved to done
// seen[] remembers each file's size and how many sends have been tried.
// ============================================================================
const WATCH = { folder: null, done: null, failed: null, seen: new Map(), busy: false, ready: false };

function setUpWatchFolder() {
    if (!SETTINGS.watchFolder) return;
    WATCH.folder = path.resolve(SETTINGS.watchFolder);
    WATCH.done   = path.join(WATCH.folder, 'done');
    WATCH.failed = path.join(WATCH.folder, 'failed');
    try {
        fs.mkdirSync(WATCH.folder, { recursive: true });
        fs.mkdirSync(WATCH.done,   { recursive: true });
        fs.mkdirSync(WATCH.failed, { recursive: true });
        WATCH.ready = true;
    } catch (err) {
        WATCH.ready = false;
        WATCH.error = 'cannot create or open the watched folder ' + WATCH.folder + ': ' + err.message;
    }
}

// Moves a file into done or failed. If a file of the same name is already
// there, the new one gets a time stamp so nothing is overwritten.
function moveAside(fromPath, toDir, note) {
    const base = path.basename(fromPath);
    let target = path.join(toDir, base);
    if (fs.existsSync(target)) {
        const ext  = path.extname(base);
        const tag  = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
        target = path.join(toDir, base.slice(0, base.length - ext.length) + '-' + tag + ext);
    }
    try {
        fs.renameSync(fromPath, target);
    } catch (err) {
        warn('WATCH', 'Could not move ' + base + ' to ' + toDir + ': ' + err.message);
        return false;
    }
    if (note) {
        try { fs.writeFileSync(target + '.txt', stamp() + '  ' + note + os.EOL); } catch (e) { /* best effort */ }
    }
    WATCH.seen.delete(fromPath);
    return true;
}

// Sends one file to the database. Resolves to { ok, permanent, message }.
// permanent means trying again will not help (bad type, bad token).
async function sendFile(filePath, mime) {
    const name   = path.basename(filePath);
    const buffer = fs.readFileSync(filePath);           // throws if locked -> caller retries
    const body   = { file_name:   name,
                     mime_type:   mime,
                     file_base64: buffer.toString('base64'),
                     source:      WATCH.folder };
    const resp = await httpRequest('POST', ordsUrl('/dla/relay/documents'), ordsHeaders(), body, ORDS_TIMEOUT_MS);
    const message = resp.json && resp.json.message ? resp.json.message : String(resp.raw).slice(0, 200);
    if (resp.statusCode === 200) return { ok: true, permanent: false, message: message };
    return { ok: false,
             permanent: (resp.statusCode === 400 || resp.statusCode === 401),
             message: 'HTTP ' + resp.statusCode + ' ' + message };
}

async function lookInWatchFolder() {
    if (!WATCH.ready || WATCH.busy) return;
    WATCH.busy = true;
    try {
        let entries;
        try {
            entries = fs.readdirSync(WATCH.folder, { withFileTypes: true });
        } catch (err) {
            warn('WATCH', 'Cannot list ' + WATCH.folder + ': ' + err.message);
            return;
        }

        // Files only, in name order, so GAS_01 goes before GAS_02.
        const files = entries.filter((e) => e.isFile()).map((e) => e.name).sort();

        for (const name of files) {
            const filePath = path.join(WATCH.folder, name);
            const ext      = path.extname(name).toLowerCase();

            // Not an invoice type: set it aside with a note, once.
            if (!WATCH_FILE_TYPES[ext]) {
                if (name.toLowerCase() === 'desktop.ini' || name.toLowerCase() === 'thumbs.db') continue;
                log('WATCH', name + ' is not a PDF, PNG or JPG. Moved to failed.');
                moveAside(filePath, WATCH.failed, 'Not an invoice file type. The relay reads .pdf, .png, .jpg and .jpeg only.');
                continue;
            }

            let size;
            try { size = fs.statSync(filePath).size; } catch (e) { continue; }   // vanished between list and stat

            const prev = WATCH.seen.get(filePath);
            if (!prev || prev.size !== size) {
                // First look, or still growing: remember the size and wait one interval.
                WATCH.seen.set(filePath, { size: size, tries: prev ? prev.tries : 0 });
                if (!prev) log('WATCH', 'Found ' + name + ' (' + size + ' bytes). Checking it is complete.');
                continue;
            }

            if (size === 0) {
                log('WATCH', name + ' is empty. Moved to failed.');
                moveAside(filePath, WATCH.failed, 'The file is empty (0 bytes).');
                continue;
            }
            if (size > WATCH_MAX_FILE_BYTES) {
                log('WATCH', name + ' is ' + Math.round(size / 1024 / 1024) + ' MB, over the limit. Moved to failed.');
                moveAside(filePath, WATCH.failed, 'The file is larger than ' + (WATCH_MAX_FILE_BYTES / 1024 / 1024) + ' MB.');
                continue;
            }

            // Steady: send it.
            prev.tries += 1;
            let result;
            try {
                result = await sendFile(filePath, WATCH_FILE_TYPES[ext]);
            } catch (err) {
                result = { ok: false, permanent: false, message: err.message };
            }

            if (result.ok) {
                log('WATCH', name + ' sent to the database: ' + result.message + ' Moved to done.');
                moveAside(filePath, WATCH.done, null);
            } else if (result.permanent) {
                warn('WATCH', name + ' refused by the database: ' + result.message + ' Moved to failed.');
                moveAside(filePath, WATCH.failed, 'Refused by the database: ' + result.message);
            } else if (prev.tries >= WATCH_MAX_TRIES) {
                warn('WATCH', name + ' could not be sent after ' + prev.tries + ' tries: ' + result.message + ' Moved to failed.');
                moveAside(filePath, WATCH.failed, 'Could not be sent after ' + prev.tries + ' tries: ' + result.message +
                                                  ' Copy it back into the folder to try again.');
            } else {
                warn('WATCH', name + ' not sent (try ' + prev.tries + '/' + WATCH_MAX_TRIES + '): ' + result.message +
                              ' Will try again.');
            }
        }

        // Forget files that are no longer there (moved or deleted by someone).
        for (const known of Array.from(WATCH.seen.keys())) {
            if (!fs.existsSync(known)) WATCH.seen.delete(known);
        }
    } catch (err) {
        warn('WATCH', 'Looking in the folder failed: ' + err.message);
    } finally {
        WATCH.busy = false;
    }
}

// ============================================================================
// THE WORK LOOP
// ============================================================================
let busy = false;
let consecutiveFailures = 0;

async function askForWork() {
    if (busy) return;
    busy = true;

    try {
        const resp = await httpRequest('GET', ordsUrl('/dla/relay/work'), ordsHeaders(), null, ORDS_TIMEOUT_MS);

        if (resp.statusCode !== 200 || !resp.json || resp.json.status !== 'OK') {
            consecutiveFailures++;
            // One line, then about one a minute, so a long outage does not flood the log.
            if (consecutiveFailures === 1 || consecutiveFailures % 12 === 0) {
                warn('WORK', 'Asking for work failed -- HTTP ' + resp.statusCode + ' ' +
                             (resp.json && resp.json.message ? resp.json.message : String(resp.raw).slice(0, 200)));
            }
            return;
        }

        if (consecutiveFailures > 0) {
            log('WORK', 'Reaching the database again after ' + consecutiveFailures + ' failed ask(s).');
            consecutiveFailures = 0;
        }

        const items = Array.isArray(resp.json.work) ? resp.json.work : [];
        for (const item of items) {
            log('WORK', 'Picked up extraction ' + item.extraction_id + ': ' + item.file_name +
                        ' -> ' + item.model + '. Reading; this can take several minutes.');

            const answer = await runWork(item);
            const seconds = answer.elapsed_ms ? ' in ' + Math.round(answer.elapsed_ms / 1000) + ' s' : '';
            log('WORK', 'Extraction ' + item.extraction_id + ' -> ' + answer.status + seconds +
                        (answer.status === 'ERROR' ? ': ' + answer.message : ''));

            const delivered = await postAnswer(item.extraction_id, answer);
            if (delivered) {
                log('WORK', 'Extraction ' + item.extraction_id + ' answer delivered: ' + delivered);
            } else {
                warn('WORK', 'Extraction ' + item.extraction_id + ' answer NOT delivered.');
            }
        }
    } catch (err) {
        consecutiveFailures++;
        if (consecutiveFailures === 1 || consecutiveFailures % 12 === 0) {
            warn('WORK', 'Cannot reach the database: ' + err.message);
        }
    } finally {
        busy = false;
    }
}

// ============================================================================
// START
// ============================================================================
function start() {
    console.log('============================================================');
    console.log(' Document Loading Agent -- Invoice Relay ' + RELAY_VERSION);
    console.log(' Settings : ' + SETTINGS.source);
    console.log(' Ollama   : ' + SETTINGS.ollamaUrl);
    console.log(' PDFs     : ' + (PDFTOPPM ? 'converter found (' + PDFTOPPM + ')'
                                           : 'converter NOT found. PDFs will be refused; pictures still work.'));
    setUpWatchFolder();
    if (!SETTINGS.watchFolder) {
        console.log(' Watch    : off. Set "watch_folder" in the settings to pick invoices up from a folder.');
    } else if (WATCH.ready) {
        console.log(' Watch    : ' + WATCH.folder + '  (sent files go to done\\, refused files to failed\\)');
    } else {
        console.log(' Watch    : NOT running. ' + WATCH.error);
    }

    let problem = null;
    if (SETTINGS.error) {
        problem = 'The settings file cannot be read: ' + SETTINGS.error;
    } else if (!SETTINGS.ordsBaseUrl || !SETTINGS.relayToken) {
        problem = 'Settings are missing. ords_base_url and relay_token are both needed.';
    } else if (!/^https?:\/\//i.test(SETTINGS.ordsBaseUrl)) {
        problem = 'ords_base_url must start with https://';
    }

    if (problem) {
        console.log(' NOT RUNNING: ' + problem);
        console.log('============================================================');
        setInterval(() => { warn('SETUP', problem); }, 60000);
        return;
    }

    // The token is a secret: only its length is shown.
    console.log(' Database : ' + SETTINGS.ordsBaseUrl);
    console.log(' Token    : set (' + SETTINGS.relayToken.length + ' characters)');
    console.log(' Work     : asking every ' + (WORK_POLL_INTERVAL_MS / 1000) + ' s. Calls out only.');
    console.log(' Stop     : press Ctrl+C');
    console.log('============================================================');

    askForWork();
    setInterval(askForWork, WORK_POLL_INTERVAL_MS);

    if (WATCH.ready) {
        lookInWatchFolder();
        setInterval(lookInWatchFolder, WATCH_POLL_INTERVAL_MS);
    }
}

start();
