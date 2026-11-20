/* ============================================================
   Script      : DLA_02_PACKAGE.sql
   Project     : Document Loading Agent (DLA) - Phase 1
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - creates or replaces package DLA_PKG (spec
                 and body). Changes no data.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Run after   : DLA_01_CREATE_TABLES.sql
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
                  SET_SETTING, SUBMIT_DOCUMENT, PARSE_EXTRACTION.
                  The other three
                  are placeholders that raise a clear error until
                  their phase builds them.
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

    /* Phase 2 placeholder: sends a document to the chosen model.
       Will return the new EXTRACTION_ID. */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    /* Working: reads the model's JSON for one extraction with
       JSON_TABLE and writes it to the staging tables. Returns
       the new STG_HEADER_ID. Does not commit. Running it again
       for the same extraction replaces that extraction's
       staging rows. */
    FUNCTION parse_extraction (
        p_extraction_id  IN NUMBER
    ) RETURN NUMBER;

    /* Phase 3 placeholder: runs the checks and writes DLA_STG_FLAGS. */
    PROCEDURE validate_staging (
        p_stg_header_id  IN NUMBER
    );

    /* Phase 3 placeholder: loads an approved invoice to the final tables.
       Will return the new INVOICE_ID. */
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
       Public  : EXTRACT_DOCUMENT  (Phase 2 placeholder)
       -------------------------------------------------------- */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER IS
    BEGIN
        not_built_yet('EXTRACT_DOCUMENT', 'Phase 2');
        RETURN NULL;
    END extract_document;

    /* --------------------------------------------------------
       Private : ADD_FLAG
       Purpose : Write one row to DLA_STG_FLAGS.
       -------------------------------------------------------- */
    PROCEDURE add_flag (
        p_stg_header_id  IN NUMBER,
        p_field_name     IN VARCHAR2,
        p_severity       IN VARCHAR2,
        p_message        IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO dla_stg_flags (
            stg_header_id,
            field_name,
            severity,
            message
        ) VALUES (
            p_stg_header_id,
            p_field_name,
            p_severity,
            SUBSTR(p_message, 1, 1000)
        );
    END add_flag;

    /* --------------------------------------------------------
       Public  : PARSE_EXTRACTION
       Purpose : Turn the model's JSON into staging rows.
                 1. Header fields come out with JSON_TABLE. Each
                    date and amount is read twice: as text, and
                    converted. If the text is there but will not
                    convert, the field is left empty and a
                    WARNING flag says what the model returned.
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
               TO_DATE(jt.invoice_date_txt DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD'),
               TO_DATE(jt.due_date_txt     DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD'),
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
               l_invoice_date,
               l_due_date,
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
                     'The model returned "' || l_inv_date_txt || '", which is not a date in YYYY-MM-DD form.');
        END IF;
        IF l_due_date_txt IS NOT NULL AND l_due_date IS NULL THEN
            add_flag(l_stg_header_id, 'DUE_DATE', 'WARNING',
                     'The model returned "' || l_due_date_txt || '", which is not a date in YYYY-MM-DD form.');
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
       Public  : VALIDATE_STAGING  (Phase 3 placeholder)
       -------------------------------------------------------- */
    PROCEDURE validate_staging (
        p_stg_header_id  IN NUMBER
    ) IS
    BEGIN
        not_built_yet('VALIDATE_STAGING', 'Phase 3');
    END validate_staging;

    /* --------------------------------------------------------
       Public  : LOAD_INVOICE  (Phase 3 placeholder)
       -------------------------------------------------------- */
    FUNCTION load_invoice (
        p_stg_header_id  IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        not_built_yet('LOAD_INVOICE', 'Phase 3');
        RETURN NULL;
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
