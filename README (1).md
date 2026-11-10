# InvoiceGuard

**AI invoice processing that catches errors before you pay them.**

InvoiceGuard is an n8n automation that reads invoices arriving by email, extracts structured data with an LLM, checks it for mistakes and duplicates, and routes each invoice by risk. Clean invoices are saved automatically, doubtful ones go to a human for approval, and suspicious ones are quarantined with an alert.

Built with n8n, Gmail, Google Gemini, and Supabase (Postgres).

![InvoiceGuard canvas](images/canvas-overview.png)

---

## What it does

| Feature | How it works |
|---|---|
| **Email ingestion** | A Gmail trigger watches a label, downloads PDF attachments, and hashes each file |
| **AI extraction** | An LLM returns strict JSON: vendor, invoice number, date, currency, line items, totals |
| **Validation** | A code step checks required fields, that line items add up to the subtotal, that subtotal + tax equals the total, and that the date is sane |
| **Self-retry** | If validation fails, a stronger model retries once with the error messages fed back into the prompt |
| **Duplicate detection** | Database lookup on vendor + invoice number, and on file hash |
| **Risk routing** | Auto-approve, human review, or quarantine (rules below) |
| **Human approval** | Review email with Approve / Disapprove buttons; the workflow waits for the answer |
| **Learning loop** | When an invoice is rejected, the reviewer can reply with a correction (`field \| wrong \| right`). Corrections are stored and injected into later extraction prompts |
| **Error workflow** | Any failing node triggers an email and a row in a `failed_queue` table |
| **Weekly report** | Every Monday an LLM writes a short spend summary from SQL totals and emails it |
| **Chat with your invoices** | A chat agent answers questions using a **read-only** SQL tool |

## Routing rules

| Route | Condition |
|---|---|
| Quarantine | Duplicate invoice (or changed bank account, planned) |
| Human review | Any other flag, such as a new vendor |
| Auto-approve | No flags |

## Architecture

Four workflows:

1. **InvoiceGuard - 1 Ingestion**: Gmail trigger, hash, file-type switch, PDF text extraction, LLM extraction, validation, retry, anomaly check, risk router, approval, save
2. **InvoiceGuard - Error Alerts**: error trigger, alert email, log to `failed_queue`
3. **InvoiceGuard - Weekly Report**: schedule, SQL totals, LLM summary, email
4. **InvoiceGuard - Ask Your Invoices**: chat trigger, AI agent, read-only Postgres tool

### Flow diagrams

> These diagrams show the original design. In this build, Gmail replaces Telegram and Slack for approvals and alerts, and the vision OCR branch for scans is on the roadmap.

![Ingestion and extraction](images/invoice_ingestion_and_extraction_flow.png)
![Validation and risk routing](images/invoice_validation_and_risk_routing.png)
![Human review and learning loop](images/invoice_human_review_and_learning_loop.png)
![Side workflows](images/invoice_side_workflows.png)

## Database

Tables: `invoices`, `invoice_items`, `vendors`, `corrections`, `failed_queue`.

Key design choices:
- `invoices` has a unique constraint on `(vendor_norm, invoice_number)`, so the database itself rejects duplicates
- Vendor names are normalised (`lower` + `trim`) into `vendor_norm`
- The chat agent connects as a separate `invoice_reader` role that has **SELECT only**, so a prompt-injected `DELETE` fails at the database

## Screenshots

![Test results](images/test-results-combined.png)

## Test results

Tested with synthetic invoices from one vendor:

| Test | Input | Expected | Result |
|---|---|---|---|
| 1 | New vendor, correct invoice | Human review, then saved | Pass |
| 2 | Same invoice again | Quarantine + alert email (`duplicate`) | Pass |
| 3 | Printed total does not match line items | Validation fails, retry fails, failed alert | Pass |
| 4 | New invoice from a known vendor | Auto-approve and save | Pass |

## Setup

1. Create a Supabase project and run the schema SQL (tables above).
2. Create the read-only role and policies:
   ```sql
   create role invoice_reader login password '<choose-a-strong-password>';
   grant usage on schema public to invoice_reader;
   grant select on invoices, invoice_items, vendors to invoice_reader;
   create policy "reader can read invoices" on invoices for select to invoice_reader using (true);
   create policy "reader can read invoice_items" on invoice_items for select to invoice_reader using (true);
   create policy "reader can read vendors" on vendors for select to invoice_reader using (true);
   ```
3. In n8n, import the four workflow JSON files from `workflows/`.
4. Create credentials: Gmail OAuth2, Google Gemini, Postgres (main user), Postgres (read-only user).
5. Create a Gmail label named `invoices` and set the Gmail trigger to watch it.
6. In the Ingestion workflow settings, set **Error Workflow** to `InvoiceGuard - Error Alerts`.
7. Publish the workflows.

## Security notes

- No credentials are stored in this repository
- The extraction prompt tells the model that document text is data, never instructions
- The chat agent uses a read-only database role, so the SELECT-only rule is enforced by the database, not only by the prompt
- Approval uses n8n's built-in wait-for-response, so no public webhook has to be built by hand

## Known limits and roadmap

- Supports text PDFs. Scanned documents and phone photos need a vision/OCR branch (planned)
- No bank-account-change check yet (the schema has the field; extraction does not read it)
- No price-jump detection yet (needs saved line items)
- Per-field confidence scores are not used for routing yet
- Weekly report adds amounts as plain numbers and does not convert currencies
- Telegram or Slack approval cards (planned; Gmail is used now)

## Author

Huzaifa Ahmad, Computer Science graduate, University of Central Punjab (UCP), Lahore.
