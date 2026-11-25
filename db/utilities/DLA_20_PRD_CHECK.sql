-- =============================================================================
-- Script      : db/utilities/DLA_20_PRD_CHECK.sql
-- Purpose     : Find out what already exists on PRD before the pipeline is
--               pointed at it. Nothing of the DLA has been installed on PRD.
-- Environment : PRD (GHAPEXAPPS_ATP_PRD)
-- Mode        : READ-ONLY. SELECT statements only. Changes nothing.
-- Run as      : the PRD workspace schema user (SQL Developer, PRD · WKSP)
-- Run with    : F5 (Run Script); copy the whole Script Output.
-- Created     : 11/24/2026
-- Changed     : 11/24/2026 - section 3 now reads APEX_APPLICATIONS (the first
--               version used a column name that does not exist)
-- =============================================================================
set pagesize 500
set linesize 200
set feedback off

prompt === 1. Which user and which database this is running as ===
prompt (so the output proves it is PRD and shows the schema name the secrets need)
select user                                as schema_user,
       sys_context('userenv','db_name')    as db_name
from   dual;

prompt === 2. APEX version on PRD ===
prompt (f300.sql was exported from APEX 26.1.6; PRD must be at least that)
select version_no
from   apex_release;

prompt === 3. Workspace this schema belongs to ===
prompt (apex_import.sql needs the workspace name; read from the applications view)
select distinct workspace
from   apex_applications;

prompt === 4. DLA objects already in this schema (expected: nothing) ===
prompt (if anything is listed, the first PRD deploy cannot treat PRD as empty)
select object_type, count(*) as how_many
from   user_objects
where  object_name like 'DLA\_%' escape '\'
group  by object_type
order  by object_type;

prompt === 5. Liquibase ledger tables already here (expected: nothing) ===
select table_name
from   user_tables
where  table_name like 'DATABASECHANGELOG%';

prompt === 6. The label platform package DLA_13 reads the OCI compartment from ===
prompt (DLA_13 looks up the compartment OCID in PKG_IMAGINARY_SPEC_READ; it must exist and be VALID)
select object_name, object_type, status
from   user_objects
where  object_name = 'PKG_IMAGINARY_SPEC_READ'
order  by object_type;

prompt === 7. ORDS: is this schema REST-enabled (the relay token needs it) ===
select *
from   user_ords_schemas;

prompt === 8. Web credentials in this workspace (looking for the OCI one) ===
select *
from   apex_workspace_credentials;

prompt === 9. Applications already in this workspace (is ID 300 free) ===
select application_id, application_name
from   apex_applications
order  by application_id;

prompt === END OF CHECK ===
