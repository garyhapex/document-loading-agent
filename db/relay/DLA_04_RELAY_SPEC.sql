/* ============================================================
   Script      : DLA_04_RELAY_SPEC.sql
   Project     : Document Loading Agent (DLA) - Phase 2
   Environment : DEV by hand (SQL Developer); PRD by the pipeline
   Changes     : YES - creates or replaces the SPEC of package
                 DLA_RELAY_PKG. Changes no data.
   Purpose     : DLA_PKG and DLA_RELAY_PKG call each other, so both
                 specs are installed before either body. Order:
                   DLA_02_PACKAGE_SPEC.sql
                   DLA_04_RELAY_SPEC.sql      (this file)
                   DLA_02_PACKAGE_BODY.sql
                   DLA_04_RELAY_DATABASE.sql  (settings, body, ORDS)
                 Split out of DLA_04_RELAY_DATABASE.sql on
                 11/24/2026 so the pipeline can install a brand-new
                 database without a compile error.
   Schema      : WKSP_WKSPPRDWORKSPACE
   Run as      : WKSP_WKSPPRDWORKSPACE, SQL Developer, F5 (Run Script)
   Run after   : DLA_02_PACKAGE_SPEC.sql
   Re-runnable : yes (CREATE OR REPLACE)
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Package spec : DLA_RELAY_PKG
   Purpose      : Logic behind the two relay endpoints, plus the
                  routine that puts an invoice in the queue.
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE dla_relay_pkg AUTHID DEFINER AS

    /* Puts one document in the queue for the local model.
       Returns the new EXTRACTION_ID. Does not commit.
       P_PURPOSE (11/21/2026): LOAD = stage and decide when the
       answer comes back (the normal path); COMPARE = keep the
       answer for the compare page only. */
    FUNCTION queue_extraction (
        p_document_id  IN NUMBER,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER;

    /* Relay asks for work. Hands out one PENDING extraction at
       a time and marks it RUNNING. Called by GET work. */
    PROCEDURE get_work (
        p_token        IN  VARCHAR2,
        p_result_json  OUT CLOB,
        p_http_status  OUT NUMBER
    );

    /* Relay posts the model's answer for one extraction.
       Called by POST work/:extraction_id. */
    PROCEDURE receive_result (
        p_extraction_id   IN  NUMBER,
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    );

    /* The relay sends in a file it found in the watched folder.
       Stores it in DLA_DOCUMENTS and queues it for the local
       model, the same as an upload on page 2.
       Called by POST documents. */
    PROCEDURE receive_document (
        p_token           IN  VARCHAR2,
        p_body            IN  CLOB,
        p_document_id     OUT NUMBER,
        p_result_status   OUT VARCHAR2,
        p_result_message  OUT VARCHAR2,
        p_http_status     OUT NUMBER
    );

END dla_relay_pkg;
/

SHOW ERRORS PACKAGE dla_relay_pkg

