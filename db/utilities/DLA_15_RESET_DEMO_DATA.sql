/* ============================================================
   Script      : DLA_15_RESET_DEMO_DATA.sql
   Project     : Document Loading Agent (DLA) - Phase 4
   Environment : DEV or PRD, by hand (SQL Developer). Demo data
                 only: the invoices are fictional samples.
                 (11/25/2026: PRD allowed, the demo now runs
                 on PRD.)
   Changes     : YES - DESTRUCTIVE for demo data. Empties these
                 tables: DLA_INVOICE_LINES, DLA_INVOICES,
                 DLA_STG_FLAGS, DLA_STG_LINES, DLA_STG_HEADERS,
                 DLA_EXTRACTIONS, DLA_DOCUMENTS, DLA_AUDIT_LOG.
                 KEEPS: DLA_VENDORS and DLA_SETTINGS (the token,
                 the prompt, the model settings).
   Purpose     : A fresh start before a demo. Every invoice ever
                 loaded is gone, so the six gas PDFs dropped in
                 again play the whole story: two load, four stop.
                 Run it, then drop the PDFs on page 2 or into
                 C:\DLA\inbox.
   Safety      : Stops with ORA-20015 if a read is RUNNING
                 (the relay or OCI is in the middle of one), so
                 nothing is pulled out from under a read.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN or WKSP_WKSPPRDWORKSPACE
                 SQL Developer, F5 (Run Script)
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/20/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* Autonomous Database runs SQL Developer's DML in parallel on the
   HIGH and MEDIUM services; that raises ORA-12860 on deletes.
   Off for this session only. */
ALTER SESSION DISABLE PARALLEL DML;

/* ------------------------------------------------------------
   Step 1  : What is there now
   Purpose : Read-only count before the reset.
   ------------------------------------------------------------ */
SELECT 'DLA_DOCUMENTS'     AS table_name, COUNT(*) AS rows_now FROM dla_documents
UNION ALL SELECT 'DLA_EXTRACTIONS',   COUNT(*) FROM dla_extractions
UNION ALL SELECT 'DLA_STG_HEADERS',   COUNT(*) FROM dla_stg_headers
UNION ALL SELECT 'DLA_STG_LINES',     COUNT(*) FROM dla_stg_lines
UNION ALL SELECT 'DLA_STG_FLAGS',     COUNT(*) FROM dla_stg_flags
UNION ALL SELECT 'DLA_INVOICES',      COUNT(*) FROM dla_invoices
UNION ALL SELECT 'DLA_INVOICE_LINES', COUNT(*) FROM dla_invoice_lines
UNION ALL SELECT 'DLA_AUDIT_LOG',     COUNT(*) FROM dla_audit_log;

/* ------------------------------------------------------------
   Step 2  : The reset
   Purpose : Children first, parents last, so no foreign key
             complains. Vendors and settings are not touched.
   ------------------------------------------------------------ */
DECLARE
    l_running  NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_running
    FROM   dla_extractions e
    WHERE  e.status = 'RUNNING';

    IF l_running > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20015,
            l_running || ' read(s) are RUNNING right now. Wait for the relay to finish '
            || '(the relay service or OCI is reading), then run this script again.'
        );
    END IF;

    DELETE FROM dla_invoice_lines;  DBMS_OUTPUT.PUT_LINE('DLA_INVOICE_LINES : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_invoices;       DBMS_OUTPUT.PUT_LINE('DLA_INVOICES      : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_stg_flags;      DBMS_OUTPUT.PUT_LINE('DLA_STG_FLAGS     : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_stg_lines;      DBMS_OUTPUT.PUT_LINE('DLA_STG_LINES     : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_stg_headers;    DBMS_OUTPUT.PUT_LINE('DLA_STG_HEADERS   : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_extractions;    DBMS_OUTPUT.PUT_LINE('DLA_EXTRACTIONS   : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_documents;      DBMS_OUTPUT.PUT_LINE('DLA_DOCUMENTS     : ' || SQL%ROWCOUNT || ' removed');
    DELETE FROM dla_audit_log;      DBMS_OUTPUT.PUT_LINE('DLA_AUDIT_LOG     : ' || SQL%ROWCOUNT || ' removed');

    COMMIT;

    dla_pkg.log_audit(
        p_action  => 'DEMO_RESET',
        p_details => 'Demo data reset by ' || USER || '. Vendors and settings kept.'
    );
    DBMS_OUTPUT.PUT_LINE('Reset done. Vendors and settings kept.');
END;
/

/* ------------------------------------------------------------
   Check 1 : What is left
   Purpose : Expect 0 for every table except DLA_AUDIT_LOG (1,
             the reset line itself).
   ------------------------------------------------------------ */
SELECT 'DLA_DOCUMENTS'     AS table_name, COUNT(*) AS rows_left FROM dla_documents
UNION ALL SELECT 'DLA_EXTRACTIONS',   COUNT(*) FROM dla_extractions
UNION ALL SELECT 'DLA_STG_HEADERS',   COUNT(*) FROM dla_stg_headers
UNION ALL SELECT 'DLA_STG_LINES',     COUNT(*) FROM dla_stg_lines
UNION ALL SELECT 'DLA_STG_FLAGS',     COUNT(*) FROM dla_stg_flags
UNION ALL SELECT 'DLA_INVOICES',      COUNT(*) FROM dla_invoices
UNION ALL SELECT 'DLA_INVOICE_LINES', COUNT(*) FROM dla_invoice_lines
UNION ALL SELECT 'DLA_AUDIT_LOG',     COUNT(*) FROM dla_audit_log;

/* ------------------------------------------------------------
   Check 2 : Kept
   Purpose : Expect 9 vendors and the settings still there.
   ------------------------------------------------------------ */
SELECT 'DLA_VENDORS'  AS table_name, COUNT(*) AS rows_kept FROM dla_vendors
UNION ALL SELECT 'DLA_SETTINGS', COUNT(*) FROM dla_settings;
