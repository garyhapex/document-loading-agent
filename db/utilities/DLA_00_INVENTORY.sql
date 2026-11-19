/* ============================================================
   Script      : DLA_00_INVENTORY.sql
   Project     : Document Loading Agent (DLA) - Phase 1
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : NONE - read-only, SELECT statements only
   Purpose     : Inventory of the DEV database before anything
                 is created.
   Run as      : ADMIN, SQL Developer, F5 (Run Script)
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET LINESIZE 200
SET PAGESIZE 200

/* ------------------------------------------------------------
   Query 1 : Database and APEX versions
   Purpose : Confirm what DEV is running today
   ------------------------------------------------------------ */
SELECT 'DATABASE' AS component,
       version_full AS version
FROM   v$instance
UNION ALL
SELECT 'APEX' AS component,
       version_no AS version
FROM   apex_release;

/* ------------------------------------------------------------
   Query 2 : Workspaces and their schemas
   Purpose : List the workspaces and the schema(s) each one uses
   ------------------------------------------------------------ */
SELECT workspace_name,
       schema
FROM   apex_workspace_schemas
ORDER  BY workspace_name,
          schema;

/* ------------------------------------------------------------
   Query 3 : Applications in every workspace
   Purpose : See existing app IDs so the new app gets a free one
   ------------------------------------------------------------ */
SELECT workspace,
       application_id,
       application_name,
       owner,
       pages,
       last_updated_on
FROM   apex_applications
WHERE  workspace NOT IN ('INTERNAL', 'COM.ORACLE.APEX.REPOSITORY', 'COM.ORACLE.CUST.REPOSITORY')
ORDER  BY workspace,
          application_id;

/* ------------------------------------------------------------
   Query 4 : Any existing objects already named DLA_
   Purpose : Confirm the DLA_ prefix is unused (expect no rows)
   ------------------------------------------------------------ */
SELECT owner,
       object_type,
       object_name
FROM   all_objects
WHERE  object_name LIKE 'DLA\_%' ESCAPE '\'
ORDER  BY owner,
          object_type,
          object_name;

/* ------------------------------------------------------------
   Query 5 : Existing VPD policies
   Purpose : Know which existing objects carry policies, so the
             DLA_ objects stay clear of them
   ------------------------------------------------------------ */
SELECT object_owner,
       object_name,
       policy_name,
       enable
FROM   all_policies
ORDER  BY object_owner,
          object_name,
          policy_name;
