/* ============================================================
   Script      : apex_import.sql
   Project     : Document Loading Agent (DLA) - CI/CD pipeline
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - run by the pipeline
   Changes     : YES - replaces APEX application 300 with the copy
                 in apex/f300.sql, then switches the automation
                 "Read waiting documents" back on.
   Purpose     : Step 5 of the pipeline, second half. The release
                 list deploys the database scripts; this script
                 deploys the application itself.
                 APEX disables every automation on import (by
                 design, so two copies never run at once), so the
                 last block enables it again.
   Run as      : WKSP_WKSPPRDWORKSPACE, by SQLcl on GitHub
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
   ============================================================ */

WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT ============================================================
PROMPT Import application 300 from apex/f300.sql
PROMPT ============================================================

/* ------------------------------------------------------------
   Block   : Where the application goes
   Purpose : Same workspace, same application id, same schema as
             the export, so every component keeps its id.
   ------------------------------------------------------------ */
BEGIN
    apex_application_install.set_workspace('DEV_WORKSPACE');
    apex_application_install.set_application_id(300);
    apex_application_install.set_schema('WKSP_WKSPPRDWORKSPACE');
END;
/

@apex/f300.sql

/* ------------------------------------------------------------
   Block   : Switch the automation back on
   Purpose : APEX disables automations on import. A short APEX
             session is needed for the API call.
   ------------------------------------------------------------ */
BEGIN
    apex_session.create_session(
        p_app_id   => 300,
        p_page_id  => 1,
        p_username => 'GHALL');

    apex_automation.enable(
        p_application_id => 300,
        p_static_id      => 'read-waiting-documents');

    apex_session.delete_session;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Automation read-waiting-documents enabled.');
END;
/

PROMPT Application import finished.
