CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','manager','csr_dispatch','technician','marketing','accounting')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  service_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id),
  technician_id UUID REFERENCES users(id),
  status TEXT NOT NULL,
  scheduled_start TIMESTAMPTZ,
  scheduled_end TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  revenue NUMERIC(12,2) NOT NULL DEFAULT 0,
  material_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  labor_hours NUMERIC(8,2) NOT NULL DEFAULT 0,
  labor_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  allocated_overhead NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE estimates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'draft',
  approved_option TEXT,
  approved_at TIMESTAMPTZ,
  signature_reference TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE estimate_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id UUID NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('Good','Better','Best')),
  description TEXT NOT NULL,
  price NUMERIC(12,2) NOT NULL,
  cost NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE TABLE invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id),
  status TEXT NOT NULL DEFAULT 'draft',
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id),
  invoice_id UUID REFERENCES invoices(id),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL,
  reference TEXT,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE time_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id),
  technician_id UUID NOT NULL REFERENCES users(id),
  entry_type TEXT NOT NULL CHECK (entry_type IN ('travel','work','break')),
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ
);

CREATE TABLE inventory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL,
  on_hand NUMERIC(12,2) NOT NULL DEFAULT 0,
  reorder_point NUMERIC(12,2) NOT NULL DEFAULT 0,
  unit_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  location TEXT NOT NULL
);

CREATE TABLE material_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id),
  inventory_item_id UUID REFERENCES inventory_items(id),
  sku TEXT NOT NULL,
  description TEXT NOT NULL,
  quantity NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  unit_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  source TEXT NOT NULL
);

CREATE TABLE price_book_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  material_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  labor_hours NUMERIC(8,2) NOT NULL DEFAULT 0,
  overhead NUMERIC(12,2) NOT NULL DEFAULT 0,
  target_gp NUMERIC(5,2) NOT NULL DEFAULT 50 CHECK (target_gp >= 0 AND target_gp < 100),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES users(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  before_data JSONB,
  after_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX jobs_technician_idx ON jobs(technician_id);
CREATE INDEX jobs_scheduled_start_idx ON jobs(scheduled_start);
CREATE INDEX estimates_job_idx ON estimates(job_id);
CREATE INDEX invoices_job_idx ON invoices(job_id);
CREATE INDEX payments_job_idx ON payments(job_id);
CREATE INDEX time_entries_job_idx ON time_entries(job_id);
CREATE INDEX material_usage_job_idx ON material_usage(job_id);
CREATE INDEX audit_log_created_at_idx ON audit_log(created_at);
