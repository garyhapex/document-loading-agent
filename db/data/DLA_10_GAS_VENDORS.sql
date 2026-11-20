/* ============================================================
   Script      : DLA_10_GAS_VENDORS.sql
   Project     : Document Loading Agent (DLA) - Phase 3
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES - adds four fictional natural gas vendors to
                 DLA_VENDORS, each only if it is not there.
   Purpose     : The natural gas sample invoices in
                 samples/invoices-gas come from these vendors.
                 "Tallulah Cathodic Protection Co." is
                 deliberately NOT added: its invoice (GAS_06)
                 shows the unknown-vendor check.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
COLUMN vendor_name FORMAT A45

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Add the vendors that are not there yet
   ------------------------------------------------------------ */
INSERT INTO dla_vendors (vendor_name)
SELECT n.vendor_name
FROM   (SELECT 'Magnolia Pipe & Polymer Supply Co.'  AS vendor_name FROM dual
        UNION ALL
        SELECT 'Chattahoochee Meter & Regulator LLC' AS vendor_name FROM dual
        UNION ALL
        SELECT 'Pinecrest Odorant Services Inc.'     AS vendor_name FROM dual
        UNION ALL
        SELECT 'Kennesaw Ridge Utility Locating LLC' AS vendor_name FROM dual) n
WHERE  NOT EXISTS (SELECT 1
                   FROM   dla_vendors v
                   WHERE  v.vendor_name = n.vendor_name);

COMMIT;

/* ------------------------------------------------------------
   Check 1 : Vendor list
   Purpose : Expect 9 vendors: the first 5 and these 4.
   ------------------------------------------------------------ */
SELECT v.vendor_id,
       v.vendor_name,
       v.active_yn
FROM   dla_vendors v
ORDER  BY v.vendor_id;
