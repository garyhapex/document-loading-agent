/* ============================================================
   Script      : DLA_19_VENDOR_WHO_COLUMNS.sql
   Project     : Document Loading Agent (DLA)
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - adds two columns and one trigger to
                 DLA_VENDORS, and corrects one row.
   Purpose     : Standard "who" columns on the vendor list.
                 CREATED_BY / CREATED_ON and the new
                 LAST_UPDATED_BY / LAST_UPDATED_ON are filled by a
                 trigger with the person signed in to the APEX
                 application (APP_USER). Outside APEX (SQL
                 Developer, scripts) the database user is used.
                 Before this, a vendor added from the app showed
                 ORDS_PLSQL_GATEWAY, the web server's database
                 account.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Re-runnable : yes (column adds are skipped if already there)
   Author      : Claude for Gary D. Hall
   Date        : 11/21/2026
   ============================================================ */

SET DEFINE OFF
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
COLUMN vendor_name     FORMAT A40
COLUMN created_by      FORMAT A20
COLUMN last_updated_by FORMAT A20

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Add LAST_UPDATED_BY and LAST_UPDATED_ON, only if
             they are not there yet
   ------------------------------------------------------------ */
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_count
    FROM   all_tab_columns c
    WHERE  c.owner       = 'WKSP_WKSPPRDWORKSPACE'
    AND    c.table_name  = 'DLA_VENDORS'
    AND    c.column_name = 'LAST_UPDATED_BY';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE wksp_wkspprdworkspace.dla_vendors ADD (last_updated_by VARCHAR2(255), last_updated_on DATE)';
        DBMS_OUTPUT.PUT_LINE('Added LAST_UPDATED_BY and LAST_UPDATED_ON.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('LAST_UPDATED_BY and LAST_UPDATED_ON are already there.');
    END IF;
END;
/

/* ------------------------------------------------------------
   Step 2  : Fill the new columns for the rows that exist
   ------------------------------------------------------------ */
UPDATE dla_vendors v
SET    v.last_updated_by = v.created_by,
       v.last_updated_on = v.created_on
WHERE  v.last_updated_by IS NULL;

/* ------------------------------------------------------------
   Step 3  : Correct the row added from the app before the
             trigger existed (Gary added Tallulah on 11/21)
   ------------------------------------------------------------ */
UPDATE dla_vendors v
SET    v.created_by      = 'GHALL',
       v.last_updated_by = 'GHALL'
WHERE  v.created_by = 'ORDS_PLSQL_GATEWAY';

COMMIT;

/* ------------------------------------------------------------
   Step 4  : Trigger that fills the who columns on every
             insert and update
   ------------------------------------------------------------ */
CREATE OR REPLACE TRIGGER dla_vendors_who_trg
BEFORE INSERT OR UPDATE ON dla_vendors
FOR EACH ROW
DECLARE
    l_who VARCHAR2(255) := COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
BEGIN
    IF INSERTING THEN
        :NEW.created_by := l_who;
        :NEW.created_on := SYSDATE;
    END IF;
    :NEW.last_updated_by := l_who;
    :NEW.last_updated_on := SYSDATE;
END;
/

/* ------------------------------------------------------------
   Check 1 : Trigger status
   Purpose : Expect DLA_VENDORS_WHO_TRG, ENABLED, VALID.
   ------------------------------------------------------------ */
SELECT t.trigger_name,
       t.status,
       o.status AS compiled
FROM   user_triggers t,
       user_objects  o
WHERE  o.object_name = t.trigger_name
AND    o.object_type = 'TRIGGER'
AND    t.trigger_name = 'DLA_VENDORS_WHO_TRG';

/* ------------------------------------------------------------
   Check 2 : Vendor list with the who columns
   Purpose : Expect no ORDS_PLSQL_GATEWAY; Tallulah by GHALL.
   ------------------------------------------------------------ */
SELECT v.vendor_name,
       v.active_yn,
       v.created_by,
       v.created_on,
       v.last_updated_by,
       v.last_updated_on
FROM   dla_vendors v
ORDER  BY v.vendor_id;
