/* ============================================================
   Script      : DLA_99_DROP_ALL.sql
   Project     : Document Loading Agent (DLA)
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - DESTRUCTIVE. Drops package DLA_PKG and all
                 10 DLA_ tables with their data. Drops nothing
                 that does not start with DLA_.
   When to run : ONLY if DLA_01_CREATE_TABLES.sql stopped partway
                 and you need a clean start. Otherwise never.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Block   : Drop each DLA_ object by exact name
   Purpose : Uses a fixed list of names, not a wildcard, so it
             can never reach another application's objects.
             An object that does not exist is skipped and
             reported; any other error stops the script.
   ------------------------------------------------------------ */
DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(200);
    l_statements t_names := t_names(
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
        'DROP TABLE dla_audit_log CASCADE CONSTRAINTS PURGE'
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
   Purpose : Expect "no rows selected".
   ------------------------------------------------------------ */
SELECT owner,
       object_type,
       object_name
FROM   all_objects
WHERE  owner = 'WKSP_WKSPPRDWORKSPACE'
AND    object_name LIKE 'DLA\_%' ESCAPE '\'
ORDER  BY object_type,
          object_name;
