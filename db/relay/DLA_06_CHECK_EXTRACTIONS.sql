/* ============================================================
   Script      : DLA_06_CHECK_EXTRACTIONS.sql
   Project     : Document Loading Agent (DLA) - Phase 2
   Environment : DEV (GHAPEXAPPS_ATP_DEV)
   Changes     : NONE - read-only
   Purpose     : Show what the models have read so far, and the
                 last entries in the audit log.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET LINESIZE 200
SET PAGESIZE 200
SET LONG 4000
COLUMN file_name      FORMAT A36
COLUMN model_name     FORMAT A14
COLUMN status         FORMAT A8
COLUMN error_message  FORMAT A60
COLUMN extracted_json FORMAT A100
COLUMN action         FORMAT A20
COLUMN details        FORMAT A90

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Query 1 : Extractions
   Purpose : One row per read. STATUS should be SUCCESS, with
             the seconds it took.
   ------------------------------------------------------------ */
SELECT e.extraction_id,
       d.file_name,
       e.model_name,
       e.status,
       ROUND(e.elapsed_ms / 1000) AS seconds,
       e.error_message
FROM   dla_extractions e,
       dla_documents   d
WHERE  d.document_id = e.document_id
ORDER  BY e.extraction_id;

/* ------------------------------------------------------------
   Query 2 : What the model returned for the latest extraction
   Purpose : The JSON the model read from the invoice.
   ------------------------------------------------------------ */
SELECT e.extraction_id,
       e.extracted_json
FROM   dla_extractions e
WHERE  e.extraction_id = (SELECT MAX(x.extraction_id)
                          FROM   dla_extractions x);

/* ------------------------------------------------------------
   Query 3 : Last 10 audit log entries
   Purpose : The trail of what happened.
   ------------------------------------------------------------ */
SELECT a.audit_id,
       a.action,
       a.details
FROM   dla_audit_log a
WHERE  a.audit_id > (SELECT MAX(x.audit_id) - 10
                     FROM   dla_audit_log x)
ORDER  BY a.audit_id;
