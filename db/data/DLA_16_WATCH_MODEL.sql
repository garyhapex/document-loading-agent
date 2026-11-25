/* ============================================================
   Script      : DLA_16_WATCH_MODEL.sql
   Project     : Document Loading Agent (DLA) - Phase 4
   Environment : DEV by hand (SQL Developer); PRD by the pipeline
   Changes     : YES - sets one row in DLA_SETTINGS: WATCH_MODEL.
                 Changes nothing else.
   Purpose     : Chooses which reader the watched folder
                 (C:\DLA\inbox) feeds:
                   OLLAMA    = the relay on Gary's PC, local model
                   OCI_GENAI = Google Gemini 2.5 Flash on OCI, via
                               the APEX automation "Read waiting
                               documents" (runs every minute)
                 The value is on the one line marked CHANGE HERE.
                 Run this file again whenever you want to switch.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN or WKSP_WKSPPRDWORKSPACE
                 SQL Developer, F5 (Run Script)
   Run after   : DLA_04_RELAY_DATABASE.sql (the 11/20 version)
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/20/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Set WATCH_MODEL
   ------------------------------------------------------------ */
DECLARE
    l_value  VARCHAR2(30) := 'OLLAMA';   /* CHANGE HERE: OLLAMA or OCI_GENAI */
BEGIN
    IF l_value NOT IN ('OLLAMA', 'OCI_GENAI') THEN
        RAISE_APPLICATION_ERROR(-20016, 'WATCH_MODEL must be OLLAMA or OCI_GENAI, not ' || l_value || '.');
    END IF;

    MERGE INTO dla_settings s
    USING (SELECT 'WATCH_MODEL' AS setting_name FROM dual) x
    ON    (s.setting_name = x.setting_name)
    WHEN MATCHED THEN
        UPDATE SET s.setting_value = l_value,
                   s.updated_by    = USER,
                   s.updated_on    = SYSDATE
    WHEN NOT MATCHED THEN
        INSERT (setting_name, setting_value, description, updated_by, updated_on)
        VALUES ('WATCH_MODEL', l_value,
                'Which reader the watched folder feeds: OLLAMA (the relay) or OCI_GENAI (the APEX automation)',
                USER, SYSDATE);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('WATCH_MODEL = ' || l_value);
END;
/

/* ------------------------------------------------------------
   Check 1 : The setting
   ------------------------------------------------------------ */
SELECT s.setting_name,
       s.setting_value,
       s.updated_by,
       s.updated_on
FROM   dla_settings s
WHERE  s.setting_name IN ('WATCH_MODEL', 'ACTIVE_MODEL', 'OCI_MODEL', 'OLLAMA_MODEL')
ORDER  BY s.setting_name;
