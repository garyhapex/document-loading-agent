# Document Loading Agent

An AI document-loading agent built in Oracle APEX. A vendor invoice arrives (dropped on a page or into a watched folder), an AI model reads it, PL/SQL checks it, the database decides, and a person approves only what was stopped. Approved invoices load into invoice tables with an audit trail.

Built by Gary D. Hall.

## What it does

1. **Receive** - an invoice (PDF or image) is dropped on the Upload Invoice page, or copied into a watched folder on a PC.
2. **Read** - an AI model reads the document and returns the data as JSON.
3. **Check** - PL/SQL validates it: required fields, line amounts against the total, duplicate invoice number, known vendor, date rules.
4. **Decide** - a clean invoice is loaded by the agent with no person involved. An invoice with a problem stops for review.
5. **Review** - a person sees the document beside the fields the model read, corrects, adds a missing vendor if needed, and approves or rejects.
6. **Load** - PL/SQL writes the final invoice tables and an audit log entry. Pages update live; nothing is refreshed by hand.

## Two AI models, one application

| Model | Where it runs | Role |
|---|---|---|
| Qwen2.5-VL 7B (`qwen2.5vl:7b`) through Ollama | A PC with an NVIDIA card. A Node relay on the PC calls out to the database for work; nothing calls in. | The agent (default reader). About 6 seconds per invoice on an RTX 5060 Ti. |
| OCI Generative AI (`google.gemini-2.5-flash`) | Oracle Cloud, us-chicago-1 | The yardstick. Read directly from the database; about 6 seconds per invoice. |

The setting `WATCH_MODEL` chooses which model reads what arrives. Everything after the read is shared. The Compare Models page runs one invoice through both and shows the two reads side by side.

## Application pages (APEX application 300)

| Page | Name | Purpose |
|---|---|---|
| 1 | Home | Clickable cards: received, loaded by the agent, loaded after review, waiting, rejected, failed, seconds per model; latest documents |
| 2 | Upload Invoice | Drop zone; every document with its status, model and read time, updating live |
| 3 | Review Invoices | The stopped invoices: document on the left, fields, problems and lines on the right; Save and check again, Approve and load, Reject, Add vendor |
| 4 | Compare Models | One invoice read by both models, field by field |
| 5 | Loaded Invoices | Every loaded invoice with its lines and audit trail |
| 6 | Vendors | Vendor list, Active/Inactive, who added or changed each row |

Shared components: automation "Read waiting documents" (every minute, reads documents waiting for the OCI model); page 0 holds the status badge colours and the live-update script.

## Design limits

Uses only features available on Oracle Database 19c with APEX 24.2: JSON_TABLE, APEX file upload, APEX_WEB_SERVICE, APEX Automations, ORDS. No vector search, no Human Task.

## Environment

| Item | Value |
|---|---|
| Database | DEV: GHAPEXAPPS_ATP_DEV, where the work is done. PRD: GHAPEXAPPS_ATP_PRD, where the pipeline deploys. Both Autonomous Database, OCI us-chicago-1 |
| APEX workspace | DEV_WORKSPACE on DEV, PRD_WORKSPACE on PRD |
| Schema | WKSP_WKSPPRDWORKSPACE (same name on both) |
| ORDS path | prd_workspace |
| APEX application ID | 300 |
| Object prefix | DLA_ |
| Relay PC | Windows 11, Node.js 26 LTS, Poppler (pdftoppm), Ollama with qwen2.5vl:7b; watched folder `C:\DLA\inbox` |

## Folder structure

| Folder | Contents |
|---|---|
| `db/tables/` | Table create and alter scripts |
| `db/packages/` | `DLA_PKG`: reading, checks, decision, load, OCI reader |
| `db/data/` | Settings, vendors, model instruction |
| `db/relay/` | Database side of the relay: `DLA_RELAY_PKG`, ORDS module `dla.relay`, read-only check scripts |
| `db/utilities/` | Inventory, re-read, demo reset, start-over |
| `relay/` | `dla-relay.js`, the Node relay that runs on the PC (settings file is not committed) |
| `apex/` | `f300.sql`, the export of application 300 |
| `samples/invoices/` | Fictional sample invoices, PDF and PNG |
| `samples/invoices-gas/` | Fictional natural gas invoices: 2 clean, 4 with a planted problem |
| `samples/invoices-gas-set2/` | Second set: 4 clean, 2 with a planted problem; made by `make_gas_set2_invoices.py` |
| `docs/` | Demo script |
| `.github/workflows/` | `deploy.yml`, the CI/CD pipeline (GitHub Actions) |
| `db/deploy/` | Pipeline files: `changelog.xml` (Liquibase list of install scripts), `apex_import.sql`, `verify.sql` |

## Installing from scratch

Every script states in its header what it does and whether it changes anything. Run them in SQL Developer on DEV with F5 (Run Script), in this order (the same order as `db/deploy/changelog.xml`). Run as ADMIN unless the row says otherwise.

| Order | Script | What it does |
|---|---|---|
| 1 | `db/tables/DLA_01_CREATE_TABLES.sql` | Creates the 10 DLA_ tables and seed rows |
| 2 | `db/tables/DLA_08_VALIDATION_COLUMNS.sql` | Adds FLAG_SOURCE (PARSE or CHECK) to the flags table |
| 3 | `db/tables/DLA_17_COMPARE_COLUMN.sql` | Adds PURPOSE (LOAD or COMPARE) to the extractions table |
| 4 | `db/packages/DLA_02_PACKAGE_SPEC.sql` | Creates the spec of package DLA_PKG |
| 5 | `db/relay/DLA_04_RELAY_SPEC.sql` | Creates the spec of package DLA_RELAY_PKG. The two packages call each other, so both specs go in before either body |
| 6 | `db/packages/DLA_02_PACKAGE_BODY.sql` | Creates the body of package DLA_PKG and tests it |
| 7 | `db/relay/DLA_04_RELAY_DATABASE.sql` | The relay token, the body of DLA_RELAY_PKG and the ORDS module. **Run as WKSP_WKSPPRDWORKSPACE, not ADMIN.** |
| 8 | `db/data/DLA_03_SET_LOCAL_MODEL.sql` | Sets the local model to qwen2.5vl:7b |
| 9 | `db/data/DLA_10_GAS_VENDORS.sql` | Adds the sample vendors |
| 10 | `db/data/DLA_11_GAS_TEST_FIXES.sql` | Sets the model instruction (prompt) |
| 11 | `db/data/DLA_13_OCI_MODEL.sql` | OCI Generative AI settings. Needs the workspace web credential `credentials_for_ocigenai_1` and a compartment OCID; see the script header |
| 12 | `db/data/DLA_16_WATCH_MODEL.sql` | Chooses the model for the watched folder: OLLAMA or OCI_GENAI (one marked line) |
| 13 | `db/data/DLA_18_RENAME_SAMPLE_VENDOR.sql` | Sample vendor rename (only if DLA_10 was run before 11/21/2026) |
| 14 | `db/data/DLA_19_VENDOR_WHO_COLUMNS.sql` | Who columns and trigger on DLA_VENDORS |
| 15 | `apex/f300.sql` | Import in App Builder (Import, application 300 into the workspace). The automation comes with it. |

Then on the PC that runs the local model: install Node.js, Poppler and Ollama, pull `qwen2.5vl:7b`, create `relay/dla-relay-settings.json` (ORDS base URL, relay token, watch folder; see the header of `relay/dla-relay.js`), and start the relay:

```
cd C:\Users\garyh\GitHub\document-loading-agent
node relay\dla-relay.js
```

The relay creates the watched folder with `done` and `failed` inside it on first start.

## Deployment pipeline (CI/CD)

Every push to `main` starts `.github/workflows/deploy.yml` on GitHub:

| Step | What happens | Who |
|---|---|---|
| 1 | Build and test on DEV | Developer |
| 2 | Export application 300 into `apex/f300.sql`, commit, push | Developer |
| 3 | Check: every db script has a header block; SQLcl logs in to PRD | GitHub, automatic |
| 4 | Wait for approval on the GitHub environment `PRD` (required reviewer) | Reviewer clicks Approve |
| 5 | Deploy to PRD: Liquibase runs the install scripts in `db/deploy/changelog.xml` that are not yet in its ledger (re-runnable scripts rerun when their file changes); application 300 is imported from `apex/f300.sql`; the automation "Read waiting documents" is switched back on; `db/deploy/recompile.sql` recompiles any DLA object a table change left invalid; `db/deploy/verify.sql` checks for invalid objects, the application, the automation and the ledger | GitHub, automatic |

To release a new database script: add it to `db/`, add one `changeSet` for it at the bottom of `db/deploy/changelog.xml`, commit, push, approve.

The pipeline signs in with three repository secrets: `PRD_WALLET_BASE64`, `PRD_DB_USER`, `PRD_DB_PASSWORD`. The workspace name is set once at the top of `deploy.yml` (`APEX_WORKSPACE`) and passed to `apex_import.sql` and `verify.sql`. No secret is stored in any file. Liquibase keeps its ledger in the tables `DATABASECHANGELOG`, `DATABASECHANGELOGLOCK` and `DATABASECHANGELOG_ACTIONS` in the application schema.

## Utilities

| Script | Use |
|---|---|
| `db/utilities/DLA_00_INVENTORY.sql` | Lists what exists (read-only) |
| `db/utilities/DLA_20_PRD_CHECK.sql` | What a target database already has before the pipeline is pointed at it (read-only) |
| `db/relay/DLA_06_CHECK_EXTRACTIONS.sql`, `db/relay/DLA_09_PROCESS_STAGED.sql` | Show the latest reads and decisions (read-only) |
| `db/utilities/DLA_12_REREAD_DOCUMENT.sql` | Takes listed documents back and queues them to be read again |
| `db/utilities/DLA_14_REMOVE_OCI_ERROR_ROWS.sql` | Removes documents whose only read was an OCI error |
| `db/utilities/DLA_15_RESET_DEMO_DATA.sql` | Demo reset: empties documents, reads, staging, invoices and audit; keeps vendors and settings |
| `db/utilities/DLA_99_DROP_ALL.sql` | Removes everything. Run as WKSP_WKSPPRDWORKSPACE. Only to start over. |

## Demo

`docs/DLA_DEMO_SCRIPT.md` is the 3-minute demo. Short version: reset with DLA_15, copy the six PDFs from `samples/invoices-gas/` into the watched folder, and watch Upload Invoice fill in by itself: two load, four stop for a person.

## Status

Working end to end on DEV; the pipeline deploys to PRD. `CHANGELOG.md` records everything that was built and run, by date.

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation: tables, package, sample invoices | Complete 11/19/2026 |
| 2 | AI extraction with both models, relay, upload page | Complete 11/20/2026 |
| 3 | Checks, decision, review, approval and load | Complete 11/20/2026 |
| 4 | Watched folder, compare page, dashboard, live updates, vendors page, demo script | Complete 11/21/2026 |
| 5 | CI/CD pipeline: GitHub Actions, approval gate, Liquibase, APEX import, verify | Complete 11/24/2026 |
