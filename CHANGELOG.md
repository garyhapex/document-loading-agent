# Build Log

Newest entries at the top. Each entry records what was done, where, and the result.

## 11/21/2026 - New desktop set up and proven (no code changes)

| Step | What | Where | Result |
|---|---|---|---|
| 1 | New PC: Acer Predator Orion 6000 (Core Ultra 7 265KF, RTX 5060 Ti 16 GB, 16 GB DDR5, 1 TB), Windows user `garyh`. Repository synced by OneDrive to `C:\Users\garyh\OneDrive\Documents\GitHub\document-loading-agent`. SQL Developer 26.2 (four connections, wallets in `C:\wallets`) and GitHub Desktop done 11/20 night and 11/21 morning. | New PC | Done. |
| 2 | Node.js v26.13.1 LTS (`C:\Program Files\nodejs`, npm 11.20.0). PowerShell refused `npm` ("running scripts is disabled"); fixed with `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`. | New PC | `node -v` = v26.13.1, `npm -v` = 11.20.0. |
| 3 | Poppler 26.09.0 with `winget install --id oschwartz10612.Poppler -e` (unpacked under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\...\poppler-26.09.0\Library\bin`; winget put `pdftoppm` on PATH). | New PC | Done. |
| 4 | Ollama (OllamaSetup.exe, no account) and `ollama pull qwen2.5vl:7b` (6.0 GB). | New PC | `ollama list` shows qwen2.5vl:7b 6.0 GB. |
| 5 | `relay\dla-relay-settings.json` had come over with OneDrive (ords_base_url, relay_token, watch_folder; no Poppler path, the relay finds pdftoppm on PATH). Nothing changed. | New PC | Checked. |
| 6 | `db/data/DLA_16_WATCH_MODEL.sql` run with the line set to OLLAMA (file changed to match in this commit). | DEV | WATCH_MODEL = OLLAMA, updated 21-NOV-26. |
| 7 | Relay 1.2.0 started (`node relay\dla-relay.js`); it created `C:\DLA\inbox` with `done` and `failed`. Two gas PDFs copied into the inbox one after the other. | New PC and DEV | **Passed.** First invoice 55 s (includes loading the model onto the card), second **6 s**. The laptop took 262 to 319 s. |
| 8 | Oracle Cloud sign-in forced a password change (identity-domain password expiry). Reset by the Forgot-password email. Nothing in the project uses that password. | OCI | Done. |
| 9 | `docs/DLA_SESSION_HANDOFF.md` brought level with the project copy. | - | Done. |

## 11/19/2026 (late evening) - Phase 4: The review page, and the watched folder (written)

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Open check from the last chat: Gary ran `db/relay/DLA_09_PROCESS_STAGED.sql` | DEV | Closed. Document 7 (GAS_04) is staged invoice 12 and its flag is "The invoice date is missing." The model left the date blank as instructed and the check stopped it. The 60-second read was simply a fast read. Nothing to fix. |
| 2 | Built page 3, Review Invoices, in application 300 (Claude, in Page Designer). Queue of PENDING staged invoices; the invoice file shown beside the fields (Ajax callback `SHOW_DOCUMENT` streams `DLA_DOCUMENTS.FILE_BLOB`); editable fields with a vendor pick list; flags and lines; buttons Save and check again (re-runs `DLA_PKG.VALIDATE_STAGING`), Approve and load (`DLA_PKG.LOAD_INVOICE`, LOADED_BY = the reviewer), Reject. Human Task not used. | DEV, Page Designer | Done and saved. Menu entry with icon. |
| 3 | Tested page 3 on real data | DEV | Passed. GAS_04 (missing date): date typed, Save and check again cleared the flag, Approve and load created the invoice with LOADED_BY = GHALL. GAS_05 (duplicate): rejected with a comment; document REJECTED. GAS_03 and GAS_06 left waiting on purpose, as demo material. Known: the green success message does not show after the branch back to the page; decisions are correct. |
| 4 | Page 3 layout tightened at Gary's request: the queue hides while an invoice is open (Back to the list brings it back), shorter comment box, shorter frame | DEV, Page Designer | Done. The whole review fits one screen. |
| 5 | Watched folder, database side: `db/relay/DLA_04_RELAY_DATABASE.sql` now adds `DLA_RELAY_PKG.RECEIVE_DOCUMENT` and a third endpoint `POST /dla/relay/documents` (same token header). Stores the file in `DLA_DOCUMENTS` with UPLOADED_BY = WATCHED_FOLDER and queues it, exactly as an upload on page 2. Test 2 added (wrong token 401, wrong type 400). | - | Written. **Not yet run on DEV.** Run as WKSP_WKSPPRDWORKSPACE; token and prompt are kept. |
| 6 | Watched folder, PC side: `relay/dla-relay.js` 1.2.0. New optional setting `watch_folder`. Every 5 s the folder is listed; a file is sent only when its size is unchanged between two looks (handles a file still being written); sent files move to `done\`, refused or non-invoice files to `failed\` with a `.txt` note; a file that cannot be sent (database unreachable) is tried 5 times, then set aside. Only .pdf, .png, .jpg, .jpeg. | - | Written. Tested by Claude against a stand-in database server: a sample PDF sent and moved to done; a .txt, an empty .pdf and a refused file moved to failed with notes. **Not yet run against DEV.** |
| 7 | `db/utilities/DLA_99_DROP_ALL.sql` now also deletes the ORDS module `dla.relay` and drops `DLA_RELAY_PKG` (was owed). Must now run as WKSP_WKSPPRDWORKSPACE. | - | Written. Not run (it is destructive). |
| 8 | Session closed. `docs/DLA_SESSION_HANDOFF.md` and the project documents brought up to date. Still owed: export of application 300 into `apex/`. | - | Done. |

## 11/20/2026 - Phase 4: The watched folder, live

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Ran `db/relay/DLA_04_RELAY_DATABASE.sql` (third endpoint `POST /dla/relay/documents`, `DLA_RELAY_PKG.RECEIVE_DOCUMENT`) | DEV, as WKSP_WKSPPRDWORKSPACE | Done. Token unchanged. |
| 2 | Added `watch_folder` = `C:\DLA\inbox` to `relay/dla-relay-settings.json`; started relay 1.2.0 | Local PC | Banner: `Watch : C:\DLA\inbox`. The relay created the folder with `done` and `failed` inside it. (Format standard Rule 17 added: say what a program does to the PC before it runs.) |
| 3 | Copied all six gas PDFs from `samples/invoices-gas/` into `C:\DLA\inbox` | Local PC and DEV | **Passed.** Found at 08:59:20, all six sent by 08:59:26 in file-name order (documents 21 to 26, extractions 21 to 26), moved to `done`, GAS_01 picked up for reading at 08:59:30. Nobody touched the application. All six stopped for a person as expected (each is a duplicate of an invoice already loaded or waiting). |

## 11/20/2026 - Phase 4: OCI Generative AI, the second reader

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Model chosen (Rule 7, checked against Oracle's model pages that morning): `google.gemini-2.5-flash` on OCI Generative AI. Takes a PDF as a document directly (no picture conversion), on-demand in Chicago, answers in seconds. The workspace credential `credentials_for_ocigenai_1` (OCI native signing) already exists in DEV_WORKSPACE from the label platform. | - | Decided. |
| 2 | `db/packages/DLA_02_PACKAGE.sql`: `EXTRACT_DOCUMENT` built. GENERIC chat request with a TEXT part (the prompt) and a DOCUMENT part (the PDF inline as base64; IMAGE for a picture), signed with the workspace credential, one retry on 429/5xx, then the same two steps as the relay path (PARSE_EXTRACTION, PROCESS_STAGING under savepoints). `db/data/DLA_13_OCI_MODEL.sql`: settings OCI_MODEL, OCI_ENDPOINT, OCI_CREDENTIAL, OCI_COMPARTMENT_OCID; the OCID is read from the label platform's package source in the same schema so it is never typed or committed. | - | Written. |
| 3 | Ran `DLA_02_PACKAGE.sql` (ADMIN), then `DLA_13_OCI_MODEL.sql` | DEV | DLA_02 clean. **DLA_13 failed silently on purpose-check:** it read USER_SOURCE, which as ADMIN holds ADMIN's objects, found no OCID and stopped with ORA-20013. Fixed to ALL_SOURCE with the owner; ran again, five settings set, credential found. |
| 4 | First OCI read: six gas PDFs dropped on page 2 with OCI_GENAI | DEV | Oracle answered every one in about 6.5 s with the invoice read correctly, **but all six stored as ERROR "not valid JSON"**: Gemini wraps its JSON in a ```json fence and the fence-stripping used DBMS_LOB.INSTR backwards, which it cannot do. Fixed with REGEXP_REPLACE. |
| 5 | `db/utilities/DLA_14_REMOVE_OCI_ERROR_ROWS.sql` written to remove the six ERROR test documents. Ran twice in SQL Developer as ADMIN: **ORA-12860 both times** (Autonomous Database runs SQL Developer's DML in parallel on the HIGH service). Claude then ran the delete from SQL Commands instead of fixing the script first — wrong per the project's own rule; Rule 18 added to the format standard. Script fixed with `ALTER SESSION DISABLE PARALLEL DML`; Gary ran it, "Removed 0" (rows already gone). | DEV | Six ERROR rows removed. |
| 6 | Second OCI read: the six gas PDFs again with OCI_GENAI (documents 35 to 40, extractions 33 to 38) | DEV | **Passed.** Read in 5.7 to 7.8 s each, staged and checked, all six stopped for a person with the right reasons (duplicates, bad total, missing date, unknown vendor). Gemini read "Tallulah Cathodic" correctly and left the missing invoice date blank, both things the local model got wrong. Two readers, one set of checks, same decisions. |
| 8 | Folder-to-OCI: `DLA_PKG.READ_WAITING_DOCUMENTS` (DLA_02), `DLA_RELAY_PKG.RECEIVE_DOCUMENT` now reads the new setting `WATCH_MODEL` (DLA_04: OLLAMA queues for the relay, OCI_GENAI leaves the file UPLOADED for the automation), `db/data/DLA_16_WATCH_MODEL.sql` sets it (one marked line to switch). APEX Automation "Read waiting documents" created by Claude in Shared Components: scheduled, FREQ=MINUTELY;INTERVAL=1, Always, one Execute Code action calling `dla_pkg.read_waiting_documents(20)`, error handling Ignore, status Active. | DEV | All three scripts ran clean (one harmless ORA-04068 on the first call after the recompile). **Passed:** GAS_01 copied into `C:\DLA\inbox` at 10:05:16 → relay stored it as document 41 "Waiting for the OCI reader" → automation picked it up on the next minute → Gemini read it in 6.5 s → checked, approved by the agent, loaded as invoice 21 (4 lines, 6,775.00). Nobody touched the application and the relay did no reading. Page 2 does not yet auto-refresh for a row waiting on the automation (Gary: leave page 2 alone for now). |
| 7 | `db/utilities/DLA_15_RESET_DEMO_DATA.sql` written and run: empties documents, reads, staging, invoices and audit; keeps vendors and settings; refuses to run while a read is RUNNING. Reason: every invoice dropped this morning stopped as a duplicate because the same six PDFs were already loaded or waiting; a demo needs a clean start each time. | DEV | Done. All tables empty, 9 vendors kept. Dropping the six gas PDFs in `C:\DLA\inbox` now replays the whole story: two load, four stop. |

## 11/19/2026 - Phase 3: Checks and the agent's decision (started)

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Ran `db/tables/DLA_08_VALIDATION_COLUMNS.sql`, `db/packages/DLA_02_PACKAGE.sql` (VALIDATE_STAGING, PROCESS_STAGING, LOAD_INVOICE built) and `db/relay/DLA_04_RELAY_DATABASE.sql` (the decision now runs after every read) | DEV, as WKSP_WKSPPRDWORKSPACE | Done, clean on the first run. |
| 2 | Ran `db/relay/DLA_09_PROCESS_STAGED.sql` | DEV | Passed. Both staged invoices were clean; the agent approved and loaded both with no person involved. Invoice 1: Prairie Fastener Supply Co. INV-10001, 364.00, 3 lines. Invoice 2: Fox Valley Packaging LLC FVP-22310, 1960.67, 4 lines. No flags. The stop-for-review path has not been exercised yet; it needs the problem invoices. |
| 3 | Created 6 fictional natural gas invoices as PDFs in `samples/invoices-gas/` (pipe, meters and regulators, odorant, locating, cathodic protection): 2 clean, 1 wrong total, 1 missing date, 1 duplicate number, 1 unknown vendor. Wrote `db/data/DLA_10_GAS_VENDORS.sql`. Page 2 now takes several files in one drop. | - | Files made and checked. Script not yet run. Invoices not yet uploaded. |
| 4 | Ran `db/data/DLA_10_GAS_VENDORS.sql` | DEV | Done. 9 vendors: the first 5 and the 4 gas vendors. |
| 5 | Dropped all 6 gas PDFs on page 2 in one drop | DEV and Local PC | Multi-file upload passed: documents 4 to 9 queued in file-name order and read one at a time, 267 to 300 seconds each, with nobody touching anything. |
| 6 | Ran `db/relay/DLA_09_PROCESS_STAGED.sql` to see each decision | DEV | 5 of 6 decisions right. Loaded by the agent: GAS_01 (MPP-48213, 6775.00), GAS_02 (CMR-10977, 7161.80). Stopped for a person, with the right reason: GAS_03 (subtotal 8,335.00 plus tax 0.00 is 8,335.00, but the total says 8,535.00), GAS_05 (duplicate of MPP-48213), GAS_06 (vendor not in the vendor list). **Wrong: GAS_04 was loaded.** It has no invoice date; the model put the due date, 12/12/2026, in the invoice date field, so the missing-date check saw a date and passed it. Also found: the model read "Tallulah Cathodic" as "Tallulah Catholic" on GAS_06 (first misread in 9 reads), and LOADED_BY shows the database user instead of AGENT. |
| 7 | Fixes written by Claude: `db/packages/DLA_02_PACKAGE.sql` (new check 9: an invoice date in the future is an error; LOADED_BY is now the approver), `db/data/DLA_11_GAS_TEST_FIXES.sql` (new prompt: the invoice date is only the date beside the Invoice Date label, never another date; copy names letter by letter; corrects LOADED_BY on invoices already loaded), `db/utilities/DLA_12_REREAD_DOCUMENT.sql` (takes document 7 back and queues it to be read and decided again). `db/relay/DLA_04_RELAY_DATABASE.sql` carries the same new prompt for a new install; it does not need to be run again. | - | Written. |
| 8 | Ran `db/packages/DLA_02_PACKAGE.sql`, `db/data/DLA_11_GAS_TEST_FIXES.sql`, then `db/utilities/DLA_12_REREAD_DOCUMENT.sql` for document 7 | DEV | All clean. LOADED_BY corrected to AGENT on the loaded invoices. Document 7 taken back and read again in 276 seconds. |
| 9 | Ran `db/relay/DLA_09_PROCESS_STAGED.sql` | DEV | Document 7 now stops for a person (IN_REVIEW): 6 of 6 gas decisions right. **But the new prompt did not work as intended.** The model still put the due date in the invoice date field, and it now returned both dates as 12/12/2026 instead of 2026-12-12. The invoice stopped only because that form could not be read as a date, so the invoice date came out empty. Two things learned: this model does not reliably follow the instruction, and the first new prompt changed the date form, which would also stop clean invoices. |
| 10 | Second fix written by Claude: `db/packages/DLA_02_PACKAGE.sql` now reads dates as YYYY-MM-DD or MM/DD/YYYY (new private function TEXT_TO_DATE), so a copied due date is read and then caught by the future-date check. Prompt in `db/data/DLA_11_GAS_TEST_FIXES.sql` (and `db/relay/DLA_04_RELAY_DATABASE.sql`) now also says to write every date as YYYY-MM-DD. `db/utilities/DLA_12_REREAD_DOCUMENT.sql` now takes a list of documents: 5 (GAS_02, clean, must load again) and 7 (GAS_04, must stop). | - | Written. |
| 11 | Gary ran the three files again. The first time, SQL Developer ran the old copy of `DLA_12` it still had open in a tab, so only document 7 was re-read (read 3 of document 7, 286 seconds). After reopening the files from disk he ran `db/packages/DLA_02_PACKAGE.sql`, `db/data/DLA_11_GAS_TEST_FIXES.sql` and `db/utilities/DLA_12_REREAD_DOCUMENT.sql` (documents 5 and 7). | DEV | Done. Lesson recorded in the format standard: tell him to reload a changed file in SQL Developer, and to click Refresh on the page after a script queues work. |
| 12 | Result of the re-reads, checked by Claude on the Upload Invoice page | DEV | **Passed.** Document 5 (GAS_02, clean) was read in 319 seconds and loaded again by the agent with the final prompt. Document 7 (GAS_04, no invoice date) stopped for a person, IN_REVIEW. All six gas invoices now end in the right place: 2 loaded, 4 stopped. Open: document 7's last read took only 60 seconds and its flag text has not been looked at; run `db/relay/DLA_09_PROCESS_STAGED.sql` and `db/relay/DLA_06_CHECK_EXTRACTIONS.sql` first thing next session. |
| 13 | Session closed. Project documents brought up to date by Claude: kickoff brief, response format standard (Rules 9 to 14 added), relay design notes, and a new handoff file, also saved here as `docs/DLA_SESSION_HANDOFF.md`. | - | Done. Next: the review page for stopped invoices. |

## 11/19/2026 - Phase 2: AI extraction (started)

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Checked PC hardware | Local PC | 32 GB RAM, Intel Iris Xe graphics. Models run on the processor. |
| 2 | Installed Ollama | Local PC | Done. |
| 3 | Pulled `llama3.2-vision` (7.8 GB) and tested | Local PC | Failed. Error: unknown model architecture 'mllama'. Llama 3.2 Vision is not supported on Ollama 0.30.0 and later. Model removed. |
| 4 | Pulled `qwen2.5vl:7b` (6.0 GB) | Local PC | Done. |
| 5 | Tested `qwen2.5vl:7b` on `samples/invoices/DLA_01_clean_prairie_fastener.png` | Local PC | Passed. Model answered invoice number INV-10001 and total due $364.00, both correct. |
| 6 | Ran `db/data/DLA_03_SET_LOCAL_MODEL.sql` | DEV, as ADMIN | Done. OLLAMA_MODEL = qwen2.5vl:7b. |
| 7 | Design decision | - | No ngrok. The local model is reached with a Node relay that calls out to ORDS, the same pattern as the Stick-IT print relay. |
| 8 | Ran `db/relay/DLA_04_RELAY_DATABASE.sql` | DEV, as WKSP_WKSPPRDWORKSPACE | Done, clean on the first run. DLA_RELAY_PKG VALID. Test: wrong token HTTP 401, right token HTTP 200 with an empty work list. ORDS module dla.relay has GET work and POST work/:extraction_id, both with header X-DLA-Relay-Token. ORDS path prd_workspace. |
| 9 | Wrote `relay/dla-relay.js` (Node, no npm packages) | - | Written. Tested by Claude against stand-in database and model servers: picks up work, calls the model, posts the answer, refuses a PDF with a clear error, reports a wrong token. Not yet run against DEV and Ollama. |
| 10 | Ran `db/relay/DLA_05_QUEUE_SAMPLE_INVOICE.sql` | DEV | Done. Sample invoice 1 loaded and queued as extraction 1. |
| 11 | First run of `relay/dla-relay.js` 1.0.0 | Local PC | Partly worked. The relay reached ORDS, the token was accepted, it picked up extraction 1 and posted an answer back. The call to Ollama failed: connect ECONNREFUSED ::1:11434. "localhost" resolved to the IPv6 address, where Ollama does not listen. Extraction 1 stored as ERROR. |
| 12 | Fixed `relay/dla-relay.js`, now 1.0.1 | Local | Done. Ollama address changed to http://127.0.0.1:11434. |
| 13 | Second run of `relay/dla-relay.js` 1.0.1, sample invoice queued again as extraction 2 | Local PC and DEV | Passed, end to end. Relay picked up the invoice from ORDS, qwen2.5vl:7b read it in 262 seconds, the relay posted the answer, the database stored it as valid JSON with status SUCCESS. |
| 14 | Ran `db/relay/DLA_06_CHECK_EXTRACTIONS.sql` | DEV | Every field correct against the sample invoice: vendor, invoice number INV-10001, invoice date 2026-11-02, due date 2026-12-02, all 3 lines (description, quantity, unit price, amount), subtotal 364.00, tax 0.00, total 364.00. Audit log shows the queue, the failed first attempt and the success. |
| 15 | Ran `db/packages/DLA_02_PACKAGE.sql` with PARSE_EXTRACTION built (JSON_TABLE into staging) | DEV | Done, clean on the first run. Package and body VALID. |
| 16 | Ran `db/relay/DLA_07_STAGE_LATEST_EXTRACTION.sql` | DEV | Passed. Extraction 2 staged as header 1: Prairie Fastener Supply Co. matched to vendor ID 1, INV-10001, dates 02-NOV-26 and 02-DEC-26, subtotal 364, tax 0, total 364, 3 lines (174, 78, 112). No flags. |
| 17 | Created APEX application 300, Document Loading Agent | DEV, DEV_WORKSPACE | Done. Home, Login and Global pages. |
| 18 | Ran `db/packages/DLA_02_PACKAGE.sql` (adds SUBMIT_DOCUMENT, the call behind the upload page) and `db/relay/DLA_04_RELAY_DATABASE.sql` (each answer is now staged automatically) | DEV, as WKSP_WKSPPRDWORKSPACE | Done, both clean. Packages VALID. Token unchanged. |
| 19 | Built page 2, Upload Invoice, in application 300 | DEV, Page Designer | Done and run. Drop zone, model select list, Read Invoice button, Submit document process, Documents report with Refresh. Icons on regions, buttons and the menu entry. |
| 20 | Tried to upload a PDF on page 2 | DEV, application 300 | Refused: the page only accepted PNG and JPG. Design fault: real invoices are PDFs. |
| 21 | Relay 1.1.0: converts each PDF page to a picture with pdftoppm (Poppler) before sending it to the model | Local | Written. Tested by Claude against stand-in servers with a real sample PDF: converted, sent as a PNG, answer posted. Not yet run against DEV and Ollama. Needs Poppler installed on the PC. |
| 22 | Installed Poppler 25.07.0 with winget; restarted the relay | Local PC | Done. Relay 1.1.0 start-up shows: PDFs converter found (pdftoppm). |
| 23 | Page 2 changed to accept PDF, PNG and JPG; unsaved-changes warning turned off; Read Status shows plain words with an icon; Seconds counts up live; the report refreshes itself every 30 seconds only while a read is in progress | DEV, Page Designer | Done and checked in the running page. |
| 24 | Uploaded `DLA_02_clean_fox_valley_packaging.pdf` by dragging it onto page 2 | DEV and Local PC | Passed, end to end, with nobody touching anything after the upload. Relay converted the PDF to a picture, qwen2.5vl:7b read it in 309 seconds, the answer was stored and staged automatically as header 2 with 4 lines. Every field correct: Fox Valley Packaging LLC, FVP-22310, 2026-11-05, 2026-12-05, 4 lines (840.00, 350.40, 324.00, 318.00), subtotal 1832.40, tax 128.27, total 1960.67. |

## 11/19/2026 - Phase 1: Foundation

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Ran `db/utilities/DLA_00_INVENTORY.sql` | DEV, as ADMIN | Done. Workspace DEV_WORKSPACE, schema WKSP_WKSPPRDWORKSPACE. No existing DLA_ objects. Application ID 300 chosen. |
| 2 | Created project folder and structure | Local, GitHub folder | Done. |
| 3 | Published repository `document-loading-agent` (private) | GitHub, with GitHub Desktop | Done. |
| 4 | Ran `db/tables/DLA_01_CREATE_TABLES.sql` | DEV, as ADMIN | Done. 10 tables created, all VALID. DLA_SETTINGS 5 rows, DLA_VENDORS 5 rows. |
| 5 | Ran `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | Failed. Package body did not compile: PLS-00231, a private function was called inside SQL statements. |
| 6 | Fixed `db/packages/DLA_02_PACKAGE.sql` | Local | Done. The user name is now read into a variable before the SQL statements. |
| 7 | Reran `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | Done. Package and package body VALID. Test returned ACTIVE_MODEL = OLLAMA and wrote audit row PHASE1_INSTALL. |
| 8 | Created 6 fictional sample invoices (PDF and PNG) | `samples/invoices/` | Done. |

**Phase 1 complete.** Next: Phase 2, AI extraction with both models.
