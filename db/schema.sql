CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','manager','csr_dispatch','technician','marketing','accounting')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE customers (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  service_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE jobs (
  id UUID PRIMARY KEY,
  customer_id UUID REFERENCES customers(id),
  technician_id UUID REFERENCES users(id),
  status TEXT NOT NULL,
  scheduled_start TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  revenue NUMERIC(12,2) NOT NULL DEFAULT 0,
  material_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  labor_hours NUMERIC(8,2) NOT NULL DEFAULT 0,
  labor_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  allocated_overhead NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
  id UUID PRIMARY KEY,
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
CREATE INDEX audit_log_created_at_idx ON audit_log(created_at);
