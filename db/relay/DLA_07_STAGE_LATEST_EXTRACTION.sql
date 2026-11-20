/* ============================================================
   Script      : DLA_07_STAGE_LATEST_EXTRACTION.sql
   Project     : Document Loading Agent (DLA) - Phase 2
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - writes staging rows (DLA_STG_HEADERS,
                 DLA_STG_LINES, DLA_STG_FLAGS) for the latest
                 successful extraction, and one audit row.
   Purpose     : Test DLA_PKG.PARSE_EXTRACTION: turn the JSON the
                 model returned into rows, then show the rows.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run after   : DLA_02_PACKAGE.sql (the version with
                 PARSE_EXTRACTION built)
   Re-runnable : yes - replaces the staging rows for that
                 extraction
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON
COLUMN vendor_name     FORMAT A30
COLUMN invoice_number  FORMAT A14
COLUMN review_status   FORMAT A10
COLUMN description     FORMAT A50
COLUMN field_name      FORMAT A14
COLUMN severity        FORMAT A8
COLUMN message         FORMAT A90

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Stage the latest successful extraction
   Purpose : Calls DLA_PKG.PARSE_EXTRACTION and commits. Rolls
             back and re-raises on any failure.
   ------------------------------------------------------------ */
DECLARE
    l_extraction_id  NUMBER;
    l_stg_header_id  NUMBER;
BEGIN
    SELECT MAX(e.extraction_id)
    INTO   l_extraction_id
    FROM   dla_extractions e
    WHERE  e.status = 'SUCCESS';

    IF l_extraction_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20041, 'There is no successful extraction to stage yet.');
    END IF;

    l_stg_header_id := dla_pkg.parse_extraction(l_extraction_id);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Extraction ' || l_extraction_id || ' staged as header ' || l_stg_header_id || '.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Query 1 : Staging header
   Purpose : Expect one row for INV-10001. VENDOR_ID should be
             filled in, because Prairie Fastener Supply Co. is
             in DLA_VENDORS.
   ------------------------------------------------------------ */
SELECT h.stg_header_id,
       h.vendor_name,
       h.vendor_id,
       h.invoice_number,
       h.invoice_date,
       h.due_date,
       h.subtotal,
       h.tax,
       h.total,
       h.review_status
FROM   dla_stg_headers h
ORDER  BY h.stg_header_id;

/* ------------------------------------------------------------
   Query 2 : Staging lines
   Purpose : Expect 3 lines: 174.00, 78.00 and 112.00.
   ------------------------------------------------------------ */
SELECT l.stg_header_id,
       l.line_number,
       l.description,
       l.quantity,
       l.unit_price,
       l.amount
FROM   dla_stg_lines l
ORDER  BY l.stg_header_id,
          l.line_number;

/* ------------------------------------------------------------
   Query 3 : Staging flags
   Purpose : Expect no rows. A flag here means the model
             returned a date or amount that would not convert.
   ------------------------------------------------------------ */
SELECT f.stg_header_id,
       f.field_name,
       f.severity,
       f.message
FROM   dla_stg_flags f
ORDER  BY f.flag_id;
