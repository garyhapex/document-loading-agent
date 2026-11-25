/* ============================================================
   Script      : DLA_12_REREAD_DOCUMENT.sql
   Project     : Document Loading Agent (DLA) - Phase 3
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - for each document number listed in the
                 block below (currently 5 and 7):
                 1. Deletes the invoice loaded from it, with its
                    lines (DLA_INVOICES, DLA_INVOICE_LINES)
                 2. Deletes its staged copy, with its lines and
                    flags (DLA_STG_HEADERS, DLA_STG_LINES,
                    DLA_STG_FLAGS)
                 3. Sets the document back to UPLOADED
                 4. Puts it back in the queue for the local model
                 The uploaded file and the earlier reads in
                 DLA_EXTRACTIONS are kept.
   Purpose     : Takes documents back and has them read and
                 decided again from the start. Used after the
                 prompt or the checks change, to prove the change.
                 Document 5 is GAS_02, a clean invoice: it must
                 load again by itself. Document 7 is GAS_04, the
                 invoice with no invoice date: it must stop for a
                 person. After this runs, the relay picks them up
                 by itself, one at a time, about 5 minutes each.
   To use on other documents: change the numbers on the line
                 marked CHANGE HERE, and in Check 1.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run after   : DLA_02_PACKAGE_BODY.sql and DLA_11_GAS_TEST_FIXES.sql
   Re-runnable : yes, but it refuses while any listed document
                 is already waiting or being read (ORA-20080),
                 and then changes nothing at all
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 200
SET SERVEROUTPUT ON
COLUMN file_name        FORMAT A50
COLUMN document_status  FORMAT A15
COLUMN model_name       FORMAT A14
COLUMN read_status      FORMAT A11

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Take each document back and queue it again
   Purpose : Every change for every listed document succeeds
             together or none do. Rolls back, logs and re-raises
             on failure.
   ------------------------------------------------------------ */
DECLARE
    l_documents      CONSTANT SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(5, 7);   /* CHANGE HERE */
    l_document_id    NUMBER;
    l_count          NUMBER;
    l_invoices       NUMBER;
    l_staged         NUMBER;
    l_extraction_id  NUMBER;
BEGIN
    FOR i IN 1 .. l_documents.COUNT LOOP
        l_document_id := l_documents(i);

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_documents d
        WHERE  d.document_id = l_document_id;

        IF l_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20080, 'DLA_12: there is no document ' || l_document_id || '. Nothing was changed.');
        END IF;

        SELECT COUNT(*)
        INTO   l_count
        FROM   dla_extractions e
        WHERE  e.document_id = l_document_id
        AND    e.status IN ('PENDING', 'RUNNING');

        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20080,
                'DLA_12: document ' || l_document_id || ' is already waiting or being read. Nothing was changed.'
            );
        END IF;

        /* 1. The loaded invoice. Its lines go with it (cascade). */
        DELETE FROM dla_invoices inv
        WHERE  inv.document_id = l_document_id;
        l_invoices := SQL%ROWCOUNT;

        /* 2. The staged copy. Its lines and flags go with it (cascade). */
        DELETE FROM dla_stg_headers h
        WHERE  h.document_id = l_document_id;
        l_staged := SQL%ROWCOUNT;

        /* 3. Back to the start */
        UPDATE dla_documents d
        SET    d.status      = 'UPLOADED'
        WHERE  d.document_id = l_document_id;

        /* 4. Back in the queue for the local model */
        l_extraction_id := dla_relay_pkg.queue_extraction(l_document_id);

        dla_pkg.log_audit(
            p_action      => 'REREAD',
            p_details     => 'Document ' || l_document_id || ' taken back: ' || l_invoices
                             || ' loaded invoice(s) and ' || l_staged
                             || ' staged invoice(s) removed. Queued again as extraction ' || l_extraction_id || '.',
            p_document_id => l_document_id
        );

        DBMS_OUTPUT.PUT_LINE('Document ' || l_document_id || ': ' || l_invoices || ' loaded invoice(s) removed, '
                             || l_staged || ' staged invoice(s) removed, queued again as extraction '
                             || l_extraction_id || '.');
    END LOOP;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        dla_pkg.log_audit(
            p_action      => 'REREAD_ERROR',
            p_details     => 'DLA_12 failed at document ' || l_document_id || ': ' || SQLERRM,
            p_document_id => l_document_id
        );
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Check 1 : The documents and their reads
   Purpose : Expect document status UPLOADED, the earlier reads
             as SUCCESS and one new read per document as PENDING
             (or RUNNING if the relay has already picked it up).
             If you changed the document numbers above, change
             them in this query too.
   ------------------------------------------------------------ */
SELECT d.document_id,
       d.file_name,
       d.status        AS document_status,
       e.extraction_id,
       e.model_name,
       e.status        AS read_status
FROM   dla_documents   d,
       dla_extractions e
WHERE  e.document_id (+) = d.document_id
AND    d.document_id IN (5, 7)
ORDER  BY d.document_id,
          e.extraction_id;
