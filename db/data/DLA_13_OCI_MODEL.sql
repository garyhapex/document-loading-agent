/* ============================================================
   Script      : DLA_13_OCI_MODEL.sql
   Project     : Document Loading Agent (DLA) - Phase 4
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - adds or updates 5 rows in DLA_SETTINGS:
                   OCI_MODEL, OCI_ENDPOINT, OCI_CREDENTIAL,
                   OCI_COMPARTMENT_OCID, OCI_GENAI_MODEL
                 Changes nothing else.
   Purpose     : Everything DLA_PKG.EXTRACT_DOCUMENT needs to
                 call OCI Generative AI (the second reader).
                 Model  : google.gemini-2.5-flash (Google Gemini
                          2.5 Flash on OCI). Chosen 11/20/2026
                          because it takes a PDF as a document
                          directly (no picture conversion), runs
                          on-demand in Chicago, and answers in
                          seconds. Checked against Oracle's
                          model pages that day.
                 Endpoint and credential: the same ones Gary's
                          label platform already uses in this
                          workspace (credentials_for_ocigenai_1,
                          OCI native signing).
                 Compartment: read from the label platform's own
                          package source in this schema
                          (PKG_IMAGINARY_SPEC_READ), so the OCID
                          is not typed by hand and does not sit
                          in this repository.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN or WKSP_WKSPPRDWORKSPACE
                 SQL Developer, F5 (Run Script)
   Run after   : DLA_02_PACKAGE.sql (the 11/20/2026 version)
   Re-runnable : yes (updates the values in place)
   Author      : Claude for Gary D. Hall
   Date        : 11/20/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : The four settings
   Purpose : MERGE so the script can be run again. The
             compartment OCID is pulled from the line after
             "c_compartment CONSTANT" in PKG_IMAGINARY_SPEC_READ;
             if that package is ever gone, the script stops with
             ORA-20013 and says what to do.
   ------------------------------------------------------------ */
DECLARE
    l_compartment  VARCHAR2(500);
    l_user         VARCHAR2(255) := NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);

    PROCEDURE upsert (p_name IN VARCHAR2, p_value IN VARCHAR2, p_desc IN VARCHAR2) IS
    BEGIN
        MERGE INTO dla_settings s
        USING (SELECT p_name AS setting_name FROM dual) x
        ON    (s.setting_name = x.setting_name)
        WHEN MATCHED THEN
            UPDATE SET s.setting_value = p_value,
                       s.description   = p_desc,
                       s.updated_by    = l_user,
                       s.updated_on    = SYSDATE
        WHEN NOT MATCHED THEN
            INSERT (setting_name, setting_value, description, updated_by, updated_on)
            VALUES (p_name, p_value, p_desc, l_user, SYSDATE);
        DBMS_OUTPUT.PUT_LINE('Set ' || p_name);
    END upsert;
BEGIN
    /* The OCID sits on the line after the constant's name, in quotes. */
    BEGIN
        /* ALL_SOURCE with the owner, not USER_SOURCE: USER_SOURCE
           shows only the connected user's own objects, so as ADMIN
           it finds nothing (that was the 11/20/2026 first-run fault). */
        SELECT REGEXP_SUBSTR(u.text, 'ocid1\.compartment\.[A-Za-z0-9._-]+')
        INTO   l_compartment
        FROM   all_source u
        WHERE  u.owner = 'WKSP_WKSPPRDWORKSPACE'
        AND    u.name  = 'PKG_IMAGINARY_SPEC_READ'
        AND    u.type  = 'PACKAGE BODY'
        AND    REGEXP_LIKE(u.text, 'ocid1\.compartment\.')
        AND    u.line  = (SELECT MIN(u2.line)
                          FROM   all_source u2
                          WHERE  u2.owner = 'WKSP_WKSPPRDWORKSPACE'
                          AND    u2.name  = 'PKG_IMAGINARY_SPEC_READ'
                          AND    u2.type  = 'PACKAGE BODY'
                          AND    REGEXP_LIKE(u2.text, 'ocid1\.compartment\.'));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_compartment := NULL;
    END;

    IF l_compartment IS NULL THEN
        RAISE_APPLICATION_ERROR(
            -20013,
            'The compartment OCID was not found in PKG_IMAGINARY_SPEC_READ. '
            || 'Set OCI_COMPARTMENT_OCID by hand with DLA_PKG.SET_SETTING.'
        );
    END IF;

    upsert('OCI_MODEL',
           'google.gemini-2.5-flash',
           'OCI Generative AI model used by EXTRACT_DOCUMENT (takes a PDF directly)');
    upsert('OCI_ENDPOINT',
           'https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/20231130/actions/chat',
           'OCI Generative AI chat endpoint, Chicago');
    upsert('OCI_CREDENTIAL',
           'credentials_for_ocigenai_1',
           'Static ID of the APEX web credential (OCI native signing) in this workspace');
    upsert('OCI_COMPARTMENT_OCID',
           l_compartment,
           'OCI compartment the model runs in (copied from the label platform)');
    /* The Phase 1 placeholder row, kept in step so nothing shows empty. */
    upsert('OCI_GENAI_MODEL',
           'google.gemini-2.5-flash',
           'Same as OCI_MODEL (Phase 1 name, kept for the Upload page)');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Compartment OCID set (' || LENGTH(l_compartment) || ' characters).');
END;
/

/* ------------------------------------------------------------
   Check 1 : The settings
   Purpose : Expect 5 rows. The OCID is shown shortened.
   ------------------------------------------------------------ */
SELECT s.setting_name,
       CASE WHEN s.setting_name = 'OCI_COMPARTMENT_OCID'
            THEN SUBSTR(s.setting_value, 1, 24) || '...'
            ELSE s.setting_value
       END AS setting_value,
       s.updated_by,
       s.updated_on
FROM   dla_settings s
WHERE  s.setting_name LIKE 'OCI_%'
ORDER  BY s.setting_name;

/* ------------------------------------------------------------
   Check 2 : The web credential exists in this workspace
   Purpose : Expect 1 row, credentials_for_ocigenai_1, type
             Oracle Cloud Infrastructure.
   ------------------------------------------------------------ */
SELECT c.workspace,
       c.name,
       c.static_id,
       c.credential_type
FROM   apex_workspace_credentials c
WHERE  c.static_id = 'credentials_for_ocigenai_1';
