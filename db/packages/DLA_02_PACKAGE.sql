/* ============================================================
   Script      : DLA_02_PACKAGE.sql
   Project     : Document Loading Agent (DLA) - Phase 1
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - creates or replaces package DLA_PKG (spec
                 and body). Changes no data.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Run after   : DLA_01_CREATE_TABLES.sql and
                 DLA_08_VALIDATION_COLUMNS.sql
   11/20/2026  : EXTRACT_DOCUMENT built: the OCI Generative AI
                 reader (Google Gemini 2.5 Flash on OCI, the PDF
                 sent as a document, no relay). Settings it reads
                 come from DLA_13_OCI_MODEL.sql.
                 READ_WAITING_DOCUMENTS added for the APEX
                 automation (watched folder -> OCI).
   11/21/2026  : Compare page support. EXTRACT_DOCUMENT takes
                 P_PURPOSE (LOAD or COMPARE); a COMPARE read is
                 stored and shown but never staged or loaded.
                 COMPARE_DOCUMENT added: one call reads a
                 document with OCI now and queues it for the
                 local model, both marked COMPARE.
                 Needs the PURPOSE column from
                 DLA_17_COMPARE_COLUMN.sql.
   Note        : SUBMIT_DOCUMENT calls DLA_RELAY_PKG. On a brand
                 new install, where DLA_04_RELAY_DATABASE.sql has
                 not been run yet, the body shows a compile error
                 here. Run DLA_04, then run this file again.
   Re-runnable : yes (CREATE OR REPLACE)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Package spec : DLA_PKG
   Purpose      : The core package behind the Document Loading
                  Agent. Working: LOG_AUDIT, GET_SETTING,
                  SET_SETTING, SUBMIT_DOCUMENT, PARSE_EXTRACTION,
                  VALIDATE_STAGING, PROCESS_STAGING, LOAD_INVOICE,
                  and EXTRACT_DOCUMENT (the OCI model, 11/20/2026).
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE dla_pkg AUTHID DEFINER AS

    c_model_ollama  CONSTANT VARCHAR2(30) := 'OLLAMA';
    c_model_oci     CONSTANT VARCHAR2(30) := 'OCI_GENAI';

    /* Working in Phase 1: writes one audit row in its own transaction. */
    PROCEDURE log_audit (
        p_action       IN VARCHAR2,
        p_details      IN VARCHAR2 DEFAULT NULL,
        p_document_id  IN NUMBER   DEFAULT NULL
    );

    /* Working in Phase 1: returns a value from DLA_SETTINGS. */
    FUNCTION get_setting (
        p_setting_name  IN VARCHAR2
    ) RETURN VARCHAR2;

    /* Working in Phase 1: changes a value in DLA_SETTINGS. */
    PROCEDURE set_setting (
        p_setting_name   IN VARCHAR2,
        p_setting_value  IN VARCHAR2
    );

    /* Working: called by the APEX upload page. Copies the file
       the user just uploaded from APEX's temporary upload area
       (APEX_APPLICATION_TEMP_FILES) into DLA_DOCUMENTS and sends
       it to the chosen model: OLLAMA goes in the relay queue,
       OCI_GENAI is read straight away. P_MODEL_CODE empty means
       use the ACTIVE_MODEL setting. Returns the new DOCUMENT_ID.
       Does not commit. */
    FUNCTION submit_document (
        p_temp_file_name  IN VARCHAR2,
        p_model_code      IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    /* Working (11/20/2026): the second reader. Sends the document
       straight from the database to OCI Generative AI (settings
       OCI_MODEL, OCI_ENDPOINT, OCI_CREDENTIAL, OCI_COMPARTMENT_OCID),
       stores the answer in DLA_EXTRACTIONS, then stages it and runs
       the agent's decision exactly as the relay path does. Needs an
       APEX session (the web credential), so it is called from the
       Upload page, not from ORDS. Returns the new EXTRACTION_ID.
       P_MODEL_CODE is accepted for symmetry; only OCI_GENAI is read
       here. P_PURPOSE (11/21/2026): LOAD is the normal path above;
       COMPARE stores the answer for the compare page only and
       skips staging, the decision, and the document status. */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER;

    /* Working (11/21/2026): the compare page (page 4). For one
       document that is already in DLA_DOCUMENTS, reads it with
       OCI Generative AI right now and puts it in the relay queue
       for the local model, both reads marked COMPARE so neither
       one is staged or loaded. The page shows the two answers
       side by side once the relay has posted its result (about
       6 seconds on the desktop, plus up to 5 seconds of polling).
       Returns a one-line message for the page. Does not commit.
       Needs an APEX session (the OCI call). */
    FUNCTION compare_document (
        p_document_id  IN NUMBER
    ) RETURN VARCHAR2;

    /* Working (11/20/2026): called by the APEX automation
       "Read waiting documents" every minute. Finds documents that
       arrived from the watched folder while WATCH_MODEL was
       OCI_GENAI (status UPLOADED, no read yet) and sends each one
       to EXTRACT_DOCUMENT, oldest first, committing after each.
       P_MAX_DOCUMENTS caps one run. Returns how many were read. */
    FUNCTION read_waiting_documents (
        p_max_documents  IN NUMBER DEFAULT 20
    ) RETURN NUMBER;

    /* Working: reads the model's JSON for one extraction with
       JSON_TABLE and writes it to the staging tables. Returns
       the new STG_HEADER_ID. Does not commit. Running it again
       for the same extraction replaces that extraction's
       staging rows. */
    FUNCTION parse_extraction (
        p_extraction_id  IN NUMBER
    ) RETURN NUMBER;

    /* Working: runs the checks on one staged invoice and writes
       what it finds to DLA_STG_FLAGS (FLAG_SOURCE = CHECK). Safe
       to run again: it replaces its own earlier flags. Does not
       commit. */
    PROCEDURE validate_staging (
        p_stg_header_id  IN NUMBER
    );

    /* Working: THE AGENT'S DECISION. Runs the checks, then:
         no flags  -> approves the invoice itself and loads it.
                      P_INVOICE_ID returns the new invoice.
         any flag  -> leaves it for a person to review.
                      P_INVOICE_ID returns empty.
       P_FLAG_COUNT returns how many flags there are. Only works
       on a staged invoice still PENDING. Does not commit. */
    PROCEDURE process_staging (
        p_stg_header_id  IN  NUMBER,
        p_invoice_id     OUT NUMBER,
        p_flag_count     OUT NUMBER
    );

    /* Working: copies an APPROVED staged invoice into the final
       tables DLA_INVOICES and DLA_INVOICE_LINES and writes the
       audit entry. Returns the new INVOICE_ID. Does not commit. */
    FUNCTION load_invoice (
        p_stg_header_id  IN NUMBER
    ) RETURN NUMBER;

END dla_pkg;
/

SHOW ERRORS PACKAGE dla_pkg

/* ------------------------------------------------------------
   Package body : DLA_PKG
   Purpose      : Code for the spec above. Every routine has an
                  exception handler that records the failure in
                  DLA_AUDIT_LOG and then re-raises it, so nothing
                  fails silently.
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE BODY dla_pkg AS

    /* --------------------------------------------------------
       Private : CURRENT_USER_NAME
       Purpose : The APEX user when called from APEX, otherwise
                 the database user.
       -------------------------------------------------------- */
    FUNCTION current_user_name RETURN VARCHAR2 IS
    BEGIN
        RETURN COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
    END current_user_name;

    /* --------------------------------------------------------
       Private : TEXT_TO_DATE
       Purpose : Turn date text from the model into a DATE.
                 The model is asked for YYYY-MM-DD but sometimes
                 copies the date the way the invoice prints it,
                 so two forms are accepted:
                   2026-12-12   (YYYY-MM-DD)
                   12/12/2026   (MM/DD/YYYY)
                 Anything else, or a date that does not exist
                 (month 13, day 32), returns NULL. That is not a
                 silent failure: PARSE_EXTRACTION raises a flag
                 whenever text was returned but no date came out.
       -------------------------------------------------------- */
    FUNCTION text_to_date (
        p_text  IN VARCHAR2
    ) RETURN DATE IS
        l_text  VARCHAR2(100);
    BEGIN
        l_text := TRIM(p_text);

        IF l_text IS NULL THEN
            RETURN NULL;
        ELSIF REGEXP_LIKE(l_text, '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$') THEN
            RETURN TO_DATE(l_text, 'YYYY-MM-DD');
        ELSIF REGEXP_LIKE(l_text, '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$') THEN
            RETURN TO_DATE(l_text, 'MM/DD/YYYY');
        ELSE
            RETURN NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            /* The text had the right shape but is not a real date. */
            RETURN NULL;
    END text_to_date;

    /* --------------------------------------------------------
       Private : NOT_BUILT_YET
       Purpose : Shared behavior for the placeholders. Logs the
                 call, then raises ORA-20099 with a clear message.
       -------------------------------------------------------- */
    PROCEDURE not_built_yet (
        p_routine  IN VARCHAR2,
        p_phase    IN VARCHAR2
    ) IS
    BEGIN
        log_audit(
            p_action  => 'NOT_BUILT',
            p_details => 'DLA_PKG.' || p_routine || ' was called but is not built until ' || p_phase || '.'
        );
        RAISE_APPLICATION_ERROR(
            -20099,
            'DLA_PKG.' || p_routine || ' is not built yet. It is planned for ' || p_phase || '.'
        );
    END not_built_yet;

    /* --------------------------------------------------------
       Public  : LOG_AUDIT
       Purpose : Insert one row into DLA_AUDIT_LOG and commit it
                 in an autonomous transaction, so the entry is
                 kept even if the caller rolls back.
       -------------------------------------------------------- */
    PROCEDURE log_audit (
        p_action       IN VARCHAR2,
        p_details      IN VARCHAR2 DEFAULT NULL,
        p_document_id  IN NUMBER   DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        l_user  dla_audit_log.performed_by%TYPE;
    BEGIN
        l_user := current_user_name;

        INSERT INTO dla_audit_log (
            document_id,
            action,
            details,
            performed_by
        ) VALUES (
            p_document_id,
            SUBSTR(p_action, 1, 50),
            SUBSTR(p_details, 1, 4000),
            l_user
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(
                -20001,
                'DLA_PKG.LOG_AUDIT failed for action ' || p_action || ': ' || SQLERRM,
                TRUE
            );
    END log_audit;

    /* --------------------------------------------------------
       Public  : GET_SETTING
       Purpose : Return SETTING_VALUE for a SETTING_NAME. Raises
                 ORA-20010 if the setting does not exist.
       -------------------------------------------------------- */
    FUNCTION get_setting (
        p_setting_name  IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_value  dla_settings.setting_value%TYPE;
    BEGIN
        SELECT s.setting_value
        INTO   l_value
        FROM   dla_settings s
        WHERE  s.setting_name = UPPER(TRIM(p_setting_name));

        RETURN l_value;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            log_audit(
                p_action  => 'SETTING_ERROR',
                p_details => 'GET_SETTING: no setting named ' || p_setting_name
            );
            RAISE_APPLICATION_ERROR(
                -20010,
                'DLA_PKG.GET_SETTING: there is no setting named ' || p_setting_name || ' in DLA_SETTINGS.'
            );
        WHEN OTHERS THEN
            log_audit(
                p_action  => 'SETTING_ERROR',
                p_details => 'GET_SETTING failed for ' || p_setting_name || ': ' || SQLERRM
            );
            RAISE;
    END get_setting;

    /* --------------------------------------------------------
       Public  : SET_SETTING
       Purpose : Update SETTING_VALUE for an existing setting and
                 log the change. Does not commit; the caller
                 (APEX or your worksheet) commits. Raises
                 ORA-20011 if the setting does not exist and
                 ORA-20012 if ACTIVE_MODEL is given a bad value.
       -------------------------------------------------------- */
    PROCEDURE set_setting (
        p_setting_name   IN VARCHAR2,
        p_setting_value  IN VARCHAR2
    ) IS
        l_name  dla_settings.setting_name%TYPE := UPPER(TRIM(p_setting_name));
        l_user  dla_settings.updated_by%TYPE;
    BEGIN
        l_user := current_user_name;

        IF l_name = 'ACTIVE_MODEL'
           AND (p_setting_value IS NULL
                OR p_setting_value NOT IN (c_model_ollama, c_model_oci))
        THEN
            RAISE_APPLICATION_ERROR(
                -20012,
                'DLA_PKG.SET_SETTING: ACTIVE_MODEL must be ' || c_model_ollama || ' or ' || c_model_oci || '.'
            );
        END IF;

        UPDATE dla_settings s
        SET    s.setting_value = p_setting_value,
               s.updated_by    = l_user,
               s.updated_on    = SYSDATE
        WHERE  s.setting_name  = l_name;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20011,
                'DLA_PKG.SET_SETTING: there is no setting named ' || p_setting_name || ' in DLA_SETTINGS.'
            );
        END IF;

        log_audit(
            p_action  => 'SETTING_CHANGED',
            p_details => l_name || ' set to ' || NVL(p_setting_value, '(empty)')
        );
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action  => 'SETTING_ERROR',
                p_details => 'SET_SETTING failed for ' || p_setting_name || ': ' || SQLERRM
            );
            RAISE;
    END set_setting;

    /* --------------------------------------------------------
       Public  : SUBMIT_DOCUMENT
       Purpose : The one call behind the upload page.
                 Raises ORA-20050 for an unknown model code and
                 ORA-20051 when the uploaded file is not found.
       -------------------------------------------------------- */
    FUNCTION submit_document (
        p_temp_file_name  IN VARCHAR2,
        p_model_code      IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER IS
        l_user           dla_documents.uploaded_by%TYPE;
        l_model          VARCHAR2(30);
        l_file_name      dla_documents.file_name%TYPE;
        l_mime_type      dla_documents.mime_type%TYPE;
        l_blob           BLOB;
        l_document_id    dla_documents.document_id%TYPE;
        l_extraction_id  NUMBER;
    BEGIN
        l_user  := current_user_name;
        l_model := UPPER(TRIM(p_model_code));

        IF l_model IS NULL THEN
            l_model := get_setting('ACTIVE_MODEL');
        END IF;

        IF l_model IS NULL OR l_model NOT IN (c_model_ollama, c_model_oci) THEN
            RAISE_APPLICATION_ERROR(
                -20050,
                'DLA_PKG.SUBMIT_DOCUMENT: the model must be ' || c_model_ollama || ' or ' || c_model_oci || '.'
            );
        END IF;

        BEGIN
            SELECT f.filename,
                   f.mime_type,
                   f.blob_content
            INTO   l_file_name,
                   l_mime_type,
                   l_blob
            FROM   apex_application_temp_files f
            WHERE  f.name = p_temp_file_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20051,
                    'DLA_PKG.SUBMIT_DOCUMENT: no uploaded file was found. Choose a file and try again.'
                );
        END;

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
            l_user
        )
        RETURNING document_id INTO l_document_id;

        log_audit(
            p_action      => 'UPLOADED',
            p_details     => l_file_name || ' uploaded by ' || l_user || ' for model ' || l_model || '.',
            p_document_id => l_document_id
        );

        IF l_model = c_model_ollama THEN
            l_extraction_id := dla_relay_pkg.queue_extraction(l_document_id);
        ELSE
            l_extraction_id := extract_document(l_document_id, l_model);
        END IF;

        RETURN l_document_id;
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action      => 'UPLOAD_ERROR',
                p_details     => 'SUBMIT_DOCUMENT failed: ' || SQLERRM,
                p_document_id => l_document_id
            );
            RAISE;
    END submit_document;

    /* --------------------------------------------------------
       Private : STRIP_FENCES
       Purpose : Some models wrap JSON in a ```json ... ``` fence
                 even when told not to. Returns the text inside.
       -------------------------------------------------------- */
    FUNCTION strip_fences (
        p_text  IN CLOB
    ) RETURN CLOB IS
        l_text  CLOB;
    BEGIN
        IF p_text IS NULL THEN
            RETURN NULL;
        END IF;
        /* Drop a leading ```json (or ```) line and a trailing ``` line,
           then any white space around what is left. REGEXP_REPLACE
           works on a CLOB; DBMS_LOB.INSTR cannot search backwards,
           which is what went wrong on 11/20/2026. */
        l_text := REGEXP_REPLACE(p_text, '^[[:space:]]*```[A-Za-z]*[[:space:]]*', '');
        l_text := REGEXP_REPLACE(l_text, '[[:space:]]*```[[:space:]]*$', '');
        RETURN TRIM(l_text);
    END strip_fences;

    /* --------------------------------------------------------
       Public  : EXTRACT_DOCUMENT   (the OCI reader, 11/20/2026)
       How     : One POST to the OCI Generative AI chat endpoint
                 with APEX_WEB_SERVICE.MAKE_REST_REQUEST and the
                 workspace web credential (OCI native signing).
                 The request is the GENERIC chat format with two
                 content parts: the instruction (TEXT) and the
                 file itself (DOCUMENT for a PDF, IMAGE for a
                 picture), both inline as base64. Built the same
                 way as the proven call in Gary's label platform
                 (PKG_IMAGINARY_SPEC_READ), with one retry when
                 Oracle's side answers 429 or 5xx.
       Then    : the answer is stored on a new DLA_EXTRACTIONS
                 row (SUCCESS or ERROR), the document status is
                 set, and on success PARSE_EXTRACTION and
                 PROCESS_STAGING run under savepoints, exactly
                 as DLA_RELAY_PKG.RECEIVE_RESULT does, so the two
                 readers end in the same place: loaded, or
                 waiting for a person.
       Raises  : ORA-20099 if the OCI settings are missing or
                 the document is not a PDF, PNG or JPG. Any
                 failure after the extraction row exists is
                 recorded on that row, not raised, so the page
                 shows a red row instead of an error.
       -------------------------------------------------------- */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER IS
        l_purpose        dla_extractions.purpose%TYPE;
        l_model          dla_settings.setting_value%TYPE;
        l_endpoint       dla_settings.setting_value%TYPE;
        l_credential     dla_settings.setting_value%TYPE;
        l_compartment    dla_settings.setting_value%TYPE;
        l_prompt         dla_settings.setting_value%TYPE;
        l_file_name      dla_documents.file_name%TYPE;
        l_mime           dla_documents.mime_type%TYPE;
        l_blob           dla_documents.file_blob%TYPE;
        l_extraction_id  dla_extractions.extraction_id%TYPE;
        l_started        TIMESTAMP;
        l_elapsed_ms     NUMBER;
        l_body           JSON_OBJECT_T;
        l_srv            JSON_OBJECT_T;
        l_req            JSON_OBJECT_T;
        l_msgs           JSON_ARRAY_T;
        l_msg            JSON_OBJECT_T;
        l_cont           JSON_ARRAY_T;
        l_txt            JSON_OBJECT_T;
        l_file           JSON_OBJECT_T;
        l_url_obj        JSON_OBJECT_T;
        l_data_url       CLOB;
        l_resp           CLOB;
        l_answer         CLOB;
        l_status         NUMBER;
        l_error          VARCHAR2(4000);
        l_stg_header     NUMBER;
        l_invoice_id     NUMBER;
        l_flag_count     NUMBER;
        l_is_json        NUMBER := 0;
    BEGIN
        l_model       := get_setting('OCI_MODEL');
        l_endpoint    := get_setting('OCI_ENDPOINT');
        l_credential  := get_setting('OCI_CREDENTIAL');
        l_compartment := get_setting('OCI_COMPARTMENT_OCID');
        l_prompt      := get_setting('EXTRACTION_PROMPT');

        IF l_model IS NULL OR l_endpoint IS NULL OR l_credential IS NULL
           OR l_compartment IS NULL OR l_prompt IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20099,
                'DLA_PKG.EXTRACT_DOCUMENT: the OCI settings are missing. Run db\data\DLA_13_OCI_MODEL.sql.'
            );
        END IF;

        l_purpose := UPPER(TRIM(NVL(p_purpose, 'LOAD')));
        IF l_purpose NOT IN ('LOAD', 'COMPARE') THEN
            RAISE_APPLICATION_ERROR(
                -20099,
                'DLA_PKG.EXTRACT_DOCUMENT: P_PURPOSE must be LOAD or COMPARE, not ' || p_purpose || '.'
            );
        END IF;

        BEGIN
            SELECT d.file_name,
                   LOWER(d.mime_type),
                   d.file_blob
            INTO   l_file_name,
                   l_mime,
                   l_blob
            FROM   dla_documents d
            WHERE  d.document_id = p_document_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20099,
                    'DLA_PKG.EXTRACT_DOCUMENT: there is no document ' || p_document_id || '.'
                );
        END;

        IF l_mime NOT IN ('application/pdf', 'image/png', 'image/jpeg') THEN
            RAISE_APPLICATION_ERROR(
                -20099,
                'DLA_PKG.EXTRACT_DOCUMENT: only PDF, PNG and JPG are read. This file is ' || l_mime || '.'
            );
        END IF;

        /* The extraction row exists before the call, so a slow or
           failed call still leaves a trace the page can show. */
        INSERT INTO dla_extractions (
            document_id,
            model_code,
            model_name,
            status,
            purpose
        ) VALUES (
            p_document_id,
            c_model_oci,
            l_model,
            'RUNNING',
            l_purpose
        )
        RETURNING extraction_id INTO l_extraction_id;

        log_audit(
            p_action      => 'EXTRACTION_STARTED',
            p_details     => 'Extraction ' || l_extraction_id || ' sent to ' || l_model || ' on OCI.',
            p_document_id => p_document_id
        );

        l_started := SYSTIMESTAMP;

        /* The request. One user message with two parts. */
        l_data_url := 'data:' || l_mime || ';base64,'
                      || REPLACE(REPLACE(APEX_WEB_SERVICE.BLOB2CLOBBASE64(
                             p_blob => l_blob, p_newlines => 'N', p_padding => 'N'),
                         CHR(10), ''), CHR(13), '');

        l_txt := JSON_OBJECT_T();
        l_txt.put('type', 'TEXT');
        l_txt.put('text', l_prompt);

        l_url_obj := JSON_OBJECT_T();
        l_url_obj.put('url', l_data_url);

        l_file := JSON_OBJECT_T();
        IF l_mime = 'application/pdf' THEN
            l_file.put('type', 'DOCUMENT');
            l_file.put('documentUrl', l_url_obj);
        ELSE
            l_file.put('type', 'IMAGE');
            l_file.put('imageUrl', l_url_obj);
        END IF;

        l_cont := JSON_ARRAY_T();
        l_cont.append(l_txt);
        l_cont.append(l_file);

        l_msg := JSON_OBJECT_T();
        l_msg.put('role', 'USER');
        l_msg.put('content', l_cont);

        l_msgs := JSON_ARRAY_T();
        l_msgs.append(l_msg);

        l_req := JSON_OBJECT_T();
        l_req.put('apiFormat', 'GENERIC');
        l_req.put('messages', l_msgs);
        l_req.put('maxTokens', 4000);
        l_req.put('temperature', 0);

        l_srv := JSON_OBJECT_T();
        l_srv.put('servingType', 'ON_DEMAND');
        l_srv.put('modelId', l_model);

        l_body := JSON_OBJECT_T();
        l_body.put('compartmentId', l_compartment);
        l_body.put('servingMode', l_srv);
        l_body.put('chatRequest', l_req);

        /* The call, tried twice when Oracle's side is busy. */
        BEGIN
            FOR l_try IN 1 .. 2 LOOP
                APEX_WEB_SERVICE.SET_REQUEST_HEADERS(p_name_01 => 'Content-Type', p_value_01 => 'application/json');
                l_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                              p_http_method          => 'POST',
                              p_url                  => l_endpoint,
                              p_credential_static_id => l_credential,
                              p_body                 => l_body.to_clob,
                              p_transfer_timeout     => 170);
                l_status := APEX_WEB_SERVICE.G_STATUS_CODE;
                EXIT WHEN l_status = 200;
                EXIT WHEN l_try = 2 OR l_status NOT IN (429, 500, 502, 503, 504);
                DBMS_SESSION.SLEEP(5);
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN
                l_status := -1;
                l_error  := SQLERRM;
        END;

        l_elapsed_ms := ROUND(EXTRACT(SECOND FROM (SYSTIMESTAMP - l_started)) * 1000
                        + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_started)) * 60000
                        + EXTRACT(HOUR   FROM (SYSTIMESTAMP - l_started)) * 3600000);

        IF l_status = 200 THEN
            /* The answer text: every text part of the first choice. */
            FOR t IN (SELECT j.txt
                      FROM   JSON_TABLE(l_resp, '$.chatResponse.choices[0].message.content[*]'
                                 COLUMNS (txt CLOB PATH '$.text')) j) LOOP
                l_answer := l_answer || t.txt;
            END LOOP;
            l_answer := strip_fences(l_answer);

            /* IS JSON is a SQL condition, not PL/SQL, hence the query. */
            IF l_answer IS NULL THEN
                l_is_json := 0;
            ELSE
                SELECT CASE WHEN l_answer IS JSON THEN 1 ELSE 0 END
                INTO   l_is_json
                FROM   dual;
            END IF;

            IF l_is_json = 0 THEN
                l_error := 'The model answered, but the answer is not valid JSON.';
            END IF;
        ELSIF l_status > 0 THEN
            l_error := 'OCI Generative AI answered HTTP ' || l_status || ': '
                       || SUBSTR(DBMS_LOB.SUBSTR(l_resp, 600, 1), 1, 600);
        ELSE
            l_error := 'The call to OCI Generative AI failed: ' || l_error;
        END IF;

        IF l_error IS NULL THEN
            UPDATE dla_extractions e
            SET    e.status         = 'SUCCESS',
                   e.elapsed_ms     = l_elapsed_ms,
                   e.raw_response   = l_resp,
                   e.extracted_json = l_answer,
                   e.error_message  = NULL
            WHERE  e.extraction_id  = l_extraction_id;

            log_audit(
                p_action      => 'EXTRACTION_SUCCESS',
                p_details     => 'Extraction ' || l_extraction_id || ' answered by ' || l_model
                                 || ' in ' || l_elapsed_ms || ' ms'
                                 || CASE WHEN l_purpose = 'COMPARE' THEN ' (compare only, not staged)' END || '.',
                p_document_id => p_document_id
            );

            /* A COMPARE read stops here: the answer is kept for
               page 4, the document and the review queue are left
               exactly as they were. */
            IF l_purpose = 'LOAD' THEN
                UPDATE dla_documents d
                SET    d.status      = 'EXTRACTED'
                WHERE  d.document_id = p_document_id;

                /* Stage it, then let the agent decide. Same two steps,
                   same savepoints, as the relay path. */
                SAVEPOINT before_staging;
                BEGIN
                    l_stg_header := parse_extraction(l_extraction_id);
                EXCEPTION
                    WHEN OTHERS THEN
                        ROLLBACK TO before_staging;
                        l_stg_header := NULL;
                END;

                IF l_stg_header IS NOT NULL THEN
                    SAVEPOINT before_decision;
                    BEGIN
                        process_staging(
                            p_stg_header_id => l_stg_header,
                            p_invoice_id    => l_invoice_id,
                            p_flag_count    => l_flag_count
                        );
                    EXCEPTION
                        WHEN OTHERS THEN
                            ROLLBACK TO before_decision;
                    END;
                END IF;
            END IF;
        ELSE
            UPDATE dla_extractions e
            SET    e.status         = 'ERROR',
                   e.elapsed_ms     = l_elapsed_ms,
                   e.raw_response   = l_resp,
                   e.error_message  = SUBSTR(l_error, 1, 4000)
            WHERE  e.extraction_id  = l_extraction_id;

            IF l_purpose = 'LOAD' THEN
                UPDATE dla_documents d
                SET    d.status      = 'ERROR'
                WHERE  d.document_id = p_document_id;
            END IF;

            log_audit(
                p_action      => 'EXTRACTION_ERROR',
                p_details     => 'Extraction ' || l_extraction_id || ': ' || SUBSTR(l_error, 1, 3000),
                p_document_id => p_document_id
            );
        END IF;

        RETURN l_extraction_id;
    END extract_document;

    /* --------------------------------------------------------
       Public  : COMPARE_DOCUMENT   (page 4, "Read with both")
       Purpose : One click on the compare page. The OCI read
                 happens here and now (seconds); the local read
                 is queued for the relay on Gary's desktop and
                 lands a few seconds later. Both rows carry
                 PURPOSE = COMPARE, so RECEIVE_RESULT and
                 EXTRACT_DOCUMENT keep them out of staging.
       Refuses : ORA-20098 if a COMPARE read for this document
                 is still PENDING or RUNNING (press Refresh and
                 wait instead of queueing it twice).
       -------------------------------------------------------- */
    FUNCTION compare_document (
        p_document_id  IN NUMBER
    ) RETURN VARCHAR2 IS
        l_count          NUMBER;
        l_oci_id         NUMBER;
        l_local_id       NUMBER;
        l_oci_status     dla_extractions.status%TYPE;
        l_oci_ms         dla_extractions.elapsed_ms%TYPE;
    BEGIN
        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_extractions e
        WHERE  e.document_id = p_document_id
        AND    e.purpose     = 'COMPARE'
        AND    e.status      IN ('PENDING', 'RUNNING');

        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20098,
                'A compare read of this document is still running. Click Refresh and wait for it.'
            );
        END IF;

        l_local_id := dla_relay_pkg.queue_extraction(
                          p_document_id => p_document_id,
                          p_purpose     => 'COMPARE');

        l_oci_id   := extract_document(
                          p_document_id => p_document_id,
                          p_model_code  => c_model_oci,
                          p_purpose     => 'COMPARE');

        SELECT e.status,
               e.elapsed_ms
        INTO   l_oci_status,
               l_oci_ms
        FROM   dla_extractions e
        WHERE  e.extraction_id = l_oci_id;

        log_audit(
            p_action      => 'COMPARE_REQUESTED',
            p_details     => 'Compare: OCI read ' || l_oci_id || ' (' || l_oci_status || ', '
                             || l_oci_ms || ' ms), local read ' || l_local_id || ' queued.',
            p_document_id => p_document_id
        );

        IF l_oci_status = 'SUCCESS' THEN
            RETURN 'OCI answered in ' || ROUND(l_oci_ms / 1000, 1)
                   || ' s. The local model is reading now; click Refresh in a few seconds.';
        ELSE
            RETURN 'OCI read failed (see the red row). The local model is reading now; click Refresh in a few seconds.';
        END IF;
    END compare_document;

    /* --------------------------------------------------------
       Public  : READ_WAITING_DOCUMENTS   (the automation's work)
       Purpose : The watched folder cannot call OCI itself (no
                 APEX session in ORDS), so RECEIVE_DOCUMENT leaves
                 an OCI-bound file as UPLOADED with no read, and
                 this picks it up from inside an APEX automation,
                 which does have a session. One commit per
                 document, so a failure on one does not undo the
                 others; a failed read is marked ERROR by
                 EXTRACT_DOCUMENT and is not picked up again.
       -------------------------------------------------------- */
    FUNCTION read_waiting_documents (
        p_max_documents  IN NUMBER DEFAULT 20
    ) RETURN NUMBER IS
        l_done           NUMBER := 0;
        l_extraction_id  NUMBER;
    BEGIN
        FOR r IN (SELECT d.document_id,
                         d.file_name
                  FROM   dla_documents d
                  WHERE  d.status = 'UPLOADED'
                  AND    NOT EXISTS (SELECT 1
                                     FROM   dla_extractions e
                                     WHERE  e.document_id = d.document_id)
                  ORDER  BY d.document_id) LOOP
            EXIT WHEN l_done >= NVL(p_max_documents, 20);
            BEGIN
                l_extraction_id := extract_document(r.document_id, c_model_oci);
                COMMIT;
                l_done := l_done + 1;
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK;
                    log_audit(
                        p_action      => 'EXTRACTION_ERROR',
                        p_details     => 'READ_WAITING_DOCUMENTS could not start a read for '
                                         || r.file_name || ': ' || SQLERRM,
                        p_document_id => r.document_id
                    );
                    /* Mark it so it is not tried every minute for ever. */
                    UPDATE dla_documents d
                    SET    d.status = 'ERROR'
                    WHERE  d.document_id = r.document_id;
                    COMMIT;
            END;
        END LOOP;
        RETURN l_done;
    END read_waiting_documents;

    /* --------------------------------------------------------
       Private : ADD_FLAG
       Purpose : Write one row to DLA_STG_FLAGS.
       -------------------------------------------------------- */
    PROCEDURE add_flag (
        p_stg_header_id  IN NUMBER,
        p_field_name     IN VARCHAR2,
        p_severity       IN VARCHAR2,
        p_message        IN VARCHAR2,
        p_flag_source    IN VARCHAR2 DEFAULT 'PARSE',
        p_stg_line_id    IN NUMBER   DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO dla_stg_flags (
            stg_header_id,
            stg_line_id,
            field_name,
            severity,
            message,
            flag_source
        ) VALUES (
            p_stg_header_id,
            p_stg_line_id,
            p_field_name,
            p_severity,
            SUBSTR(p_message, 1, 1000),
            p_flag_source
        );
    END add_flag;

    /* --------------------------------------------------------
       Private : MONEY
       Purpose : A number as text for messages, e.g. 4,305.30.
       -------------------------------------------------------- */
    FUNCTION money (
        p_number  IN NUMBER
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_number, 'FM999G999G999G990D00');
    END money;

    /* --------------------------------------------------------
       Public  : PARSE_EXTRACTION
       Purpose : Turn the model's JSON into staging rows.
                 1. Header fields come out with JSON_TABLE. Each
                    date and amount is read twice: as text, and
                    converted. Dates are accepted as YYYY-MM-DD
                    or MM/DD/YYYY (see TEXT_TO_DATE). If the text
                    is there but will not convert, the field is
                    left empty and a WARNING flag says what the
                    model returned.
                 2. The vendor name is matched to DLA_VENDORS
                    (exact name, ignoring case). No match leaves
                    VENDOR_ID empty; the validation step reports
                    it.
                 3. Lines come out with JSON_TABLE on
                    line_items[*].
                 Raises ORA-20040 if the extraction does not
                 exist or has no successful JSON to parse.
       -------------------------------------------------------- */
    FUNCTION parse_extraction (
        p_extraction_id  IN NUMBER
    ) RETURN NUMBER IS
        l_user            dla_stg_headers.created_by%TYPE;
        l_document_id     dla_extractions.document_id%TYPE;
        l_status          dla_extractions.status%TYPE;
        l_has_json        NUMBER;
        l_vendor_name     dla_stg_headers.vendor_name%TYPE;
        l_vendor_id       dla_stg_headers.vendor_id%TYPE;
        l_invoice_number  dla_stg_headers.invoice_number%TYPE;
        l_inv_date_txt    VARCHAR2(100);
        l_due_date_txt    VARCHAR2(100);
        l_subtotal_txt    VARCHAR2(100);
        l_tax_txt         VARCHAR2(100);
        l_total_txt       VARCHAR2(100);
        l_invoice_date    DATE;
        l_due_date        DATE;
        l_subtotal        NUMBER;
        l_tax             NUMBER;
        l_total           NUMBER;
        l_stg_header_id   dla_stg_headers.stg_header_id%TYPE;
        l_line_count      NUMBER;
    BEGIN
        l_user := current_user_name;

        BEGIN
            SELECT e.document_id,
                   e.status,
                   CASE WHEN e.extracted_json IS NULL THEN 0 ELSE 1 END
            INTO   l_document_id,
                   l_status,
                   l_has_json
            FROM   dla_extractions e
            WHERE  e.extraction_id = p_extraction_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20040,
                    'DLA_PKG.PARSE_EXTRACTION: there is no extraction ' || p_extraction_id || '.'
                );
        END;

        IF l_status <> 'SUCCESS' OR l_has_json = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20040,
                'DLA_PKG.PARSE_EXTRACTION: extraction ' || p_extraction_id
                || ' has status ' || l_status || ' and no JSON to parse.'
            );
        END IF;

        /* Replace any earlier staging rows for this extraction.
           Lines and flags go with the header (ON DELETE CASCADE). */
        DELETE FROM dla_stg_headers h
        WHERE  h.extraction_id = p_extraction_id;

        /* 1. Header */
        SELECT jt.vendor_name,
               jt.invoice_number,
               jt.invoice_date_txt,
               jt.due_date_txt,
               jt.subtotal_txt,
               jt.tax_txt,
               jt.total_txt,
               TO_NUMBER(jt.subtotal_txt   DEFAULT NULL ON CONVERSION ERROR),
               TO_NUMBER(jt.tax_txt        DEFAULT NULL ON CONVERSION ERROR),
               TO_NUMBER(jt.total_txt      DEFAULT NULL ON CONVERSION ERROR)
        INTO   l_vendor_name,
               l_invoice_number,
               l_inv_date_txt,
               l_due_date_txt,
               l_subtotal_txt,
               l_tax_txt,
               l_total_txt,
               l_subtotal,
               l_tax,
               l_total
        FROM   dla_extractions e,
               JSON_TABLE(
                   e.extracted_json, '$'
                   COLUMNS (
                       vendor_name       VARCHAR2(200) PATH '$.vendor_name',
                       invoice_number    VARCHAR2(100) PATH '$.invoice_number',
                       invoice_date_txt  VARCHAR2(100) PATH '$.invoice_date',
                       due_date_txt      VARCHAR2(100) PATH '$.due_date',
                       subtotal_txt      VARCHAR2(100) PATH '$.subtotal',
                       tax_txt           VARCHAR2(100) PATH '$.tax',
                       total_txt         VARCHAR2(100) PATH '$.total'
                   )
               ) jt
        WHERE  e.extraction_id = p_extraction_id;

        /* Dates are converted here, not in the query above: a
           function private to this package body cannot be called
           from SQL. */
        l_invoice_date := text_to_date(l_inv_date_txt);
        l_due_date     := text_to_date(l_due_date_txt);

        /* 2. Vendor match */
        BEGIN
            SELECT v.vendor_id
            INTO   l_vendor_id
            FROM   dla_vendors v
            WHERE  UPPER(TRIM(v.vendor_name)) = UPPER(TRIM(l_vendor_name))
            AND    v.active_yn = 'Y';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_vendor_id := NULL;
        END;

        INSERT INTO dla_stg_headers (
            document_id,
            extraction_id,
            vendor_name,
            vendor_id,
            invoice_number,
            invoice_date,
            due_date,
            subtotal,
            tax,
            total,
            created_by
        ) VALUES (
            l_document_id,
            p_extraction_id,
            l_vendor_name,
            l_vendor_id,
            l_invoice_number,
            l_invoice_date,
            l_due_date,
            l_subtotal,
            l_tax,
            l_total,
            l_user
        )
        RETURNING stg_header_id INTO l_stg_header_id;

        /* Flags for values the model returned that would not convert */
        IF l_inv_date_txt IS NOT NULL AND l_invoice_date IS NULL THEN
            add_flag(l_stg_header_id, 'INVOICE_DATE', 'WARNING',
                     'The model returned "' || l_inv_date_txt || '", which could not be read as a date (YYYY-MM-DD or MM/DD/YYYY).');
        END IF;
        IF l_due_date_txt IS NOT NULL AND l_due_date IS NULL THEN
            add_flag(l_stg_header_id, 'DUE_DATE', 'WARNING',
                     'The model returned "' || l_due_date_txt || '", which could not be read as a date (YYYY-MM-DD or MM/DD/YYYY).');
        END IF;
        IF l_subtotal_txt IS NOT NULL AND l_subtotal IS NULL THEN
            add_flag(l_stg_header_id, 'SUBTOTAL', 'WARNING',
                     'The model returned "' || l_subtotal_txt || '", which is not a number.');
        END IF;
        IF l_tax_txt IS NOT NULL AND l_tax IS NULL THEN
            add_flag(l_stg_header_id, 'TAX', 'WARNING',
                     'The model returned "' || l_tax_txt || '", which is not a number.');
        END IF;
        IF l_total_txt IS NOT NULL AND l_total IS NULL THEN
            add_flag(l_stg_header_id, 'TOTAL', 'WARNING',
                     'The model returned "' || l_total_txt || '", which is not a number.');
        END IF;

        /* 3. Lines */
        INSERT INTO dla_stg_lines (
            stg_header_id,
            line_number,
            description,
            quantity,
            unit_price,
            amount
        )
        SELECT l_stg_header_id,
               NVL(jt.line_number, jt.seq),
               jt.description,
               jt.quantity,
               jt.unit_price,
               jt.amount
        FROM   dla_extractions e,
               JSON_TABLE(
                   e.extracted_json, '$.line_items[*]'
                   COLUMNS (
                       seq          FOR ORDINALITY,
                       line_number  NUMBER         PATH '$.line_number',
                       description  VARCHAR2(1000) PATH '$.description',
                       quantity     NUMBER         PATH '$.quantity',
                       unit_price   NUMBER         PATH '$.unit_price',
                       amount       NUMBER         PATH '$.amount'
                   )
               ) jt
        WHERE  e.extraction_id = p_extraction_id;

        l_line_count := SQL%ROWCOUNT;

        log_audit(
            p_action      => 'STAGED',
            p_details     => 'Extraction ' || p_extraction_id || ' staged as header '
                             || l_stg_header_id || ' with ' || l_line_count || ' line(s).',
            p_document_id => l_document_id
        );

        RETURN l_stg_header_id;
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action      => 'STAGING_ERROR',
                p_details     => 'PARSE_EXTRACTION failed for extraction ' || p_extraction_id || ': ' || SQLERRM,
                p_document_id => l_document_id
            );
            RAISE;
    END parse_extraction;

    /* --------------------------------------------------------
       Public  : VALIDATE_STAGING
       Checks  : 1. Required fields are there: vendor, invoice
                    number, invoice date, total.
                 2. The vendor is in DLA_VENDORS.
                 3. The invoice is not a duplicate: not already
                    loaded, and not already waiting from another
                    document.
                 4. There is at least one line.
                 5. Each line: quantity x unit price = amount.
                 6. The lines add up to the subtotal.
                 7. Subtotal + tax = total.
                 8. The due date is not before the invoice date
                    (WARNING).
                 9. The invoice date is not in the future. A model
                    that finds no invoice date sometimes fills in
                    the due date instead; a date after today is
                    how that shows up.
                 Differences up to the TOTAL_TOLERANCE setting are
                 allowed, for rounding.
                 Raises ORA-20060 if the staged invoice does not
                 exist.
       -------------------------------------------------------- */
    PROCEDURE validate_staging (
        p_stg_header_id  IN NUMBER
    ) IS
        l_h           dla_stg_headers%ROWTYPE;
        l_tolerance   NUMBER;
        l_count       NUMBER;
        l_line_count  NUMBER;
        l_line_sum    NUMBER;
        l_expected    NUMBER;
    BEGIN
        BEGIN
            SELECT h.*
            INTO   l_h
            FROM   dla_stg_headers h
            WHERE  h.stg_header_id = p_stg_header_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20060,
                    'DLA_PKG.VALIDATE_STAGING: there is no staged invoice ' || p_stg_header_id || '.'
                );
        END;

        /* The tolerance setting is text such as 0.01. If it cannot
           be read as a number, one cent is used. */
        BEGIN
            l_tolerance := TO_NUMBER(get_setting('TOTAL_TOLERANCE'));
        EXCEPTION
            WHEN VALUE_ERROR THEN
                l_tolerance := 0.01;
        END;
        l_tolerance := NVL(l_tolerance, 0.01);

        /* Start clean: remove the flags from an earlier run of these checks. */
        DELETE FROM dla_stg_flags f
        WHERE  f.stg_header_id = p_stg_header_id
        AND    f.flag_source   = 'CHECK';

        /* 1. Required fields */
        IF l_h.vendor_name IS NULL THEN
            add_flag(p_stg_header_id, 'VENDOR_NAME', 'ERROR', 'The vendor name is missing.', 'CHECK');
        END IF;
        IF l_h.invoice_number IS NULL THEN
            add_flag(p_stg_header_id, 'INVOICE_NUMBER', 'ERROR', 'The invoice number is missing.', 'CHECK');
        END IF;
        IF l_h.invoice_date IS NULL THEN
            add_flag(p_stg_header_id, 'INVOICE_DATE', 'ERROR', 'The invoice date is missing.', 'CHECK');
        END IF;
        IF l_h.total IS NULL THEN
            add_flag(p_stg_header_id, 'TOTAL', 'ERROR', 'The invoice total is missing.', 'CHECK');
        END IF;

        /* 2. Known vendor */
        IF l_h.vendor_name IS NOT NULL AND l_h.vendor_id IS NULL THEN
            add_flag(p_stg_header_id, 'VENDOR_NAME', 'ERROR',
                     'The vendor "' || l_h.vendor_name || '" is not in the vendor list.', 'CHECK');
        END IF;

        /* 3. Duplicate */
        IF l_h.vendor_id IS NOT NULL AND l_h.invoice_number IS NOT NULL THEN
            SELECT COUNT(*)
            INTO   l_count
            FROM   dla_invoices i
            WHERE  i.vendor_id      = l_h.vendor_id
            AND    i.invoice_number = l_h.invoice_number;

            IF l_count > 0 THEN
                add_flag(p_stg_header_id, 'INVOICE_NUMBER', 'ERROR',
                         'Invoice ' || l_h.invoice_number || ' from this vendor has already been loaded. This looks like a duplicate.',
                         'CHECK');
            ELSE
                SELECT COUNT(*)
                INTO   l_count
                FROM   dla_stg_headers h
                WHERE  h.vendor_id      = l_h.vendor_id
                AND    h.invoice_number = l_h.invoice_number
                AND    h.document_id   <> l_h.document_id
                AND    h.stg_header_id  < p_stg_header_id
                AND    h.review_status <> 'REJECTED';

                IF l_count > 0 THEN
                    add_flag(p_stg_header_id, 'INVOICE_NUMBER', 'ERROR',
                             'Invoice ' || l_h.invoice_number || ' from this vendor is already waiting from another document. This looks like a duplicate.',
                             'CHECK');
                END IF;
            END IF;
        END IF;

        /* 4. At least one line, and the sum of the lines */
        SELECT COUNT(*),
               NVL(SUM(l.amount), 0)
        INTO   l_line_count,
               l_line_sum
        FROM   dla_stg_lines l
        WHERE  l.stg_header_id = p_stg_header_id;

        IF l_line_count = 0 THEN
            add_flag(p_stg_header_id, 'LINE_ITEMS', 'ERROR', 'No invoice lines were read.', 'CHECK');
        END IF;

        /* 5. Each line: quantity x unit price = amount */
        FOR r IN (SELECT l.stg_line_id,
                         l.line_number,
                         l.quantity,
                         l.unit_price,
                         l.amount
                  FROM   dla_stg_lines l
                  WHERE  l.stg_header_id = p_stg_header_id
                  ORDER  BY l.line_number)
        LOOP
            IF r.amount IS NULL THEN
                add_flag(p_stg_header_id, 'AMOUNT', 'ERROR',
                         'Line ' || r.line_number || ': the amount is missing.', 'CHECK', r.stg_line_id);
            ELSIF r.quantity IS NOT NULL
              AND r.unit_price IS NOT NULL
              AND ABS(ROUND(r.quantity * r.unit_price, 2) - r.amount) > l_tolerance
            THEN
                add_flag(p_stg_header_id, 'AMOUNT', 'ERROR',
                         'Line ' || r.line_number || ': ' || r.quantity || ' x ' || money(r.unit_price)
                         || ' is ' || money(ROUND(r.quantity * r.unit_price, 2))
                         || ', but the amount says ' || money(r.amount) || '.',
                         'CHECK', r.stg_line_id);
            END IF;
        END LOOP;

        /* 6. The lines add up to the subtotal */
        IF l_line_count > 0
           AND l_h.subtotal IS NOT NULL
           AND ABS(l_line_sum - l_h.subtotal) > l_tolerance
        THEN
            add_flag(p_stg_header_id, 'SUBTOTAL', 'ERROR',
                     'The lines add up to ' || money(l_line_sum) || ', but the subtotal says ' || money(l_h.subtotal) || '.',
                     'CHECK');
        END IF;

        /* 7. Subtotal + tax = total */
        IF l_h.total IS NOT NULL AND l_line_count > 0 THEN
            l_expected := NVL(l_h.subtotal, l_line_sum) + NVL(l_h.tax, 0);
            IF ABS(l_expected - l_h.total) > l_tolerance THEN
                add_flag(p_stg_header_id, 'TOTAL', 'ERROR',
                         'Subtotal ' || money(NVL(l_h.subtotal, l_line_sum)) || ' plus tax ' || money(NVL(l_h.tax, 0))
                         || ' is ' || money(l_expected) || ', but the total says ' || money(l_h.total) || '.',
                         'CHECK');
            END IF;
        END IF;

        /* 8. Due date not before the invoice date */
        IF l_h.invoice_date IS NOT NULL
           AND l_h.due_date IS NOT NULL
           AND l_h.due_date < l_h.invoice_date
        THEN
            add_flag(p_stg_header_id, 'DUE_DATE', 'WARNING',
                     'The due date is before the invoice date.', 'CHECK');
        END IF;

        /* 9. Invoice date not in the future */
        IF l_h.invoice_date IS NOT NULL
           AND TRUNC(l_h.invoice_date) > TRUNC(SYSDATE)
        THEN
            add_flag(p_stg_header_id, 'INVOICE_DATE', 'ERROR',
                     'The invoice date ' || TO_CHAR(l_h.invoice_date, 'MM/DD/YYYY')
                     || ' is in the future. Check it against the invoice: it may be the due date, or the invoice may have no date.',
                     'CHECK');
        END IF;

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_stg_flags f
        WHERE  f.stg_header_id = p_stg_header_id;

        log_audit(
            p_action      => 'CHECKED',
            p_details     => 'Staged invoice ' || p_stg_header_id || ' checked: ' || l_count || ' flag(s).',
            p_document_id => l_h.document_id
        );
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action      => 'CHECK_ERROR',
                p_details     => 'VALIDATE_STAGING failed for staged invoice ' || p_stg_header_id || ': ' || SQLERRM,
                p_document_id => l_h.document_id
            );
            RAISE;
    END validate_staging;

    /* --------------------------------------------------------
       Public  : PROCESS_STAGING
       Purpose : The agent's decision. See the spec.
                 Raises ORA-20061 if the staged invoice does not
                 exist or is no longer PENDING.
       -------------------------------------------------------- */
    PROCEDURE process_staging (
        p_stg_header_id  IN  NUMBER,
        p_invoice_id     OUT NUMBER,
        p_flag_count     OUT NUMBER
    ) IS
        l_document_id    dla_stg_headers.document_id%TYPE;
        l_review_status  dla_stg_headers.review_status%TYPE;
    BEGIN
        p_invoice_id := NULL;
        p_flag_count := NULL;

        BEGIN
            SELECT h.document_id,
                   h.review_status
            INTO   l_document_id,
                   l_review_status
            FROM   dla_stg_headers h
            WHERE  h.stg_header_id = p_stg_header_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20061,
                    'DLA_PKG.PROCESS_STAGING: there is no staged invoice ' || p_stg_header_id || '.'
                );
        END;

        IF l_review_status <> 'PENDING' THEN
            RAISE_APPLICATION_ERROR(
                -20061,
                'DLA_PKG.PROCESS_STAGING: staged invoice ' || p_stg_header_id
                || ' is already ' || l_review_status || '.'
            );
        END IF;

        validate_staging(p_stg_header_id);

        SELECT COUNT(*)
        INTO   p_flag_count
        FROM   dla_stg_flags f
        WHERE  f.stg_header_id = p_stg_header_id;

        IF p_flag_count = 0 THEN
            UPDATE dla_stg_headers h
            SET    h.review_status  = 'APPROVED',
                   h.reviewed_by    = 'AGENT',
                   h.reviewed_on    = SYSDATE,
                   h.review_comment = 'All checks passed. Approved automatically.'
            WHERE  h.stg_header_id  = p_stg_header_id;

            log_audit(
                p_action      => 'AUTO_APPROVED',
                p_details     => 'Staged invoice ' || p_stg_header_id || ' passed every check and was approved by the agent.',
                p_document_id => l_document_id
            );

            p_invoice_id := load_invoice(p_stg_header_id);
        ELSE
            UPDATE dla_documents d
            SET    d.status      = 'IN_REVIEW'
            WHERE  d.document_id = l_document_id;

            log_audit(
                p_action      => 'NEEDS_REVIEW',
                p_details     => 'Staged invoice ' || p_stg_header_id || ' has ' || p_flag_count
                                 || ' flag(s) and is waiting for a person.',
                p_document_id => l_document_id
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action      => 'PROCESS_ERROR',
                p_details     => 'PROCESS_STAGING failed for staged invoice ' || p_stg_header_id || ': ' || SQLERRM,
                p_document_id => l_document_id
            );
            RAISE;
    END process_staging;

    /* --------------------------------------------------------
       Public  : LOAD_INVOICE
       Purpose : Copy an APPROVED staged invoice to the final
                 tables. Raises ORA-20070 if it does not exist,
                 is not APPROVED, was already loaded, or is
                 missing a field the final table requires.
                 LOADED_BY is whoever approved the invoice:
                 AGENT when the agent approved it, otherwise the
                 person who approved it on the review page.
       -------------------------------------------------------- */
    FUNCTION load_invoice (
        p_stg_header_id  IN NUMBER
    ) RETURN NUMBER IS
        l_h           dla_stg_headers%ROWTYPE;
        l_user        dla_invoices.loaded_by%TYPE;
        l_count       NUMBER;
        l_invoice_id  dla_invoices.invoice_id%TYPE;
        l_line_count  NUMBER;
    BEGIN
        l_user := current_user_name;

        BEGIN
            SELECT h.*
            INTO   l_h
            FROM   dla_stg_headers h
            WHERE  h.stg_header_id = p_stg_header_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    -20070,
                    'DLA_PKG.LOAD_INVOICE: there is no staged invoice ' || p_stg_header_id || '.'
                );
        END;

        IF l_h.review_status <> 'APPROVED' THEN
            RAISE_APPLICATION_ERROR(
                -20070,
                'DLA_PKG.LOAD_INVOICE: staged invoice ' || p_stg_header_id || ' is '
                || l_h.review_status || ', not APPROVED.'
            );
        END IF;

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_invoices i
        WHERE  i.stg_header_id = p_stg_header_id;

        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20070,
                'DLA_PKG.LOAD_INVOICE: staged invoice ' || p_stg_header_id || ' has already been loaded.'
            );
        END IF;

        IF l_h.vendor_id IS NULL
           OR l_h.invoice_number IS NULL
           OR l_h.invoice_date IS NULL
           OR l_h.total IS NULL
        THEN
            RAISE_APPLICATION_ERROR(
                -20070,
                'DLA_PKG.LOAD_INVOICE: staged invoice ' || p_stg_header_id
                || ' cannot be loaded. It needs a known vendor, an invoice number, an invoice date and a total.'
            );
        END IF;

        INSERT INTO dla_invoices (
            vendor_id,
            invoice_number,
            invoice_date,
            due_date,
            subtotal,
            tax,
            total,
            document_id,
            stg_header_id,
            loaded_by
        ) VALUES (
            l_h.vendor_id,
            l_h.invoice_number,
            l_h.invoice_date,
            l_h.due_date,
            l_h.subtotal,
            l_h.tax,
            l_h.total,
            l_h.document_id,
            p_stg_header_id,
            NVL(l_h.reviewed_by, l_user)
        )
        RETURNING invoice_id INTO l_invoice_id;

        INSERT INTO dla_invoice_lines (
            invoice_id,
            line_number,
            description,
            quantity,
            unit_price,
            amount
        )
        SELECT l_invoice_id,
               l.line_number,
               l.description,
               l.quantity,
               l.unit_price,
               l.amount
        FROM   dla_stg_lines l
        WHERE  l.stg_header_id = p_stg_header_id;

        l_line_count := SQL%ROWCOUNT;

        UPDATE dla_documents d
        SET    d.status      = 'LOADED'
        WHERE  d.document_id = l_h.document_id;

        log_audit(
            p_action      => 'LOADED',
            p_details     => 'Invoice ' || l_h.invoice_number || ' loaded as invoice ' || l_invoice_id
                             || ' with ' || l_line_count || ' line(s), total ' || money(l_h.total)
                             || '. Approved by ' || l_h.reviewed_by || '.',
            p_document_id => l_h.document_id
        );

        RETURN l_invoice_id;
    EXCEPTION
        WHEN OTHERS THEN
            log_audit(
                p_action      => 'LOAD_ERROR',
                p_details     => 'LOAD_INVOICE failed for staged invoice ' || p_stg_header_id || ': ' || SQLERRM,
                p_document_id => l_h.document_id
            );
            RAISE;
    END load_invoice;

END dla_pkg;
/

SHOW ERRORS PACKAGE BODY dla_pkg

/* ------------------------------------------------------------
   Test 1  : Call a working routine
   Purpose : Proves the package runs. Expect the line
             "ACTIVE_MODEL = OLLAMA" in the Script Output.
   ------------------------------------------------------------ */
BEGIN
    DBMS_OUTPUT.PUT_LINE('ACTIVE_MODEL = ' || dla_pkg.get_setting('ACTIVE_MODEL'));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TEST FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Check 1 : Package status
   Purpose : Expect 2 rows (PACKAGE and PACKAGE BODY), both
             STATUS = VALID.
   ------------------------------------------------------------ */
SELECT owner,
       object_type,
       object_name,
       status
FROM   all_objects
WHERE  owner = 'WKSP_WKSPPRDWORKSPACE'
AND    object_name = 'DLA_PKG'
ORDER  BY object_type;
