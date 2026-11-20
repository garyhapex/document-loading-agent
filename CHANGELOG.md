# Build Log

Newest entries at the top. Each entry records what was done, where, and the result.

## 11/19/2026 - Phase 1: Foundation

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Ran `db/utilities/DLA_00_INVENTORY.sql` | DEV, as ADMIN | Done. Workspace DEV_WORKSPACE, schema WKSP_WKSPPRDWORKSPACE. No existing DLA_ objects. Application ID 300 chosen. |
| 2 | Created project folder and structure | Local, GitHub folder | Done. |
| 3 | Published repository `document-loading-agent` (private) | GitHub, with GitHub Desktop | Done. |
| 4 | Ran `db/tables/DLA_01_CREATE_TABLES.sql` | DEV, as ADMIN | Done. 10 tables created, all VALID. DLA_SETTINGS 5 rows, DLA_VENDORS 5 rows. |
| 5 | Ran `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | Failed. Package body did not compile: PLS-00231, a private function was called inside SQL statements. |
| 6 | Fixed `db/packages/DLA_02_PACKAGE.sql` | Local | Done. The user name is now read into a variable before the SQL statements. |
| 7 | Rerun `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | NOT YET DONE. Package body DLA_PKG is INVALID on DEV until this is run. |
| 8 | Created 6 fictional sample invoices (PDF and PNG) | `samples/invoices/` | Done. |
