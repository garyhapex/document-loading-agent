/* ============================================================
   Script      : DLA_18_RENAME_SAMPLE_VENDOR.sql
   Project     : Document Loading Agent (DLA)
   Environment : DEV by hand (SQL Developer); PRD by the pipeline
   Changes     : YES - renames one fictional vendor in DLA_VENDORS.
   Purpose     : The sample vendor "Kennesaw Ridge Utility Locating
                 LLC" is renamed "Oconee Ridge Utility Locating LLC",
                 to match the new GAS_04 sample invoice. The rename
                 keeps the samples fully fictional. The vendor keeps
                 its VENDOR_ID, so nothing else changes.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Re-runnable : yes (does nothing once renamed)
   Author      : Claude for Gary D. Hall
   Date        : 11/21/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200
COLUMN vendor_name FORMAT A45

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Rename the vendor, only if the new name is not
             already there
   ------------------------------------------------------------ */
UPDATE dla_vendors v
SET    v.vendor_name = 'Oconee Ridge Utility Locating LLC'
WHERE  v.vendor_name = 'Kennesaw Ridge Utility Locating LLC'
AND    NOT EXISTS (SELECT 1
                   FROM   dla_vendors x
                   WHERE  x.vendor_name = 'Oconee Ridge Utility Locating LLC');

COMMIT;

/* ------------------------------------------------------------
   Check 1 : Vendor list
   Purpose : Expect 9 vendors; Oconee Ridge listed, no Kennesaw.
   ------------------------------------------------------------ */
SELECT v.vendor_id,
       v.vendor_name,
       v.active_yn
FROM   dla_vendors v
ORDER  BY v.vendor_id;
