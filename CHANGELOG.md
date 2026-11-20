# Build Log

Newest entries at the top. Each entry records what was done, where, and the result.

## 11/19/2026 - Phase 2: AI extraction (started)

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Checked PC hardware | Local PC | 32 GB RAM, Intel Iris Xe graphics. Models run on the processor. |
| 2 | Installed Ollama | Local PC | Done. |
| 3 | Pulled `llama3.2-vision` (7.8 GB) and tested | Local PC | Failed. Error: unknown model architecture 'mllama'. Llama 3.2 Vision is not supported on Ollama 0.30.0 and later. Model removed. |
| 4 | Pulled `qwen2.5vl:7b` (6.0 GB) | Local PC | Done. |
| 5 | Tested `qwen2.5vl:7b` on `samples/invoices/DLA_01_clean_prairie_fastener.png` | Local PC | Passed. Model answered invoice number INV-10001 and total due $364.00, both correct. |
| 6 | Ran `db/data/DLA_03_SET_LOCAL_MODEL.sql` | DEV, as ADMIN | Done. OLLAMA_MODEL = qwen2.5vl:7b. |
| 7 | Design decision | - | No ngrok. The local model is reached with a Node relay that calls out to ORDS, the same pattern as the Stick-IT print relay. |
| 8 | Ran `db/relay/DLA_04_RELAY_DATABASE.sql` | DEV, as WKSP_WKSPPRDWORKSPACE | Done, clean on the first run. DLA_RELAY_PKG VALID. Test: wrong token HTTP 401, right token HTTP 200 with an empty work list. ORDS module dla.relay has GET work and POST work/:extraction_id, both with header X-DLA-Relay-Token. ORDS path prd_workspace. |
| 9 | Wrote `relay/dla-relay.js` (Node, no npm packages) | - | Written. Tested by Claude against stand-in database and model servers: picks up work, calls the model, posts the answer, refuses a PDF with a clear error, reports a wrong token. Not yet run against DEV and Ollama. |
| 10 | Ran `db/relay/DLA_05_QUEUE_SAMPLE_INVOICE.sql` | DEV | Done. Sample invoice 1 loaded and queued as extraction 1. |
| 11 | First run of `relay/dla-relay.js` 1.0.0 | Local PC | Partly worked. The relay reached ORDS, the token was accepted, it picked up extraction 1 and posted an answer back. The call to Ollama failed: connect ECONNREFUSED ::1:11434. "localhost" resolved to the IPv6 address, where Ollama does not listen. Extraction 1 stored as ERROR. |
| 12 | Fixed `relay/dla-relay.js`, now 1.0.1 | Local | Done. Ollama address changed to http://127.0.0.1:11434. |
| 13 | Second run of `relay/dla-relay.js` 1.0.1, sample invoice queued again as extraction 2 | Local PC and DEV | Passed, end to end. Relay picked up the invoice from ORDS, qwen2.5vl:7b read it in 262 seconds, the relay posted the answer, the database stored it as valid JSON with status SUCCESS. |
| 14 | Ran `db/relay/DLA_06_CHECK_EXTRACTIONS.sql` | DEV | Every field correct against the sample invoice: vendor, invoice number INV-10001, invoice date 2026-11-02, due date 2026-12-02, all 3 lines (description, quantity, unit price, amount), subtotal 364.00, tax 0.00, total 364.00. Audit log shows the queue, the failed first attempt and the success. |

## 11/19/2026 - Phase 1: Foundation

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Ran `db/utilities/DLA_00_INVENTORY.sql` | DEV, as ADMIN | Done. Workspace DEV_WORKSPACE, schema WKSP_WKSPPRDWORKSPACE. No existing DLA_ objects. Application ID 300 chosen. |
| 2 | Created project folder and structure | Local, GitHub folder | Done. |
| 3 | Published repository `document-loading-agent` (private) | GitHub, with GitHub Desktop | Done. |
| 4 | Ran `db/tables/DLA_01_CREATE_TABLES.sql` | DEV, as ADMIN | Done. 10 tables created, all VALID. DLA_SETTINGS 5 rows, DLA_VENDORS 5 rows. |
| 5 | Ran `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | Failed. Package body did not compile: PLS-00231, a private function was called inside SQL statements. |
| 6 | Fixed `db/packages/DLA_02_PACKAGE.sql` | Local | Done. The user name is now read into a variable before the SQL statements. |
| 7 | Reran `db/packages/DLA_02_PACKAGE.sql` | DEV, as ADMIN | Done. Package and package body VALID. Test returned ACTIVE_MODEL = OLLAMA and wrote audit row PHASE1_INSTALL. |
| 8 | Created 6 fictional sample invoices (PDF and PNG) | `samples/invoices/` | Done. |

**Phase 1 complete.** Next: Phase 2, AI extraction with both models.
