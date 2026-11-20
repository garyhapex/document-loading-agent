/* ============================================================
   Script      : DLA_09_PROCESS_STAGED.sql
   Project     : Document Loading Agent (DLA) - Phase 3
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - for every staged invoice still PENDING and
                 not yet checked: runs the checks, then loads it
                 (if clean) or leaves it for review (if flagged).
                 Writes DLA_STG_FLAGS, DLA_INVOICES,
                 DLA_INVOICE_LINES and DLA_AUDIT_LOG.
   Purpose     : Invoices read before the checks existed are
                 sitting in staging. This puts them through the
                 agent's decision, oldest first. From now on the
                 relay does this by itself for each new invoice.
                 Also the script to run to see where everything
                 stands.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run after   : DLA_02_PACKAGE.sql and DLA_04_RELAY_DATABASE.sql
   Re-runnable : yes - an invoice already checked is skipped
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 200
SET SERVEROUTPUT ON
COLUMN vendor_name     FORMAT A30
COLUMN invoice_number  FORMAT A14
COLUMN review_status   FORMAT A10
COLUMN reviewed_by     FORMAT A10
COLUMN document_status FORMAT A10
COLUMN field_name      FORMAT A14
COLUMN severity        FORMAT A8
COLUMN flag_source     FORMAT A6
COLUMN message         FORMAT A110
COLUMN loaded_by       FORMAT A22

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Put every unchecked PENDING staged invoice through
             the agent
   Purpose : Oldest first, so the first copy of a duplicate is
             the one that loads. Each invoice is committed on its
             own; a failure on one is reported and the rest carry
             on.
   ------------------------------------------------------------ */
DECLARE
    l_invoice_id  NUMBER;
    l_flag_count  NUMBER;
    l_done        NUMBER := 0;
BEGIN
    FOR r IN (SELECT h.stg_header_id,
                     h.invoice_number
              FROM   dla_stg_headers h
              WHERE  h.review_status = 'PENDING'
              AND    NOT EXISTS (SELECT 1
                                 FROM   dla_stg_flags f
                                 WHERE  f.stg_header_id = h.stg_header_id
                                 AND    f.flag_source   = 'CHECK')
              ORDER  BY h.stg_header_id)
    LOOP
        BEGIN
            dla_pkg.process_staging(
                p_stg_header_id => r.stg_header_id,
                p_invoice_id    => l_invoice_id,
                p_flag_count    => l_flag_count
            );
            COMMIT;
            l_done := l_done + 1;
            IF l_invoice_id IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE('Staged invoice ' || r.stg_header_id || ' (' || r.invoice_number
                                     || '): clean. Loaded as invoice ' || l_invoice_id || '.');
            ELSE
                DBMS_OUTPUT.PUT_LINE('Staged invoice ' || r.stg_header_id || ' (' || r.invoice_number
                                     || '): ' || l_flag_count || ' flag(s). Waiting for review.');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK;
                DBMS_OUTPUT.PUT_LINE('Staged invoice ' || r.stg_header_id || ' FAILED: ' || SQLERRM);
        END;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(l_done || ' staged invoice(s) processed.');
END;
/

/* ------------------------------------------------------------
   Query 1 : Every staged invoice and what was decided
   Purpose : REVIEWED_BY = AGENT means the agent approved it by
             itself. PENDING means it is waiting for a person.
   ------------------------------------------------------------ */
SELECT h.stg_header_id,
       h.vendor_name,
       h.invoice_number,
       h.total,
       h.review_status,
       h.reviewed_by,
       d.status AS document_status
FROM   dla_stg_headers h,
       dla_documents   d
WHERE  d.document_id = h.document_id
ORDER  BY h.stg_header_id;

/* ------------------------------------------------------------
   Query 2 : Flags
   Purpose : Why each flagged invoice was stopped.
   ------------------------------------------------------------ */
SELECT f.stg_header_id,
       f.field_name,
       f.severity,
       f.flag_source,
       f.message
FROM   dla_stg_flags f
ORDER  BY f.stg_header_id,
          f.flag_id;

/* ------------------------------------------------------------
   Query 3 : Loaded invoices
   Purpose : What is in the final table, with the line count.
   ------------------------------------------------------------ */
SELECT i.invoice_id,
       v.vendor_name,
       i.invoice_number,
       i.invoice_date,
       i.total,
       (SELECT COUNT(*)
        FROM   dla_invoice_lines l
        WHERE  l.invoice_id = i.invoice_id) AS line_count,
       i.loaded_by
FROM   dla_invoices i,
       dla_vendors  v
WHERE  v.vendor_id = i.vendor_id
ORDER  BY i.invoice_id;
