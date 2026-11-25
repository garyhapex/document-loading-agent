# Document Loading Agent — 3-minute demo script

Written by Claude for Gary D. Hall, 11/21/2026. Updated 11/25/2026 for PRD: application 300 on PRD (PRD_WORKSPACE), the relay running as the Windows service "DLA Invoice Relay PRD", and pages that update by themselves. Run it once the day before, so the model is loaded and nothing surprises you.

## Before you start (5 minutes, once)

| Step | Where | Do this | Expect |
|---|---|---|---|
| 1 | SQL Developer, PRD WKSP_WKSPPRDWORKSPACE | Run `db\utilities\DLA_15_RESET_DEMO_DATA.sql` | All counts 0; vendors and settings kept |
| 2 | Chrome, application 300 on PRD, **Vendors** | If Tallulah Cathodic Protection Co. is on the list with Status Active, set its Status to Inactive and save | Tallulah Inactive, so GAS_06 stops as an unknown vendor |
| 3 | Windows, Services | Find **DLA Invoice Relay PRD** | Status Running. If not, right-click it and choose Start |
| 4 | File Explorer | Copy `samples\invoices-gas\GAS_01_clean_magnolia_pipe.pdf` into `C:\DLA\inbox` and wait 60 seconds | Warms the model up (the first read of the day is slow). Then run step 1 again so the dashboard starts at zero |
| 5 | Chrome | Sign in to the application, open **Home** | All badges 0 |

The watched folder feeds the local model: the pipeline sets `WATCH_MODEL = OLLAMA` on PRD (`db\data\DLA_16_WATCH_MODEL.sql`), so there is nothing to set by hand.

Keep three things on screen: the application (Home), File Explorer open at `samples\invoices-gas`, and `C:\DLA\inbox`.

## The script

**0:00 — Home (10 seconds)**
"This is an invoice-loading agent in APEX. The model reads, the database decides, and a person is only involved when a check fails. Everything on this page is zero; watch it fill."

**0:10 — Drop the invoices (20 seconds)**
In File Explorer, select all six PDFs in `samples\invoices-gas` and copy them into `C:\DLA\inbox`.
"Nobody uploads anything. A scanner, an email rule or a person saves the file in a folder, and the relay on this PC sends it to the database. From here on I don't touch the application."

**0:30 — Watch them get read (40 seconds)**
Click **Upload Invoice** in the menu. The six rows appear and turn from Waiting to Being read to done by themselves, about 6 seconds each on the local model. No Refresh needed.
"Each one is read by a vision model running on this PC, no cloud. The answer comes back as JSON, lands in staging tables, and the database runs the checks: known vendor, dates, lines add up, subtotal plus tax equals total, not a duplicate."

**1:10 — Home again (20 seconds)**
Click **Home**.
"Six invoices. Two were clean, so the agent loaded them itself. Four stopped: wrong total, missing date, duplicate number, unknown vendor. Nobody looked at the two clean ones; that is the point."

**1:30 — Review one (40 seconds)**
Click **Review Invoices**, open GAS_03 (Pinecrest, total 8,535 vs 8,335).
"The invoice is on the left, what the model read on the right, and the problem the checks found. The lines add to 8,335; the invoice says 8,535." Change Total to 8335, click **Save and check again** ("No problems"), click **Approve and load**.
"Approved and loaded, with my name on it in the audit log."

**2:10 — Compare the readers (40 seconds)**
Click **Compare Models**, pick GAS_03 in **Invoice**, click **Read with both models**. Both columns fill in by themselves.
"Same invoice, two readers: the local model on this PC and OCI Generative AI. Same checks, same decisions, and here is where they agree and where they don't, with the seconds. The readers are swappable; the rules are not."

**2:50 — Close (10 seconds)**
"Every piece of this is in a GitHub repository: tables, packages, the relay, the page export, a pipeline that deploys to production only from a published release, and a changelog of every run. Questions?"

## If something goes wrong
- A row stays at Waiting: the relay service is stopped or Ollama is not running. In Services, start **DLA Invoice Relay PRD**; start Ollama. The queue picks up where it left off.
- Everything stops as a duplicate: the reset in step 1 was not run. Run it; it refuses only while a read is in progress.
- GAS_06 loads instead of stopping: Tallulah is Active on the Vendors page (it was added on PRD on 11/25). Do step 2, then step 1, and start again.
- Compare shows "A compare read is still running": wait; the columns fill in when it finishes, and it will not queue twice.
