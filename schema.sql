-- InvoiceGuard database schema (Supabase / Postgres)

create table vendors (
  id serial primary key,
  vendor_norm text unique not null,
  vendor_name text,
  bank_account text,
  created_at timestamptz default now()
);

create table invoices (
  id serial primary key,
  vendor_norm text not null,
  invoice_number text not null,
  invoice_date date,
  currency text,
  subtotal numeric,
  tax_amount numeric,
  total numeric,
  file_hash text,
  status text default 'approved',
  flags text[],
  raw_json jsonb,
  created_at timestamptz default now(),
  unique (vendor_norm, invoice_number)
);

create table invoice_items (
  id serial primary key,
  invoice_id int references invoices(id),
  vendor_norm text,
  description text,
  description_norm text,
  quantity numeric,
  unit_price numeric,
  line_total numeric,
  created_at timestamptz default now()
);

create table corrections (
  id serial primary key,
  vendor_norm text,
  field text,
  wrong_value text,
  right_value text,
  created_at timestamptz default now()
);

create table failed_queue (
  id serial primary key,
  source text,
  error text,
  payload jsonb,
  created_at timestamptz default now()
);

-- Read-only role used by the "Ask Your Invoices" chat agent.
-- Replace the password placeholder before running. Never commit a real password.
create role invoice_reader login password '<choose-a-strong-password>';
grant usage on schema public to invoice_reader;
grant select on invoices, invoice_items, vendors to invoice_reader;

-- Supabase turns on row security, so the reader needs explicit read policies.
create policy "reader can read invoices" on invoices
  for select to invoice_reader using (true);
create policy "reader can read invoice_items" on invoice_items
  for select to invoice_reader using (true);
create policy "reader can read vendors" on vendors
  for select to invoice_reader using (true);
