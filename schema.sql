-- =========================================================
-- Utopian CRM — Supabase schema
-- Run this once in your Supabase SQL Editor.
-- Then copy config.example.js -> config.js with your URL + anon key.
-- =========================================================

-- Enable UUID generation (usually already on in Supabase)
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------
-- users (team members using this CRM)
-- ---------------------------------------------------------
create table if not exists users (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  role        text,
  color_idx   int  not null default 0,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------
-- leads (sellers, buyers, other contacts)
-- ---------------------------------------------------------
create table if not exists leads (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  phone        text,
  email        text,
  source       text,
  status       text not null default 'new',
  county       text,
  state        text default 'TX',
  notes        text,
  assigned_to  uuid references users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_leads_status      on leads(status);
create index if not exists idx_leads_assigned_to on leads(assigned_to);

-- ---------------------------------------------------------
-- properties (deals under evaluation / contract / closed)
-- ---------------------------------------------------------
create table if not exists properties (
  id           uuid primary key default gen_random_uuid(),
  lead_id      uuid references leads(id) on delete set null,
  address      text not null,
  county       text,
  state        text default 'TX',
  acres        numeric,
  ask_price    numeric,
  offer_price  numeric,
  arv_price    numeric,
  status       text not null default 'new',
  notes        text,
  assigned_to  uuid references users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_properties_status      on properties(status);
create index if not exists idx_properties_assigned_to on properties(assigned_to);
create index if not exists idx_properties_lead_id     on properties(lead_id);

-- ---------------------------------------------------------
-- tasks (assigned to multiple users, optionally linked to
-- a lead or a property)
-- ---------------------------------------------------------
create table if not exists tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  linked_id    uuid,
  linked_type  text check (linked_type in ('lead','property') or linked_type is null),
  due_date     date,
  priority     text not null default 'medium' check (priority in ('high','medium','low')),
  status       text not null default 'todo'   check (status   in ('todo','in-progress','done','blocked')),
  notes        text,
  assignees    uuid[] not null default '{}',
  created_at   timestamptz not null default now()
);
create index if not exists idx_tasks_status    on tasks(status);
create index if not exists idx_tasks_due_date  on tasks(due_date);
create index if not exists idx_tasks_assignees on tasks using gin (assignees);

-- ---------------------------------------------------------
-- projects (business improvements: marketing, SOPs, tools, etc.)
-- ---------------------------------------------------------
create table if not exists projects (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  category     text not null default 'Other',
  status       text not null default 'ideas' check (status in ('ideas','planned','in-progress','done')),
  priority     text not null default 'medium' check (priority in ('high','medium','low')),
  description  text,
  due_date     date,
  assignees    uuid[] not null default '{}',
  created_at   timestamptz not null default now()
);
create index if not exists idx_projects_status   on projects(status);
create index if not exists idx_projects_category on projects(category);

-- =========================================================
-- Row Level Security
-- =========================================================
-- The app uses Supabase's anon key with permissive policies
-- (the "pick your name" login model — no per-user auth).
--
-- This is fine for a small internal team using a private URL,
-- but ANYONE with the URL + anon key can read/write your data.
--
-- If you need real user auth later:
--   1. Enable Supabase Auth in the dashboard
--   2. Replace the policies below with auth.uid()-based rules
--   3. Add a login screen to the app
-- =========================================================

alter table users      enable row level security;
alter table leads      enable row level security;
alter table properties enable row level security;
alter table tasks      enable row level security;
alter table projects   enable row level security;

-- Drop existing permissive policies if re-running
drop policy if exists "anon full access users"      on users;
drop policy if exists "anon full access leads"      on leads;
drop policy if exists "anon full access properties" on properties;
drop policy if exists "anon full access tasks"      on tasks;
drop policy if exists "anon full access projects"   on projects;

create policy "anon full access users"      on users      for all to anon using (true) with check (true);
create policy "anon full access leads"      on leads      for all to anon using (true) with check (true);
create policy "anon full access properties" on properties for all to anon using (true) with check (true);
create policy "anon full access tasks"      on tasks      for all to anon using (true) with check (true);
create policy "anon full access projects"   on projects   for all to anon using (true) with check (true);

-- =========================================================
-- Done. Now:
--   1. Copy config.example.js -> config.js
--   2. Fill in your project URL and anon key
--   3. Open index.html — the "Local" badge should turn green ("Supabase")
-- =========================================================
