/* ============================================================
   Script      : DLA_99_DROP_ALL.sql
   Project     : Document Loading Agent (DLA)
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - DESTRUCTIVE. Drops the ORDS module
                 dla.relay, packages DLA_RELAY_PKG and DLA_PKG,
                 all 10 DLA_ tables with their data, and the
                 three Liquibase ledger tables the pipeline
                 created (DATABASECHANGELOG, DATABASECHANGELOGLOCK,
                 DATABASECHANGELOG_ACTIONS). The ledger tables
                 are dropped only if every row in the ledger is
                 a DLA changeSet (id starting dla-); if anything
                 else is in it, the script stops before dropping
                 anything. Drops nothing else.
                 The APEX application (300) is not touched;
                 delete it in App Builder if you want it gone.
   When to run : ONLY for a clean start. Otherwise never.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE  <-- NOT ADMIN.
                 The ORDS module belongs to the schema that
                 defined it, so only that schema can delete it.
                 SQL Developer, F5 (Run Script)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026 (ORDS module and relay package
                 added the same day, late)
   Changed     : 11/25/2026 - Liquibase ledger tables added.
                 Without this, a reinstall after a clean start
                 would find a ledger saying every script had
                 already run, and the pipeline would install
                 nothing.
   ============================================================ */

SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block 0 : The ledger holds only DLA changeSets
   Purpose : Read-only. Runs before anything is dropped. Stops
             with ORA-20031 if DATABASECHANGELOG has a row whose
             id does not start with dla- (another application
             deploying with Liquibase into this schema), so its
             ledger is never dropped by this script. If the
             table is not there, there is nothing to check.
   ------------------------------------------------------------ */
DECLARE
    l_other  NUMBER;
BEGIN
    EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM databasechangelog d WHERE d.id NOT LIKE ''dla-%'''
        INTO l_other;
    IF l_other > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20031,
            l_other || ' row(s) in DATABASECHANGELOG are not DLA changeSets. '
            || 'Another application uses this ledger; nothing was dropped.'
        );
    END IF;
    DBMS_OUTPUT.PUT_LINE('Checked : ledger holds only DLA changeSets');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -942 THEN
            DBMS_OUTPUT.PUT_LINE('Checked : no ledger table (DATABASECHANGELOG not there)');
        ELSE
            RAISE;
        END IF;
END;
/

/* ------------------------------------------------------------
   Block 1 : Delete the ORDS module dla.relay
   Purpose : Removes the three relay endpoints. Stops with
             ORA-20030 if not run as the schema, because ORDS
             would otherwise look for the module under ADMIN
             and quietly find nothing.
   ------------------------------------------------------------ */
BEGIN
    IF USER <> 'WKSP_WKSPPRDWORKSPACE' THEN
        RAISE_APPLICATION_ERROR(
            -20030,
            'Run this file on the WKSP_WKSPPRDWORKSPACE connection, not ' || USER || '.'
        );
    END IF;

    ORDS.DELETE_MODULE(p_module_name => 'dla.relay');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Done    : ORDS module dla.relay deleted (or was not there)');
END;
/

/* ------------------------------------------------------------
   Block 2 : Drop each DLA_ object by exact name
   Purpose : Uses a fixed list of names, not a wildcard, so it
             can never reach another application's objects.
             An object that does not exist is skipped and
             reported; any other error stops the script.
             DLA_RELAY_PKG goes first because it calls DLA_PKG.
   ------------------------------------------------------------ */
DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(200);
    l_statements t_names := t_names(
        'DROP PACKAGE dla_relay_pkg',
        'DROP PACKAGE dla_pkg',
        'DROP TABLE dla_invoice_lines CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_invoices CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_stg_flags CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_stg_lines CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_stg_headers CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_extractions CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_documents CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_vendors CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_settings CASCADE CONSTRAINTS PURGE',
        'DROP TABLE dla_audit_log CASCADE CONSTRAINTS PURGE',
        'DROP TABLE databasechangelog_actions CASCADE CONSTRAINTS PURGE',
        'DROP TABLE databasechangelog CASCADE CONSTRAINTS PURGE',
        'DROP TABLE databasechangeloglock CASCADE CONSTRAINTS PURGE'
    );
BEGIN
    FOR i IN 1 .. l_statements.COUNT LOOP
        BEGIN
            EXECUTE IMMEDIATE l_statements(i);
            DBMS_OUTPUT.PUT_LINE('Done    : ' || l_statements(i));
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE IN (-942, -4043) THEN
                    DBMS_OUTPUT.PUT_LINE('Skipped : ' || l_statements(i) || ' (does not exist)');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('FAILED  : ' || l_statements(i) || ' - ' || SQLERRM);
                    RAISE;
                END IF;
        END;
    END LOOP;
END;
/

/* ------------------------------------------------------------
   Check 1 : Anything left
   Purpose : Expect "no rows selected" (DLA objects and the
             three Liquibase ledger tables).
   ------------------------------------------------------------ */
SELECT owner,
       object_type,
       object_name
FROM   all_objects
WHERE  owner = 'WKSP_WKSPPRDWORKSPACE'
AND   (object_name LIKE 'DLA\_%' ESCAPE '\'
       OR object_name LIKE 'DATABASECHANGELOG%')
ORDER  BY object_type,
          object_name;

/* ------------------------------------------------------------
   Check 2 : ORDS module gone
   Purpose : Expect "no rows selected".
   ------------------------------------------------------------ */
SELECT m.name,
       m.status
FROM   user_ords_modules m
WHERE  m.name = 'dla.relay';
