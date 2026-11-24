/* ============================================================
   Script      : release.sql
   Project     : Document Loading Agent (DLA) - CI/CD pipeline
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - run by the pipeline
   Changes     : YES - runs the scripts listed below, in order
   Purpose     : The release list. The GitHub pipeline
                 (.github/workflows/deploy.yml) runs this file with
                 SQLcl after a person has approved the deploy.
                 Each release edits the list below to name exactly
                 the scripts that release runs. Only re-runnable
                 scripts belong here (CREATE OR REPLACE, scripts
                 that check before they change). Never DLA_01 or
                 DLA_99.
   Run as      : WKSP_WKSPPRDWORKSPACE, by SQLcl on GitHub
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/24/2026
   ============================================================ */

-- Stop at the first error and report failure to the pipeline.
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
WHENEVER OSERROR  EXIT FAILURE ROLLBACK

SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT ============================================================
PROMPT Release 2026-11-24 : recompile DLA_PKG
PROMPT ============================================================

@db/packages/DLA_02_PACKAGE.sql

PROMPT Release list finished.
