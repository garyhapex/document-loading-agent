/* ============================================================
   Script      : DLA_08_VALIDATION_COLUMNS.sql
   Project     : Document Loading Agent (DLA) - Phase 3
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - adds one column, FLAG_SOURCE, to
                 DLA_STG_FLAGS. Changes no existing data.
   Purpose     : A flag now records where it came from:
                   PARSE = a value the model returned would not
                           convert to a date or number
                   CHECK = one of the agent's checks found a
                           problem
                 The checks need this so they can be run again
                 and replace only their own flags.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run before  : DLA_02_PACKAGE.sql (the version with the checks)
   Re-runnable : yes - does nothing if the column is there
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Add FLAG_SOURCE if it is not there
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
    AND    c.table_name  = 'DLA_STG_FLAGS'
    AND    c.column_name = 'FLAG_SOURCE';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE
            q'[ALTER TABLE dla_stg_flags ADD (
                   flag_source VARCHAR2(10) DEFAULT 'PARSE' NOT NULL,
                   CONSTRAINT dla_stg_flags_source_ck CHECK (flag_source IN ('PARSE', 'CHECK'))
               )]';
        DBMS_OUTPUT.PUT_LINE('FLAG_SOURCE added to DLA_STG_FLAGS.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('FLAG_SOURCE is already there. Nothing changed.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/
