/* ============================================================
   Script      : DLA_04_RELAY_DATABASE.sql
   Project     : Document Loading Agent (DLA) - Phase 2
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES
                 1. DLA_EXTRACTIONS: status check now allows PENDING
                 2. DLA_SETTINGS: adds RELAY_TOKEN and
                    EXTRACTION_PROMPT if they are not there
                 3. Creates package DLA_RELAY_PKG
                 4. Creates ORDS module dla.relay (3 endpoints)
                 Touches nothing that does not start with DLA_
                 or dla.
   Purpose     : The database side of the invoice relay. Same
                 pattern as the Stick-IT print relay: the relay
                 on the PC calls OUT to ORDS, asks for work, and
                 posts the answer back. Nothing calls in.
                   GET  /ords/prd_workspace/dla/relay/work
                   POST /ords/prd_workspace/dla/relay/work/:extraction_id
                   POST /ords/prd_workspace/dla/relay/documents
                 All three need the header X-DLA-Relay-Token.
                 The third one (added 11/19/2026, late) is the
                 watched folder: the relay found a file in the
                 folder it watches and sends it in. The file is
                 stored in DLA_DOCUMENTS exactly as an upload on
                 page 2 is, and queued for the local model.
                 11/20/2026 (later): RECEIVE_DOCUMENT reads the
                 setting WATCH_MODEL (OLLAMA or OCI_GENAI) to
                 decide which reader the folder feeds. The
                 setting is added here with default OLLAMA if
                 missing; db\data\DLA_16_WATCH_MODEL.sql
                 changes it.
                 11/21/2026: compare page. QUEUE_EXTRACTION takes
                 P_PURPOSE (LOAD or COMPARE) and RECEIVE_RESULT
                 skips staging, the decision and the document
                 status for a COMPARE read, so page 4 can read a
                 document with both models without touching the
                 review queue. Needs the PURPOSE column from
                 DLA_17_COMPARE_COLUMN.sql; run that first.
   Re-run note : Re-running keeps the token, the prompt and
                 WATCH_MODEL (they are only inserted when
                 missing). Re-run this whole file after any
                 change to it.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE  <-- NOT ADMIN.
                 ORDS modules belong to the user that defines
                 them, the same as IMAGINARY_ORDS_ENDPOINTS.sql.
                 SQL Developer, F5 (Run Script)
   Run after   : DLA_03_SET_LOCAL_MODEL.sql
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Allow status PENDING on DLA_EXTRACTIONS
   Purpose : PENDING = waiting for the relay to pick it up.
             The constraint is dropped and added again so this
             step can be re-run.
   ------------------------------------------------------------ */
ALTER TABLE dla_extractions DROP CONSTRAINT dla_extractions_status_ck;

ALTER TABLE dla_extractions ADD CONSTRAINT dla_extractions_status_ck
    CHECK (status IN ('PENDING', 'RUNNING', 'SUCCESS', 'ERROR'));

/* ------------------------------------------------------------
   Step 2  : Settings
   Purpose : RELAY_TOKEN is the relay's password, generated once.
             EXTRACTION_PROMPT is the instruction both AI models
             get. Each row is added only if it is not there, so
             re-running never changes an existing token.
   ------------------------------------------------------------ */
INSERT INTO dla_settings (setting_name, setting_value, description)
SELECT 'RELAY_TOKEN',
       RAWTOHEX(SYS_GUID()) || RAWTOHEX(SYS_GUID()),
       'Token the DLA relay sends in the X-DLA-Relay-Token header'
FROM   dual
WHERE  NOT EXISTS (SELECT 1
                   FROM   dla_settings s
                   WHERE  s.setting_name = 'RELAY_TOKEN');

INSERT INTO dla_settings (setting_name, setting_value, description)
SELECT 'EXTRACTION_PROMPT',
       q'[You are reading a vendor invoice. Return only one JSON object, with no other text, using exactly these keys: vendor_name (string), invoice_number (string), invoice_date (string, YYYY-MM-DD), due_date (string, YYYY-MM-DD), subtotal (number), tax (number), total (number), line_items (array of objects with these keys: line_number (number), description (string), quantity (number), unit_price (number), amount (number)). Use null for any value that is not printed on the invoice. Do not calculate or guess missing values. invoice_date is only the date printed beside the label Invoice Date or Date. If that label has no date beside it, invoice_date must be null. Never use the due date, a ship date, a service date or an order date as the invoice date. Write every date as YYYY-MM-DD, even when the invoice prints it another way. Copy the vendor name and the invoice number exactly as printed, letter by letter. Copy numbers exactly as printed, without currency symbols or thousands separators.]',
       'Instruction sent to the AI model with every invoice'
FROM   dual
WHERE  NOT EXISTS (SELECT 1
                   FROM   dla_settings s
                   WHERE  s.setting_name = 'EXTRACTION_PROMPT');

INSERT INTO dla_settings (setting_name, setting_value, description)
SELECT 'WATCH_MODEL',
       'OLLAMA',
       'Which reader the watched folder feeds: OLLAMA (the relay) or OCI_GENAI (the APEX automation)'
FROM   dual
WHERE  NOT EXISTS (SELECT 1
                   FROM   dla_settings s
                   WHERE  s.setting_name = 'WATCH_MODEL');

COMMIT;

/* ------------------------------------------------------------
   Package spec : DLA_RELAY_PKG
   Purpose      : Logic behind the two relay endpoints, plus the
                  routine that puts an invoice in the queue.
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE dla_relay_pkg AUTHID DEFINER AS

    /* Puts one document in the queue for the local model.
       Returns the new EXTRACTION_ID. Does not commit.
       P_PURPOSE (11/21/2026): LOAD = stage and decide when the
       answer comes back (the normal path); COMPARE = keep the
       answer for the compare page only. */
    FUNCTION queue_extraction (
        p_document_id  IN NUMBER,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER;

    /* Relay asks for work. Hands out one PENDING extraction at
       a time and marks it RUNNING. Called by GET work. */
    PROCEDURE get_work (
        p_token        IN  VARCHAR2,
        p_result_json  OUT CLOB,
        p_http_status  OUT NUMBER
    );

    /* Relay posts the model's answer for one extraction.
       Called by POST work/:extraction_id. */
    PROCEDURE receive_result (
        p_extraction_id   IN  NUMBER,
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    );

    /* The relay sends in a file it found in the watched folder.
       Stores it in DLA_DOCUMENTS and queues it for the local
       model, the same as an upload on page 2.
       Called by POST documents. */
    PROCEDURE receive_document (
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_document_id     OUT NUMBER,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    );

END dla_relay_pkg;
/

SHOW ERRORS PACKAGE dla_relay_pkg

/* ------------------------------------------------------------
   Package body : DLA_RELAY_PKG
   Purpose      : Code for the spec above. Every routine logs a
                  failure to DLA_AUDIT_LOG. GET_WORK and
                  RECEIVE_RESULT report failures through their
                  OUT parameters so the endpoint can answer the
                  relay with a proper HTTP status.
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE BODY dla_relay_pkg AS

    /* --------------------------------------------------------
       Private : TOKEN_OK
       Purpose : TRUE when the token sent matches RELAY_TOKEN.
       -------------------------------------------------------- */
    FUNCTION token_ok (
        p_token  IN VARCHAR2
    ) RETURN BOOLEAN IS
        l_expected  dla_settings.setting_value%TYPE;
    BEGIN
        l_expected := dla_pkg.get_setting('RELAY_TOKEN');
        RETURN p_token IS NOT NULL
           AND l_expected IS NOT NULL
           AND p_token = l_expected;
    END token_ok;

    /* --------------------------------------------------------
       Private : ERROR_JSON
       Purpose : {"status":"ERROR","message":"..."} as a CLOB.
       -------------------------------------------------------- */
    FUNCTION error_json (
        p_message  IN VARCHAR2
    ) RETURN CLOB IS
        l_json  CLOB;
    BEGIN
        APEX_JSON.INITIALIZE_CLOB_OUTPUT;
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status',  'ERROR');
        APEX_JSON.WRITE('message', p_message);
        APEX_JSON.CLOSE_OBJECT;
        l_json := APEX_JSON.GET_CLOB_OUTPUT;
        APEX_JSON.FREE_OUTPUT;
        RETURN l_json;
    END error_json;

    /* --------------------------------------------------------
       Public  : QUEUE_EXTRACTION
       -------------------------------------------------------- */
    FUNCTION queue_extraction (
        p_document_id  IN NUMBER,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER IS
        l_model_code     dla_extractions.model_code%TYPE;
        l_model_name     dla_extractions.model_name%TYPE;
        l_purpose        dla_extractions.purpose%TYPE;
        l_count          NUMBER;
        l_extraction_id  dla_extractions.extraction_id%TYPE;
    BEGIN
        l_model_code := dla_pkg.c_model_ollama;
        l_model_name := dla_pkg.get_setting('OLLAMA_MODEL');
        l_purpose    := UPPER(TRIM(NVL(p_purpose, 'LOAD')));

        IF l_purpose NOT IN ('LOAD', 'COMPARE') THEN
            RAISE_APPLICATION_ERROR(
                -20020,
                'DLA_RELAY_PKG.QUEUE_EXTRACTION: P_PURPOSE must be LOAD or COMPARE, not ' || p_purpose || '.'
            );
        END IF;

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_documents d
        WHERE  d.document_id = p_document_id;

        IF l_count = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20020,
                'DLA_RELAY_PKG.QUEUE_EXTRACTION: there is no document ' || p_document_id || '.'
            );
        END IF;

        INSERT INTO dla_extractions (
            document_id,
            model_code,
            model_name,
            status,
            purpose
        ) VALUES (
            p_document_id,
            l_model_code,
            l_model_name,
            'PENDING',
            l_purpose
        )
        RETURNING extraction_id INTO l_extraction_id;

        dla_pkg.log_audit(
            p_action      => 'EXTRACTION_QUEUED',
            p_details     => 'Extraction ' || l_extraction_id || ' queued for ' || l_model_name
                             || CASE WHEN l_purpose = 'COMPARE' THEN ' (compare only)' END || '.',
            p_document_id => p_document_id
        );

        RETURN l_extraction_id;
    EXCEPTION
        WHEN OTHERS THEN
            dla_pkg.log_audit(
                p_action      => 'RELAY_ERROR',
                p_details     => 'QUEUE_EXTRACTION failed: ' || SQLERRM,
                p_document_id => p_document_id
            );
            RAISE;
    END queue_extraction;

    /* --------------------------------------------------------
       Public  : GET_WORK
       Answer  : {"status":"OK","work":[ {extraction_id,
                  document_id, file_name, mime_type, model,
                  prompt, image_base64} ]}
                 An empty queue is "work":[].
       -------------------------------------------------------- */
    PROCEDURE get_work (
        p_token        IN  VARCHAR2,
        p_result_json  OUT CLOB,
        p_http_status  OUT NUMBER
    ) IS
        l_model_code     dla_extractions.model_code%TYPE;
        l_prompt         dla_settings.setting_value%TYPE;
        l_extraction_id  dla_extractions.extraction_id%TYPE;
        l_document_id    dla_extractions.document_id%TYPE;
        l_model_name     dla_extractions.model_name%TYPE;
        l_file_name      dla_documents.file_name%TYPE;
        l_mime_type      dla_documents.mime_type%TYPE;
        l_blob           BLOB;
        l_base64         CLOB;
        l_error          VARCHAR2(4000);
    BEGIN
        p_http_status := 200;

        IF NOT token_ok(p_token) THEN
            p_http_status := 401;
            p_result_json := error_json('Relay token is missing or wrong.');
            RETURN;
        END IF;

        l_model_code := dla_pkg.c_model_ollama;
        l_prompt     := dla_pkg.get_setting('EXTRACTION_PROMPT');

        BEGIN
            SELECT q.extraction_id
            INTO   l_extraction_id
            FROM   (SELECT e.extraction_id
                    FROM   dla_extractions e
                    WHERE  e.status     = 'PENDING'
                    AND    e.model_code = l_model_code
                    ORDER  BY e.extraction_id) q
            WHERE  ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_extraction_id := NULL;
        END;

        IF l_extraction_id IS NOT NULL THEN
            SELECT e.document_id,
                   e.model_name,
                   d.file_name,
                   d.mime_type,
                   d.file_blob
            INTO   l_document_id,
                   l_model_name,
                   l_file_name,
                   l_mime_type,
                   l_blob
            FROM   dla_extractions e,
                   dla_documents   d
            WHERE  d.document_id   = e.document_id
            AND    e.extraction_id = l_extraction_id;

            UPDATE dla_extractions e
            SET    e.status     = 'RUNNING',
                   e.started_on = SYSTIMESTAMP
            WHERE  e.extraction_id = l_extraction_id;

            l_base64 := APEX_WEB_SERVICE.BLOB2CLOBBASE64(l_blob);
        END IF;

        APEX_JSON.INITIALIZE_CLOB_OUTPUT;
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'OK');
        APEX_JSON.OPEN_ARRAY('work');

        IF l_extraction_id IS NOT NULL THEN
            APEX_JSON.OPEN_OBJECT;
            APEX_JSON.WRITE('extraction_id', l_extraction_id);
            APEX_JSON.WRITE('document_id',   l_document_id);
            APEX_JSON.WRITE('file_name',     l_file_name);
            APEX_JSON.WRITE('mime_type',     l_mime_type);
            APEX_JSON.WRITE('model',         l_model_name);
            APEX_JSON.WRITE('prompt',        l_prompt);
            APEX_JSON.WRITE('image_base64',  l_base64);
            APEX_JSON.CLOSE_OBJECT;
        END IF;

        APEX_JSON.CLOSE_ARRAY;
        APEX_JSON.CLOSE_OBJECT;
        p_result_json := APEX_JSON.GET_CLOB_OUTPUT;
        APEX_JSON.FREE_OUTPUT;
    EXCEPTION
        WHEN OTHERS THEN
            l_error := SQLERRM;
            ROLLBACK;
            dla_pkg.log_audit(
                p_action  => 'RELAY_ERROR',
                p_details => 'GET_WORK failed: ' || l_error
            );
            p_http_status := 500;
            p_result_json := error_json('GET_WORK failed. See DLA_AUDIT_LOG.');
    END get_work;

    /* --------------------------------------------------------
       Public  : RECEIVE_RESULT
       Body    : {"status":"SUCCESS" or "ERROR",
                  "raw_response":"...", "elapsed_ms":n,
                  "message":"..."}
       A SUCCESS whose raw_response is not valid JSON is stored
       as ERROR, with the raw text kept for review.
       A valid answer is staged straight away with
       DLA_PKG.PARSE_EXTRACTION, then checked and decided with
       DLA_PKG.PROCESS_STAGING: a clean invoice is approved and
       loaded by the agent, anything flagged waits for a person.
       If staging or checking fails, what was done before it is
       kept and the failure is in DLA_AUDIT_LOG.
       -------------------------------------------------------- */
    PROCEDURE receive_result (
        p_extraction_id   IN  NUMBER,
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    ) IS
        l_obj          JSON_OBJECT_T;
        l_status       VARCHAR2(20);
        l_elapsed      NUMBER;
        l_raw          CLOB;
        l_message      VARCHAR2(4000);
        l_count        NUMBER;
        l_is_json      NUMBER := 0;
        l_document_id  dla_extractions.document_id%TYPE;
        l_purpose      dla_extractions.purpose%TYPE;
        l_stg_header   NUMBER;
        l_invoice_id   NUMBER;
        l_flag_count   NUMBER;
        l_error        VARCHAR2(4000);
    BEGIN
        p_http_status    := 200;
        p_result_status  := 'OK';
        p_result_message := 'Result stored.';

        IF NOT token_ok(p_token) THEN
            p_http_status    := 401;
            p_result_status  := 'ERROR';
            p_result_message := 'Relay token is missing or wrong.';
            RETURN;
        END IF;

        IF p_body IS NULL THEN
            p_http_status    := 400;
            p_result_status  := 'ERROR';
            p_result_message := 'The request has no body.';
            RETURN;
        END IF;

        BEGIN
            l_obj := JSON_OBJECT_T.PARSE(p_body);
        EXCEPTION
            WHEN OTHERS THEN
                p_http_status    := 400;
                p_result_status  := 'ERROR';
                p_result_message := 'The request body is not valid JSON.';
                RETURN;
        END;

        l_status  := UPPER(SUBSTR(l_obj.GET_STRING('status'), 1, 20));
        l_elapsed := l_obj.GET_NUMBER('elapsed_ms');
        l_raw     := l_obj.GET_CLOB('raw_response');
        l_message := SUBSTR(l_obj.GET_STRING('message'), 1, 4000);

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_extractions e
        WHERE  e.extraction_id = p_extraction_id
        AND    e.status        = 'RUNNING';

        IF l_count = 0 THEN
            p_http_status    := 404;
            p_result_status  := 'ERROR';
            p_result_message := 'Extraction ' || p_extraction_id || ' is not waiting for an answer.';
            RETURN;
        END IF;

        SELECT e.purpose
        INTO   l_purpose
        FROM   dla_extractions e
        WHERE  e.extraction_id = p_extraction_id;

        IF l_status = 'SUCCESS' AND l_raw IS NOT NULL THEN
            SELECT CASE WHEN l_raw IS JSON THEN 1 ELSE 0 END
            INTO   l_is_json
            FROM   dual;
        END IF;

        IF l_status = 'SUCCESS' AND l_is_json = 1 THEN
            UPDATE dla_extractions e
            SET    e.status         = 'SUCCESS',
                   e.elapsed_ms     = l_elapsed,
                   e.raw_response   = l_raw,
                   e.extracted_json = l_raw,
                   e.error_message  = NULL
            WHERE  e.extraction_id  = p_extraction_id
            RETURNING e.document_id INTO l_document_id;

            dla_pkg.log_audit(
                p_action      => 'EXTRACTION_SUCCESS',
                p_details     => 'Extraction ' || p_extraction_id || ' answered in ' || l_elapsed || ' ms'
                                 || CASE WHEN l_purpose = 'COMPARE' THEN ' (compare only, not staged)' END || '.',
                p_document_id => l_document_id
            );

            /* A COMPARE read stops here: the answer is kept for
               page 4; the document and the review queue are left
               as they were. */
            IF l_purpose = 'COMPARE' THEN
                p_result_message := 'Compare result stored.';
                RETURN;
            END IF;

            UPDATE dla_documents d
            SET    d.status      = 'EXTRACTED'
            WHERE  d.document_id = l_document_id;

            /* Stage the answer. A staging failure must not lose
               the answer, so it is undone back to this point and
               reported; PARSE_EXTRACTION has already logged it. */
            SAVEPOINT before_staging;
            BEGIN
                l_stg_header     := dla_pkg.parse_extraction(p_extraction_id);
                p_result_message := 'Result stored and staged as header ' || l_stg_header || '.';
            EXCEPTION
                WHEN OTHERS THEN
                    l_error := SQLERRM;
                    ROLLBACK TO before_staging;
                    l_stg_header     := NULL;
                    p_result_message := 'Result stored. Staging failed: ' || SUBSTR(l_error, 1, 300);
            END;

            /* The agent's decision: check it, then load it or
               leave it for a person. A failure here keeps the
               staged rows. */
            IF l_stg_header IS NOT NULL THEN
                SAVEPOINT before_decision;
                BEGIN
                    dla_pkg.process_staging(
                        p_stg_header_id => l_stg_header,
                        p_invoice_id    => l_invoice_id,
                        p_flag_count    => l_flag_count
                    );
                    IF l_invoice_id IS NOT NULL THEN
                        p_result_message := 'Read, checked and loaded as invoice ' || l_invoice_id || '. No person needed.';
                    ELSE
                        p_result_message := 'Read and checked: ' || l_flag_count || ' flag(s). Waiting for a person to review.';
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_error := SQLERRM;
                        ROLLBACK TO before_decision;
                        p_result_message := 'Result stored and staged. Checking failed: ' || SUBSTR(l_error, 1, 300);
                END;
            END IF;
        ELSE
            IF l_status = 'SUCCESS' THEN
                l_error := 'The model answered, but the answer is not valid JSON.';
            ELSE
                l_error := NVL(l_message, 'The relay reported an error with no message.');
            END IF;

            UPDATE dla_extractions e
            SET    e.status         = 'ERROR',
                   e.elapsed_ms     = l_elapsed,
                   e.raw_response   = l_raw,
                   e.error_message  = l_error
            WHERE  e.extraction_id  = p_extraction_id
            RETURNING e.document_id INTO l_document_id;

            IF l_purpose = 'LOAD' THEN
                UPDATE dla_documents d
                SET    d.status      = 'ERROR'
                WHERE  d.document_id = l_document_id;
            END IF;

            dla_pkg.log_audit(
                p_action      => 'EXTRACTION_ERROR',
                p_details     => 'Extraction ' || p_extraction_id || ': ' || l_error,
                p_document_id => l_document_id
            );

            p_result_message := 'Result stored as ERROR: ' || SUBSTR(l_error, 1, 400);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            l_error := SQLERRM;
            ROLLBACK;
            dla_pkg.log_audit(
                p_action  => 'RELAY_ERROR',
                p_details => 'RECEIVE_RESULT failed for extraction ' || p_extraction_id || ': ' || l_error
            );
            p_http_status    := 500;
            p_result_status  := 'ERROR';
            p_result_message := 'RECEIVE_RESULT failed. See DLA_AUDIT_LOG.';
    END receive_result;

    /* --------------------------------------------------------
       Public  : RECEIVE_DOCUMENT   (watched folder)
       Body    : {"file_name":"GAS_01.pdf",
                  "mime_type":"application/pdf",
                  "file_base64":"....",
                  "source":"C:\DLA\inbox"}
       What    : The same two steps SUBMIT_DOCUMENT does for an
                 upload on page 2: insert the file into
                 DLA_DOCUMENTS, then queue it for the local model
                 with QUEUE_EXTRACTION. UPLOADED_BY records that
                 the watched folder sent it, so the audit trail
                 shows no person touched it.
       Checks  : file name, type and content must be there; only
                 PDF, PNG and JPG are taken. The same file dropped
                 twice is NOT refused here on purpose: the relay
                 moves each file out of the folder once it is
                 sent, and the invoice-level duplicate check in
                 DLA_PKG.VALIDATE_STAGING is the real guard (it
                 stops the invoice for a person).
       -------------------------------------------------------- */
    PROCEDURE receive_document (
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_document_id     OUT NUMBER,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    ) IS
        l_obj            JSON_OBJECT_T;
        l_file_name      dla_documents.file_name%TYPE;
        l_mime_type      dla_documents.mime_type%TYPE;
        l_source         VARCHAR2(400);
        l_base64         CLOB;
        l_blob           BLOB;
        l_document_id    dla_documents.document_id%TYPE;
        l_extraction_id  NUMBER;
        l_watch_model    VARCHAR2(30);
        l_error          VARCHAR2(4000);
    BEGIN
        p_http_status    := 200;
        p_result_status  := 'OK';
        p_result_message := 'Stored.';
        p_document_id    := NULL;

        IF NOT token_ok(p_token) THEN
            p_http_status    := 401;
            p_result_status  := 'ERROR';
            p_result_message := 'Relay token is missing or wrong.';
            RETURN;
        END IF;

        IF p_body IS NULL THEN
            p_http_status    := 400;
            p_result_status  := 'ERROR';
            p_result_message := 'The request has no body.';
            RETURN;
        END IF;

        BEGIN
            l_obj := JSON_OBJECT_T.PARSE(p_body);
        EXCEPTION
            WHEN OTHERS THEN
                p_http_status    := 400;
                p_result_status  := 'ERROR';
                p_result_message := 'The request body is not valid JSON.';
                RETURN;
        END;

        l_file_name := SUBSTR(TRIM(l_obj.GET_STRING('file_name')), 1, 400);
        l_mime_type := LOWER(SUBSTR(TRIM(l_obj.GET_STRING('mime_type')), 1, 255));
        l_source    := SUBSTR(TRIM(l_obj.GET_STRING('source')), 1, 400);
        l_base64    := l_obj.GET_CLOB('file_base64');

        IF l_file_name IS NULL OR l_mime_type IS NULL
           OR l_base64 IS NULL OR DBMS_LOB.GETLENGTH(l_base64) = 0 THEN
            p_http_status    := 400;
            p_result_status  := 'ERROR';
            p_result_message := 'file_name, mime_type and file_base64 are all needed.';
            RETURN;
        END IF;

        IF l_mime_type NOT IN ('application/pdf', 'image/png', 'image/jpeg') THEN
            p_http_status    := 400;
            p_result_status  := 'ERROR';
            p_result_message := 'Only PDF, PNG and JPG files are read. This file is ' || l_mime_type || '.';
            RETURN;
        END IF;

        l_blob := APEX_WEB_SERVICE.CLOBBASE642BLOB(l_base64);

        IF l_blob IS NULL OR DBMS_LOB.GETLENGTH(l_blob) = 0 THEN
            p_http_status    := 400;
            p_result_status  := 'ERROR';
            p_result_message := 'The file content is empty.';
            RETURN;
        END IF;

        INSERT INTO dla_documents (
            file_name,
            mime_type,
            file_blob,
            file_size,
            uploaded_by
        ) VALUES (
            l_file_name,
            l_mime_type,
            l_blob,
            DBMS_LOB.GETLENGTH(l_blob),
            'WATCHED_FOLDER'
        )
        RETURNING document_id INTO l_document_id;

        dla_pkg.log_audit(
            p_action      => 'UPLOADED',
            p_details     => l_file_name || ' picked up by the relay from the watched folder'
                             || CASE WHEN l_source IS NOT NULL THEN ' ' || l_source END
                             || '. No person involved.',
            p_document_id => l_document_id
        );

        /* WATCH_MODEL decides which reader the folder feeds.
           OLLAMA: queue it for the relay, as before.
           OCI_GENAI: leave it UPLOADED with no read; the APEX
           automation "Read waiting documents" picks it up within
           a minute and calls DLA_PKG.EXTRACT_DOCUMENT (which needs
           the APEX session the automation has and ORDS does not). */
        l_watch_model := UPPER(TRIM(dla_pkg.get_setting('WATCH_MODEL')));

        IF l_watch_model = dla_pkg.c_model_oci THEN
            p_document_id    := l_document_id;
            p_result_message := 'Stored as document ' || l_document_id
                                || '. Waiting for the OCI reader (within a minute).';
        ELSE
            l_extraction_id  := queue_extraction(l_document_id);
            p_document_id    := l_document_id;
            p_result_message := 'Stored as document ' || l_document_id
                                || ' and queued as extraction ' || l_extraction_id || ' for the local model.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            l_error := SQLERRM;
            ROLLBACK;
            dla_pkg.log_audit(
                p_action  => 'RELAY_ERROR',
                p_details => 'RECEIVE_DOCUMENT failed for ' || NVL(l_file_name, '(no name)') || ': ' || l_error
            );
            p_http_status    := 500;
            p_result_status  := 'ERROR';
            p_result_message := 'RECEIVE_DOCUMENT failed. See DLA_AUDIT_LOG.';
    END receive_document;

END dla_relay_pkg;
/

SHOW ERRORS PACKAGE BODY dla_relay_pkg

/* ------------------------------------------------------------
   Step 4  : ORDS module dla.relay
   Purpose : The two endpoints the relay calls. Built the same
             way as IMAGINARY_ORDS_ENDPOINTS.sql: thin handlers
             that call the package. DEFINE_MODULE replaces the
             whole module, so this step can be re-run.
             Stops with ORA-20030 if not run as
             WKSP_WKSPPRDWORKSPACE.
   ------------------------------------------------------------ */
BEGIN
    IF USER <> 'WKSP_WKSPPRDWORKSPACE' THEN
        RAISE_APPLICATION_ERROR(
            -20030,
            'Step 4 must be run on the WKSP_WKSPPRDWORKSPACE connection, not ' || USER
            || '. Switch connections and run this whole file again.'
        );
    END IF;

    ORDS.DEFINE_MODULE(
        p_module_name    => 'dla.relay',
        p_base_path      => '/dla/relay/',
        p_items_per_page => 0,
        p_status         => 'PUBLISHED',
        p_comments       => 'Document Loading Agent relay: asks for invoices to read and posts the answers.'
    );

    /* GET work -- the relay asks for its work. */
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'dla.relay',
        p_pattern     => 'work',
        p_priority    => 0,
        p_etag_type   => 'NONE',
        p_comments    => 'The relay asking for work.'
    );

    ORDS.DEFINE_HANDLER(
        p_module_name   => 'dla.relay',
        p_pattern       => 'work',
        p_method        => 'GET',
        p_source_type   => 'plsql/block',
        p_comments      => 'Relay asks for work. Logic in DLA_RELAY_PKG.GET_WORK.',
        p_source        => q'~
DECLARE
    l_result_json CLOB;
    l_http_status NUMBER;
    l_len         NUMBER;
    l_pos         NUMBER;
BEGIN
    DLA_RELAY_PKG.GET_WORK(
        p_token       => :relay_token,
        p_result_json => l_result_json,
        p_http_status => l_http_status
    );

    :status_code := l_http_status;

    OWA_UTIL.MIME_HEADER('application/json', FALSE);
    OWA_UTIL.HTTP_HEADER_CLOSE;

    -- An invoice image is far over 32K, so the answer is sent in pieces.
    l_len := NVL(DBMS_LOB.GETLENGTH(l_result_json), 0);
    l_pos := 1;
    WHILE l_pos <= l_len LOOP
        HTP.PRN(DBMS_LOB.SUBSTR(l_result_json, 8000, l_pos));
        l_pos := l_pos + 8000;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        :status_code := 500;
        OWA_UTIL.MIME_HEADER('application/json', FALSE);
        OWA_UTIL.HTTP_HEADER_CLOSE;
        HTP.P('{"status":"ERROR","message":"Internal error."}');
END;
~'
    );

    ORDS.DEFINE_PARAMETER(
        p_module_name        => 'dla.relay',
        p_pattern            => 'work',
        p_method             => 'GET',
        p_name               => 'X-DLA-Relay-Token',
        p_bind_variable_name => 'relay_token',
        p_source_type        => 'HEADER',
        p_param_type         => 'STRING',
        p_access_method      => 'IN',
        p_comments           => 'The relay token from DLA_SETTINGS.'
    );

    /* POST work/:extraction_id -- the relay answers one extraction. */
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'dla.relay',
        p_pattern     => 'work/:extraction_id',
        p_priority    => 0,
        p_etag_type   => 'NONE',
        p_comments    => 'The relay answering one extraction.'
    );

    ORDS.DEFINE_HANDLER(
        p_module_name   => 'dla.relay',
        p_pattern       => 'work/:extraction_id',
        p_method        => 'POST',
        p_source_type   => 'plsql/block',
        p_mimes_allowed => 'application/json',
        p_comments      => 'Relay answers one extraction. Logic in DLA_RELAY_PKG.RECEIVE_RESULT.',
        p_source        => q'~
DECLARE
    l_extraction_id   NUMBER;
    l_body            CLOB;
    l_result_status   VARCHAR2(20);
    l_result_message  VARCHAR2(500);
    l_http_status     NUMBER;
    l_resp            CLOB;

    PROCEDURE send_json(p_resp_status IN VARCHAR2, p_resp_message IN VARCHAR2) IS
    BEGIN
        APEX_JSON.INITIALIZE_CLOB_OUTPUT;
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status',  p_resp_status);
        APEX_JSON.WRITE('message', p_resp_message);
        APEX_JSON.CLOSE_OBJECT;
        l_resp := APEX_JSON.GET_CLOB_OUTPUT;
        APEX_JSON.FREE_OUTPUT;

        OWA_UTIL.MIME_HEADER('application/json', FALSE);
        OWA_UTIL.HTTP_HEADER_CLOSE;
        HTP.P(l_resp);
    END send_json;
BEGIN
    l_extraction_id := :extraction_id;
    l_body          := :body_text;

    DLA_RELAY_PKG.RECEIVE_RESULT(
        p_extraction_id  => l_extraction_id,
        p_token          => :relay_token,
        p_body           => l_body,
        p_result_status  => l_result_status,
        p_result_message => l_result_message,
        p_http_status    => l_http_status
    );

    :status_code := l_http_status;
    send_json(l_result_status, l_result_message);

EXCEPTION
    WHEN OTHERS THEN
        :status_code := 500;
        send_json('ERROR', SUBSTR(SQLERRM, 1, 400));
END;
~'
    );

    ORDS.DEFINE_PARAMETER(
        p_module_name        => 'dla.relay',
        p_pattern            => 'work/:extraction_id',
        p_method             => 'POST',
        p_name               => 'X-DLA-Relay-Token',
        p_bind_variable_name => 'relay_token',
        p_source_type        => 'HEADER',
        p_param_type         => 'STRING',
        p_access_method      => 'IN',
        p_comments           => 'The relay token from DLA_SETTINGS.'
    );

    /* POST documents -- the relay sends in a file from the watched folder. */
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'dla.relay',
        p_pattern     => 'documents',
        p_priority    => 0,
        p_etag_type   => 'NONE',
        p_comments    => 'The relay sending in a file it found in the watched folder.'
    );

    ORDS.DEFINE_HANDLER(
        p_module_name   => 'dla.relay',
        p_pattern       => 'documents',
        p_method        => 'POST',
        p_source_type   => 'plsql/block',
        p_mimes_allowed => 'application/json',
        p_comments      => 'Relay sends in a file. Logic in DLA_RELAY_PKG.RECEIVE_DOCUMENT.',
        p_source        => q'~
DECLARE
    l_body            CLOB;
    l_document_id     NUMBER;
    l_result_status   VARCHAR2(20);
    l_result_message  VARCHAR2(500);
    l_http_status     NUMBER;
    l_resp            CLOB;

    PROCEDURE send_json(p_resp_status IN VARCHAR2, p_resp_message IN VARCHAR2, p_doc_id IN NUMBER) IS
    BEGIN
        APEX_JSON.INITIALIZE_CLOB_OUTPUT;
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status',      p_resp_status);
        APEX_JSON.WRITE('message',     p_resp_message);
        APEX_JSON.WRITE('document_id', p_doc_id);
        APEX_JSON.CLOSE_OBJECT;
        l_resp := APEX_JSON.GET_CLOB_OUTPUT;
        APEX_JSON.FREE_OUTPUT;

        OWA_UTIL.MIME_HEADER('application/json', FALSE);
        OWA_UTIL.HTTP_HEADER_CLOSE;
        HTP.P(l_resp);
    END send_json;
BEGIN
    l_body := :body_text;

    DLA_RELAY_PKG.RECEIVE_DOCUMENT(
        p_token          => :relay_token,
        p_body           => l_body,
        p_document_id    => l_document_id,
        p_result_status  => l_result_status,
        p_result_message => l_result_message,
        p_http_status    => l_http_status
    );

    :status_code := l_http_status;
    send_json(l_result_status, l_result_message, l_document_id);

EXCEPTION
    WHEN OTHERS THEN
        :status_code := 500;
        send_json('ERROR', SUBSTR(SQLERRM, 1, 400), NULL);
END;
~'
    );

    ORDS.DEFINE_PARAMETER(
        p_module_name        => 'dla.relay',
        p_pattern            => 'documents',
        p_method             => 'POST',
        p_name               => 'X-DLA-Relay-Token',
        p_bind_variable_name => 'relay_token',
        p_source_type        => 'HEADER',
        p_param_type         => 'STRING',
        p_access_method      => 'IN',
        p_comments           => 'The relay token from DLA_SETTINGS.'
    );

    COMMIT;
END;
/

/* ------------------------------------------------------------
   Test 1  : Call GET_WORK the way the endpoint will
   Purpose : Proves the package runs. Expect:
               Wrong token : HTTP 401
               Right token : HTTP 200 {"status":"OK","work":[]}
             The token itself is never printed.
   ------------------------------------------------------------ */
DECLARE
    l_json    CLOB;
    l_status  NUMBER;
BEGIN
    dla_relay_pkg.get_work(
        p_token       => 'wrong-token',
        p_result_json => l_json,
        p_http_status => l_status
    );
    DBMS_OUTPUT.PUT_LINE('Wrong token : HTTP ' || l_status);

    dla_relay_pkg.get_work(
        p_token       => dla_pkg.get_setting('RELAY_TOKEN'),
        p_result_json => l_json,
        p_http_status => l_status
    );
    DBMS_OUTPUT.PUT_LINE('Right token : HTTP ' || l_status || ' ' || DBMS_LOB.SUBSTR(l_json, 200, 1));
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('TEST FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Test 2  : Call RECEIVE_DOCUMENT with bad input
   Purpose : Proves the watched-folder endpoint refuses what it
             should, without storing anything. Expect:
               Wrong token : HTTP 401
               Not a PDF   : HTTP 400 (Only PDF, PNG and JPG ...)
             Nothing is inserted, so nothing to roll back.
   ------------------------------------------------------------ */
DECLARE
    l_doc_id   NUMBER;
    l_status   VARCHAR2(20);
    l_message  VARCHAR2(500);
    l_http     NUMBER;
BEGIN
    dla_relay_pkg.receive_document(
        p_token          => 'wrong-token',
        p_body           => '{"file_name":"x.pdf","mime_type":"application/pdf","file_base64":"JVBERg=="}',
        p_document_id    => l_doc_id,
        p_result_status  => l_status,
        p_result_message => l_message,
        p_http_status    => l_http
    );
    DBMS_OUTPUT.PUT_LINE('Wrong token : HTTP ' || l_http || ' ' || l_message);

    dla_relay_pkg.receive_document(
        p_token          => dla_pkg.get_setting('RELAY_TOKEN'),
        p_body           => '{"file_name":"notes.txt","mime_type":"text/plain","file_base64":"aGVsbG8="}',
        p_document_id    => l_doc_id,
        p_result_status  => l_status,
        p_result_message => l_message,
        p_http_status    => l_http
    );
    DBMS_OUTPUT.PUT_LINE('Not a PDF   : HTTP ' || l_http || ' ' || l_message);
END;
/

/* ------------------------------------------------------------
   Check 1 : Package status
   Purpose : Expect PACKAGE and PACKAGE BODY, both VALID.
   ------------------------------------------------------------ */
SELECT object_type,
       object_name,
       status
FROM   all_objects
WHERE  owner = 'WKSP_WKSPPRDWORKSPACE'
AND    object_name = 'DLA_RELAY_PKG'
ORDER  BY object_type;

/* ------------------------------------------------------------
   Check 2 : ORDS endpoints
   Purpose : Expect 3 rows: POST documents, GET work and
             POST work/:extraction_id, each with header
             X-DLA-Relay-Token bound.
   ------------------------------------------------------------ */
SELECT t.uri_template,
       h.method,
       h.source_type,
       p.name AS header_param,
       p.bind_variable_name
FROM   user_ords_templates  t,
       user_ords_handlers   h,
       user_ords_parameters p
WHERE  h.template_id = t.id
AND    p.handler_id (+) = h.id
AND    t.module_id = (SELECT m.id
                      FROM   user_ords_modules m
                      WHERE  m.name = 'dla.relay')
ORDER  BY t.uri_template,
          h.method;

/* ------------------------------------------------------------
   Check 3 : ORDS path for this schema
   Purpose : PATTERN is the part after /ords/ in the relay's
             address. Expect prd_workspace.
   ------------------------------------------------------------ */
SELECT id,
       parsing_schema,
       type,
       pattern,
       status
FROM   user_ords_schemas;
