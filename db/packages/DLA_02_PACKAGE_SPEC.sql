/* ============================================================
   Script      : DLA_02_PACKAGE_SPEC.sql
   Project     : Document Loading Agent (DLA) - Phase 1
   Environment : DEV by hand (SQL Developer); PRD by the pipeline
   Changes     : YES - creates or replaces the SPEC of package
                 DLA_PKG. Changes no data.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Run after   : DLA_01_CREATE_TABLES.sql and
                 DLA_08_VALIDATION_COLUMNS.sql
   11/20/2026  : EXTRACT_DOCUMENT built: the OCI Generative AI
                 reader (Google Gemini 2.5 Flash on OCI, the PDF
                 sent as a document, no relay). Settings it reads
                 come from DLA_13_OCI_MODEL.sql.
                 READ_WAITING_DOCUMENTS added for the APEX
                 automation (watched folder -> OCI).
   11/21/2026  : Compare page support. EXTRACT_DOCUMENT takes
                 P_PURPOSE (LOAD or COMPARE); a COMPARE read is
                 stored and shown but never staged or loaded.
                 COMPARE_DOCUMENT added: one call reads a
                 document with OCI now and queues it for the
                 local model, both marked COMPARE.
                 Needs the PURPOSE column from
                 DLA_17_COMPARE_COLUMN.sql.
   Note        : DLA_PKG and DLA_RELAY_PKG call each other, so the
                 two specs are installed before either body:
                 DLA_02_PACKAGE_SPEC.sql, then DLA_04_RELAY_DATABASE.sql,
                 then DLA_02_PACKAGE_BODY.sql. Split on 11/24/2026
                 so the pipeline can install a brand-new database
                 without a compile error.
   Re-runnable : yes (CREATE OR REPLACE)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Package spec : DLA_PKG
   Purpose      : The core package behind the Document Loading
                  Agent. Working: LOG_AUDIT, GET_SETTING,
                  SET_SETTING, SUBMIT_DOCUMENT, PARSE_EXTRACTION,
                  VALIDATE_STAGING, PROCESS_STAGING, LOAD_INVOICE,
                  and EXTRACT_DOCUMENT (the OCI model, 11/20/2026).
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE dla_pkg AUTHID DEFINER AS

    c_model_ollama  CONSTANT VARCHAR2(30) := 'OLLAMA';
    c_model_oci     CONSTANT VARCHAR2(30) := 'OCI_GENAI';

    /* Working in Phase 1: writes one audit row in its own transaction. */
    PROCEDURE log_audit (
        p_action       IN VARCHAR2,
        p_details      IN VARCHAR2 DEFAULT NULL,
        p_document_id  IN NUMBER   DEFAULT NULL
    );

    /* Working in Phase 1: returns a value from DLA_SETTINGS. */
    FUNCTION get_setting (
        p_setting_name  IN VARCHAR2
    ) RETURN VARCHAR2;

    /* Working in Phase 1: changes a value in DLA_SETTINGS. */
    PROCEDURE set_setting (
        p_setting_name   IN VARCHAR2,
        p_setting_value  IN VARCHAR2
    );

    /* Working: called by the APEX upload page. Copies the file
       the user just uploaded from APEX's temporary upload area
       (APEX_APPLICATION_TEMP_FILES) into DLA_DOCUMENTS and sends
       it to the chosen model: OLLAMA goes in the relay queue,
       OCI_GENAI is read straight away. P_MODEL_CODE empty means
       use the ACTIVE_MODEL setting. Returns the new DOCUMENT_ID.
       Does not commit. */
    FUNCTION submit_document (
        p_temp_file_name  IN VARCHAR2,
        p_model_code      IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    /* Working (11/20/2026): the second reader. Sends the document
       straight from the database to OCI Generative AI (settings
       OCI_MODEL, OCI_ENDPOINT, OCI_CREDENTIAL, OCI_COMPARTMENT_OCID),
       stores the answer in DLA_EXTRACTIONS, then stages it and runs
       the agent's decision exactly as the relay path does. Needs an
       APEX session (the web credential), so it is called from the
       Upload page, not from ORDS. Returns the new EXTRACTION_ID.
       P_MODEL_CODE is accepted for symmetry; only OCI_GENAI is read
       here. P_PURPOSE (11/21/2026): LOAD is the normal path above;
       COMPARE stores the answer for the compare page only and
       skips staging, the decision, and the document status. */
    FUNCTION extract_document (
        p_document_id  IN NUMBER,
        p_model_code   IN VARCHAR2 DEFAULT NULL,
        p_purpose      IN VARCHAR2 DEFAULT 'LOAD'
    ) RETURN NUMBER;

    /* Working (11/21/2026): the compare page (page 4). For one
       document that is already in DLA_DOCUMENTS, reads it with
       OCI Generative AI right now and puts it in the relay queue
       for the local model, both reads marked COMPARE so neither
       one is staged or loaded. The page shows the two answers
       side by side once the relay has posted its result (about
       6 seconds on the desktop, plus up to 5 seconds of polling).
       Returns a one-line message for the page. Does not commit.
       Needs an APEX session (the OCI call). */
    FUNCTION compare_document (
        p_document_id  IN NUMBER
    ) RETURN VARCHAR2;

    /* Working (11/20/2026): called by the APEX automation
       "Read waiting documents" every minute. Finds documents that
       arrived from the watched folder while WATCH_MODEL was
       OCI_GENAI (status UPLOADED, no read yet) and sends each one
       to EXTRACT_DOCUMENT, oldest first, committing after each.
       P_MAX_DOCUMENTS caps one run. Returns how many were read. */
    FUNCTION read_waiting_documents (
        p_max_documents  IN NUMBER DEFAULT 20
    ) RETURN NUMBER;

    /* Working: reads the model's JSON for one extraction with
       JSON_TABLE and writes it to the staging tables. Returns
       the new STG_HEADER_ID. Does not commit. Running it again
       for the same extraction replaces that extraction's
       staging rows. */
    FUNCTION parse_extraction (
        p_extraction_id  IN NUMBER
    ) RETURN NUMBER;

    /* Working: runs the checks on one staged invoice and writes
       what it finds to DLA_STG_FLAGS (FLAG_SOURCE = CHECK). Safe
       to run again: it replaces its own earlier flags. Does not
       commit. */
    PROCEDURE validate_staging (
        p_stg_header_id  IN NUMBER
    );

    /* Working: THE AGENT'S DECISION. Runs the checks, then:
         no flags  -> approves the invoice itself and loads it.
                      P_INVOICE_ID returns the new invoice.
         any flag  -> leaves it for a person to review.
                      P_INVOICE_ID returns empty.
       P_FLAG_COUNT returns how many flags there are. Only works
       on a staged invoice still PENDING. Does not commit. */
    PROCEDURE process_staging (
        p_stg_header_id  IN  NUMBER,
        p_invoice_id     OUT NUMBER,
        p_flag_count     OUT NUMBER
    );

    /* Working: copies an APPROVED staged invoice into the final
       tables DLA_INVOICES and DLA_INVOICE_LINES and writes the
       audit entry. Returns the new INVOICE_ID. Does not commit. */
    FUNCTION load_invoice (
        p_stg_header_id  IN NUMBER
    ) RETURN NUMBER;

END dla_pkg;
/

SHOW ERRORS PACKAGE dla_pkg

