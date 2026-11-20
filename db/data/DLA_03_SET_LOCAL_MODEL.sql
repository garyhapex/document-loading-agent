/* ============================================================
   Script      : DLA_03_SET_LOCAL_MODEL.sql
   Project     : Document Loading Agent (DLA) - Phase 2
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - updates one row in DLA_SETTINGS
                 (OLLAMA_MODEL) and writes one audit row.
   Purpose     : The local model changed from llama3.2-vision to
                 qwen2.5vl:7b, because llama3.2-vision does not
                 run on Ollama 0.30.0 and later.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Run after   : DLA_02_PACKAGE.sql
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
   Block   : Set the local model name
   Purpose : Uses DLA_PKG.SET_SETTING so the change is logged in
             DLA_AUDIT_LOG. Rolls back and re-raises on failure.
   ------------------------------------------------------------ */
BEGIN
    dla_pkg.set_setting(
        p_setting_name  => 'OLLAMA_MODEL',
        p_setting_value => 'qwen2.5vl:7b'
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OLLAMA_MODEL = ' || dla_pkg.get_setting('OLLAMA_MODEL'));
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Check 1 : Settings
   Purpose : Expect OLLAMA_MODEL = qwen2.5vl:7b.
   ------------------------------------------------------------ */
SELECT setting_name,
       setting_value
FROM   dla_settings
ORDER  BY setting_name;
