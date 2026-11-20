/* ============================================================
   Script      : DLA_14_REMOVE_OCI_ERROR_ROWS.sql
   Project     : Document Loading Agent (DLA) - Phase 4
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - deletes documents whose ONLY read was an
                 OCI_GENAI read that ended in ERROR, with their
                 extraction rows. Audit rows are kept (history).
                 Nothing staged or loaded is touched: a document
                 that reached staging has a review status and is
                 kept.
                 11/20/2026: ORA-12860 on the first two runs was
                 parallel DML on the Autonomous Database service;
                 fixed with ALTER SESSION DISABLE PARALLEL DML.
                 The rows were then removed by Claude from SQL
                 Commands, so this script found nothing left to do.
   Purpose     : The first OCI test on 11/20/2026 stored six
                 documents as ERROR because of a fence-stripping
                 fault in DLA_PKG (fixed the same morning). They
                 are test clutter on the Upload page, not
                 history worth keeping.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN or WKSP_WKSPPRDWORKSPACE
                 SQL Developer, F5 (Run Script)
   Re-runnable : yes (deletes nothing the second time)
   Author      : Claude for Gary D. Hall
   Date        : 11/20/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* Autonomous Database runs deletes in parallel on the HIGH and
   MEDIUM services, and parallel deletes in a loop raise ORA-12860.
   This turns that off for this session only. (Found 11/20/2026.) */
ALTER SESSION DISABLE PARALLEL DML;

/* ------------------------------------------------------------
   Step 1  : Show what will go
   Purpose : Read-only look before the delete.
   ------------------------------------------------------------ */
SELECT d.document_id,
       d.file_name,
       d.status,
       e.extraction_id,
       e.model_code,
       e.status AS read_status,
       SUBSTR(e.error_message, 1, 80) AS error_message
FROM   dla_documents   d,
       dla_extractions e
WHERE  e.document_id = d.document_id
AND    d.status      = 'ERROR'
AND    NOT EXISTS (SELECT 1
                   FROM   dla_extractions e2
                   WHERE  e2.document_id = d.document_id
                   AND   (e2.model_code <> 'OCI_GENAI' OR e2.status <> 'ERROR'))
AND    NOT EXISTS (SELECT 1
                   FROM   dla_stg_headers h
                   WHERE  h.document_id = d.document_id)
ORDER  BY d.document_id;

/* ------------------------------------------------------------
   Step 2  : Delete them
   ------------------------------------------------------------ */
DECLARE
    l_docs   NUMBER := 0;
    l_reads  NUMBER := 0;
BEGIN
    FOR r IN (SELECT d.document_id
              FROM   dla_documents d
              WHERE  d.status = 'ERROR'
              AND    NOT EXISTS (SELECT 1
                                 FROM   dla_extractions e2
                                 WHERE  e2.document_id = d.document_id
                                 AND   (e2.model_code <> 'OCI_GENAI' OR e2.status <> 'ERROR'))
              AND    NOT EXISTS (SELECT 1
                                 FROM   dla_stg_headers h
                                 WHERE  h.document_id = d.document_id)) LOOP
        DELETE FROM dla_extractions e WHERE e.document_id = r.document_id;
        l_reads := l_reads + SQL%ROWCOUNT;
        DELETE FROM dla_documents d   WHERE d.document_id = r.document_id;
        l_docs := l_docs + SQL%ROWCOUNT;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Removed ' || l_docs || ' document(s) and ' || l_reads || ' read(s).');
END;
/
