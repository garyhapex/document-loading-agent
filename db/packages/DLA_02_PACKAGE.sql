/* ============================================================
   Script      : DLA_02_PACKAGE.sql
   Project     : Document Loading Agent (DLA) - Phase 1
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - creates package DLA_PKG (spec and body)
                 and writes one row to DLA_AUDIT_LOG as a test.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Run after   : DLA_01_CREATE_TABLES.sql
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
   Purpose      : The one package behind the Document Loading
                  Agent. Phase 1 delivers the working utilities
                  (LOG_AUDIT, GET_SETTING, SET_SETTING). The
                  other four are placeholders that raise a clear
                  error until their phase builds them.
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

    /* Phase 2 placeholder: sends a document to the chosen model.
       Will return the new EXTRACTION_ID. */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    /* Phase 2 placeholder: parses the JSON into staging.
       Will return the new STG_HEADER_ID. */
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
    BEGIN
        INSERT INTO dla_audit_log (
            document_id,
            action,
            details,
            performed_by
        ) VALUES (
            p_document_id,
            SUBSTR(p_action, 1, 50),
            SUBSTR(p_details, 1, 4000),
            current_user_name
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
    BEGIN
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
               s.updated_by    = current_user_name,
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
       Public  : PARSE_EXTRACTION  (Phase 2 placeholder)
       -------------------------------------------------------- */
    FUNCTION parse_extraction (
        p_extraction_id  IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        not_built_yet('PARSE_EXTRACTION', 'Phase 2');
        RETURN NULL;
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
   Test 1  : Call the two working routines
   Purpose : Proves the package runs. Expect the line
             "ACTIVE_MODEL = OLLAMA" in the Script Output.
   ------------------------------------------------------------ */
BEGIN
    dla_pkg.log_audit(
        p_action  => 'PHASE1_INSTALL',
        p_details => 'DLA_PKG installed and LOG_AUDIT tested.'
    );
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

/* ------------------------------------------------------------
   Check 2 : Audit log
   Purpose : Expect 1 row with ACTION = PHASE1_INSTALL.
   ------------------------------------------------------------ */
SELECT audit_id,
       action,
       details,
       performed_by,
       performed_on
FROM   dla_audit_log
ORDER  BY audit_id;
