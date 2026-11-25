# Document Loading Agent — 3-minute demo script

Written by Claude for Gary D. Hall, 11/21/2026. Application 300 on DEV (DEV_WORKSPACE). Run it once the day before, so the model is loaded and nothing surprises you.

## Before you start (5 minutes, once)

| Step | Where | Do this | Expect |
|---|---|---|---|
| 1 | SQL Developer, DEV WKSP_WKSPPRDWORKSPACE | Run `db\utilities\DLA_15_RESET_DEMO_DATA.sql` | All counts 0, 9 vendors kept |
| 2 | SQL Developer, DEV WKSP_WKSPPRDWORKSPACE | Check `db\data\DLA_16_WATCH_MODEL.sql` says `'OLLAMA'` on the CHANGE HERE line, run it | `WATCH_MODEL = OLLAMA` |
| 3 | PowerShell | `cd C:\Users\garyh\GitHub\document-loading-agent` then `node relay\dla-relay.js` | Banner shows `Watch : C:\DLA\inbox`. Leave it open |
| 4 | File Explorer | Copy `samples\invoices-gas\GAS_01_clean_magnolia_pipe.pdf` into `C:\DLA\inbox` and wait 60 seconds | Warms the model up (first read is slow). Then run step 1 again so the dashboard starts at zero |
| 5 | Chrome | Sign in to the application, open **Home** | All badges 0 |

Keep three things on screen: the application (Home), File Explorer open at `samples\invoices-gas`, and `C:\DLA\inbox`.

## The script

**0:00 — Home (10 seconds)**
"This is an invoice-loading agent in APEX. The model reads, the database decides, and a person is only involved when a check fails. Everything on this page is zero; watch it fill."

**0:10 — Drop the invoices (20 seconds)**
In File Explorer, select all six PDFs in `samples\invoices-gas` and copy them into `C:\DLA\inbox`.
"Nobody uploads anything. A scanner, an email rule or a person saves the file in a folder, and the relay on this PC sends it to the database. From here on I don't touch the application."

**0:30 — Watch them get read (40 seconds)**
Click **Upload Invoice** in the menu, then click **Refresh** once. The six rows appear and turn from Waiting to Reading to Success by themselves, about 6 seconds each on the local model.
"Each one is read by a vision model running on this PC, no cloud. The answer comes back as JSON, lands in staging tables, and the database runs the checks: known vendor, dates, lines add up, subtotal plus tax equals total, not a duplicate."

**1:10 — Home again (20 seconds)**
Click **Home**.
"Six invoices. Two were clean, so the agent loaded them itself. Four stopped: wrong total, missing date, duplicate number, unknown vendor. Nobody looked at the two clean ones; that is the point."

**1:30 — Review one (40 seconds)**
Click **Review Invoices**, open GAS_03 (Pinecrest, total 8,535 vs 8,335).
"The invoice is on the left, what the model read on the right, and the problem the checks found. The lines add to 8,335; the invoice says 8,535." Change Total to 8335, click **Save and check again** ("No problems"), click **Approve and load**.
"Approved and loaded, with my name on it in the audit log."

**2:10 — Compare the readers (40 seconds)**
Click **Compare Models**, pick GAS_03, click **Read with both models**, wait, click **Refresh**.
"Same invoice, two readers: the local model on this PC and OCI Generative AI. Same checks, same decisions, and here is where they agree and where they don't, with the seconds. The readers are swappable; the rules are not."

**2:50 — Close (10 seconds)**
"Every piece of this is in a GitHub repository: tables, packages, the relay, the page export, and a changelog of every run. Questions?"

## If something goes wrong
- A row stays at Waiting: the relay window is closed or Ollama is not running. Start `node relay\dla-relay.js` again; the queue picks up where it left off.
- Everything stops as a duplicate: the reset in step 1 was not run. Run it; it refuses only while a read is in progress.
- Compare shows "A compare read is still running": wait and click Refresh; it will not queue twice.
