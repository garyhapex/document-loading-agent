/* ============================================================
   Script      : DLA_17_COMPARE_COLUMN.sql
   Project     : Document Loading Agent (DLA) - Phase 4
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - adds one column, PURPOSE, to
                 DLA_EXTRACTIONS. Existing rows get LOAD.
   Purpose     : A read now says why it was made:
                   LOAD    = the normal path: the answer is
                             staged, checked, and loaded or
                             stopped for a person
                   COMPARE = made by the compare page (page 4)
                             to put the two models side by side.
                             The answer is stored and shown, but
                             NOT staged or loaded, so a compare
                             never creates a second copy of an
                             invoice in the review queue.
                 DLA_02_PACKAGE.sql and DLA_04_RELAY_DATABASE.sql
                 (the versions dated 11/21/2026) read this column.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run before  : DLA_02_PACKAGE.sql and DLA_04_RELAY_DATABASE.sql
                 (the 11/21/2026 versions)
   Re-runnable : yes - does nothing if the column is there
   Author      : Claude for Gary D. Hall
   Date        : 11/21/2026
   ============================================================ */

SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Add PURPOSE if it is not there
   Purpose : Looks in ALL_TAB_COLUMNS first, so the script can be
             run more than once. Re-raises any failure.
   ------------------------------------------------------------ */
DECLARE
    l_count  NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_count
    FROM   all_tab_columns c
    WHERE  c.owner       = 'WKSP_WKSPPRDWORKSPACE'
    AND    c.table_name  = 'DLA_EXTRACTIONS'
    AND    c.column_name = 'PURPOSE';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE
            q'[ALTER TABLE dla_extractions ADD (
                   purpose VARCHAR2(10) DEFAULT 'LOAD' NOT NULL,
                   CONSTRAINT dla_extractions_purpose_ck CHECK (purpose IN ('LOAD', 'COMPARE'))
               )]';
        DBMS_OUTPUT.PUT_LINE('PURPOSE added to DLA_EXTRACTIONS.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('PURPOSE is already there. Nothing changed.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Check   : The column and how the existing reads are marked
   ------------------------------------------------------------ */
SELECT e.purpose,
       e.model_code,
       COUNT(*) AS reads
FROM   dla_extractions e
GROUP  BY e.purpose, e.model_code
ORDER  BY e.purpose, e.model_code;
