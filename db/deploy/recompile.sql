/* ============================================================
   Script      : recompile.sql
   Project     : Document Loading Agent (DLA) - CI/CD pipeline
   Environment : PRD (GHAPEXAPPS_ATP_PRD) - run by the pipeline
   Changes     : YES - recompiles DLA objects that are INVALID.
                 Creates, drops and changes nothing else.
   Purpose     : Step 5 of the pipeline, between the Liquibase
                 update and the application import. A table
                 change (DLA_19 adds columns to DLA_VENDORS, for
                 example) marks the packages that use that table
                 INVALID. Oracle would recompile them on first
                 use; this does it now, so verify.sql sees the
                 true state and a real compile error fails the run.
                 Only objects whose name starts with DLA are
                 touched: never the label platform's.
   Run as      : WKSP_WKSPPRDWORKSPACE, by SQLcl on GitHub
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
   ============================================================ */

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON

DECLARE
    l_done NUMBER := 0;
BEGIN
    FOR r IN (SELECT o.object_type, o.object_name
              FROM   user_objects o
              WHERE  o.object_name LIKE 'DLA%'
              AND    o.status = 'INVALID'
              AND    o.object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW', 'PROCEDURE', 'FUNCTION')
              ORDER  BY CASE o.object_type WHEN 'PACKAGE' THEN 1 WHEN 'PACKAGE BODY' THEN 2 ELSE 3 END,
                        o.object_name)
    LOOP
        BEGIN
            IF r.object_type = 'PACKAGE BODY' THEN
                EXECUTE IMMEDIATE 'ALTER PACKAGE ' || r.object_name || ' COMPILE BODY';
            ELSE
                EXECUTE IMMEDIATE 'ALTER ' || r.object_type || ' ' || r.object_name || ' COMPILE';
            END IF;
            DBMS_OUTPUT.PUT_LINE('Recompiled ' || r.object_type || ' ' || r.object_name);
            l_done := l_done + 1;
        EXCEPTION
            WHEN OTHERS THEN
                /* A compile that reports errors still leaves the object; verify.sql catches it. */
                DBMS_OUTPUT.PUT_LINE('Could not recompile ' || r.object_type || ' ' || r.object_name || ': ' || SQLERRM);
        END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Recompile finished: ' || l_done || ' object(s) recompiled.');
END;
/
