/* ============================================================
   Script      : verify.sql
   Project     : Document Loading Agent (DLA) - CI/CD pipeline
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - run by the pipeline
   Changes     : NO - read-only check
   Purpose     : Step 5 "verify". After the Liquibase update and
                 apex_import.sql have run:
                   1. every DLA object in the schema is VALID
                   2. application 300 exists in DEV_WORKSPACE
                   3. automation "read-waiting-documents" is ACTIVE
                   4. the Liquibase ledger (DATABASECHANGELOG) holds
                      one row per changeSet in db/deploy/changelog.xml
                 Any failure raises an error, which fails the run.
                 The pipeline sets &expected_changesets (the count
                 of changeSets in changelog.xml) before calling this.
   Run as      : WKSP_WKSPPRDWORKSPACE, by SQLcl on GitHub
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
   Changed     : 11/24/2026 - check 4 added (Liquibase ledger)
   ============================================================ */

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON
SET LINESIZE 200

PROMPT Invalid DLA objects (expect no rows):
SELECT o.object_type,
       o.object_name,
       o.status
FROM   user_objects o
WHERE  o.object_name LIKE 'DLA%'
AND    o.status = 'INVALID'
ORDER  BY o.object_type, o.object_name;

PROMPT Application 300 and its automation (full row, for the log):
SET LINESIZE 300
SELECT m.*
FROM   apex_appl_automations m
WHERE  m.application_id = 300;

PROMPT Liquibase ledger (newest first):
SELECT d.id,
       d.exectype,
       d.dateexecuted
FROM   databasechangelog d
ORDER  BY d.orderexecuted DESC;

DECLARE
    l_invalid  NUMBER;
    l_apps     NUMBER;
    l_active   NUMBER;
    l_ledger   NUMBER;
    l_expected NUMBER := &expected_changesets;
BEGIN
    SELECT COUNT(*)
    INTO   l_invalid
    FROM   user_objects o
    WHERE  o.object_name LIKE 'DLA%'
    AND    o.status = 'INVALID';

    IF l_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(-20100, l_invalid || ' invalid DLA object(s) after the release');
    END IF;

    SELECT COUNT(*)
    INTO   l_apps
    FROM   apex_applications a
    WHERE  a.application_id = 300
    AND    a.workspace      = 'DEV_WORKSPACE';

    IF l_apps <> 1 THEN
        RAISE_APPLICATION_ERROR(-20101, 'Application 300 not found in DEV_WORKSPACE after the import');
    END IF;

    SELECT COUNT(*)
    INTO   l_active
    FROM   apex_appl_automations m
    WHERE  m.application_id = 300
    AND    m.static_id      = 'read-waiting-documents'
    AND    UPPER(m.polling_status) = 'ACTIVE';

    IF l_active <> 1 THEN
        RAISE_APPLICATION_ERROR(-20102, 'Automation read-waiting-documents is not ACTIVE after the import');
    END IF;

    SELECT COUNT(*)
    INTO   l_ledger
    FROM   databasechangelog d;

    IF l_ledger <> l_expected THEN
        RAISE_APPLICATION_ERROR(-20103, 'Liquibase ledger has ' || l_ledger || ' rows; changelog.xml has ' || l_expected || ' changeSets');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Verify OK: 0 invalid DLA objects, application 300 present, automation ACTIVE, ledger ' || l_ledger || ' of ' || l_expected);
END;
/
