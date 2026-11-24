/* ============================================================
   Script      : verify.sql
   Project     : Document Loading Agent (DLA) - CI/CD pipeline
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - run by the pipeline
   Changes     : NO - read-only check
   Purpose     : Step 5 "verify". After release.sql has run, every
                 DLA object in the schema must be VALID. If any is
                 INVALID the script raises an error, which fails
                 the pipeline run.
   Run as      : WKSP_WKSPPRDWORKSPACE, by SQLcl on GitHub
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
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

DECLARE
    l_invalid NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_invalid
    FROM   user_objects o
    WHERE  o.object_name LIKE 'DLA%'
    AND    o.status = 'INVALID';

    IF l_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(-20100, l_invalid || ' invalid DLA object(s) after the release');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Verify OK: 0 invalid DLA objects');
END;
/
