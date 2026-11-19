# Document Loading Agent

An AI document-loading agent built in Oracle APEX. A user uploads a vendor invoice, an AI model reads it, PL/SQL checks it, a person approves it, and the data loads into invoice tables with an audit trail.

Built by Gary D. Hall.

## What it does

1. **Upload** - a user uploads a vendor invoice (PDF or image) on an APEX page.
2. **Read** - an AI model reads the document and returns the data as JSON.
3. **Check** - PL/SQL validates it: required fields, line amounts against the total, duplicate invoice number, known vendor.
4. **Stage** - the data goes into staging tables with a flag on each problem field.
5. **Approve** - a person reviews the document beside the extracted fields, edits if needed, and approves or rejects.
6. **Load** - on approval, PL/SQL loads the final invoice tables and writes an audit log entry.

## Two AI models, one application

| Model | Where it runs | Purpose |
|---|---|---|
| Llama vision model through Ollama | A local PC, reached through a tunnel | The in-house option |
| OCI Generative AI | Oracle Cloud | The cloud option |

One setting chooses which model reads a document. Everything after extraction is shared. A compare page runs the same invoice through both.

## Design limits

Uses only features available on Oracle Database 19c with APEX 24.2: JSON_TABLE, APEX file upload, APEX_WEB_SERVICE, APEX Human Task. No vector search.

## Environment

| Item | Value |
|---|---|
| Database | GHAPEXAPPS_ATP_DEV (OCI, us-chicago-1) |
| APEX workspace | DEV_WORKSPACE |
| Schema | WKSP_WKSPPRDWORKSPACE |
| APEX application ID | 300 |
| Object prefix | DLA_ |

## Folder structure

| Folder | Contents |
|---|---|
| `db/tables/` | Table create scripts |
| `db/packages/` | PL/SQL packages |
| `db/utilities/` | Inventory and start-over scripts |
| `apex/` | APEX application export |
| `samples/invoices/` | Fictional sample invoices, PDF and PNG |
| `docs/` | Design notes and demo script |

## Deployment sequence

Run in SQL Developer as ADMIN on DEV, with F5 (Run Script), in this order:

| Order | Script | What it does |
|---|---|---|
| 1 | `db/tables/DLA_01_CREATE_TABLES.sql` | Creates the 10 DLA_ tables and seed rows |
| 2 | `db/packages/DLA_02_PACKAGE.sql` | Creates package DLA_PKG and tests it |

`db/utilities/DLA_99_DROP_ALL.sql` removes everything above. Use it only to start over.

## Status

See `CHANGELOG.md` for what has been built and run, by date.

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation: tables, package skeleton, sample invoices | In progress |
| 2 | AI extraction with both models | Not started |
| 3 | Validation, review, approval and load | Not started |
| 4 | Compare page, dashboard, demo script | Not started |
