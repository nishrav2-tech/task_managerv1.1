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
-- properties (deals under evaluation / contract / closed)
-- ---------------------------------------------------------
create table if not exists properties (
  id           uuid primary key default gen_random_uuid(),
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

-- ---------------------------------------------------------
-- tasks (assigned to multiple users, optionally linked to
-- a property)
-- ---------------------------------------------------------
create table if not exists tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  linked_id    uuid,
  linked_type  text check (linked_type in ('property') or linked_type is null),
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

-- ---------------------------------------------------------
-- kpi_metrics (one row per metric — each metric has its own
-- manually entered 7-day and 30-day totals, each independently
-- editable)
-- ---------------------------------------------------------
create table if not exists kpi_metrics (
  id                   uuid primary key default gen_random_uuid(),
  metric_key           text not null unique,
  trailing_7_value     integer not null default 0,
  trailing_30_value    integer not null default 0,
  created_at           timestamptz not null default now()
);
create index if not exists idx_kpi_metrics_metric_key on kpi_metrics(metric_key);

-- ---------------------------------------------------------
-- kpi_meta (single row — tracks the ONE "last updated" stamp
-- shown for the whole KPI section, refreshed whenever any
-- metric value is edited)
-- ---------------------------------------------------------
create table if not exists kpi_meta (
  id           uuid primary key default gen_random_uuid(),
  updated_at   timestamptz not null default now()
);

-- If you previously ran an older version of this schema with a
-- daily-log-based "kpi_logs" table, or per-field update-date columns
-- on kpi_metrics, they're no longer used by the app and can be
-- dropped once you've confirmed the new KPI section works:
-- drop table if exists kpi_logs;
-- alter table kpi_metrics drop column if exists trailing_7_updated_at;
-- alter table kpi_metrics drop column if exists trailing_30_updated_at;

-- ---------------------------------------------------------
-- call_logs (Activity Log tab — one row per calendar day,
-- aggregate team call metrics for that day)
-- ---------------------------------------------------------
create table if not exists call_logs (
  id                    uuid primary key default gen_random_uuid(),
  log_date              date not null unique,
  calls_made            integer not null default 0,
  conversations_held    integer not null default 0,
  offers_made           integer not null default 0,
  offers_accepted       integer not null default 0,
  not_interested        integer not null default 0,
  notes                 text,
  created_at            timestamptz not null default now()
);
create index if not exists idx_call_logs_log_date on call_logs(log_date);

-- ---------------------------------------------------------
-- campaign_logs (Activity Log tab — any number of campaign
-- touches per day, e.g. mail drops, PPC pushes, SMS blasts)
-- ---------------------------------------------------------
create table if not exists campaign_logs (
  id                uuid primary key default gen_random_uuid(),
  log_date          date not null,
  campaign_name     text not null,
  channel           text,
  counties_hit      text,
  leads_generated   integer,
  notes             text,
  created_at        timestamptz not null default now()
);
create index if not exists idx_campaign_logs_log_date on campaign_logs(log_date);

-- =========================================================
-- Migrating an existing install that still has the old
-- standalone "leads" table / properties.lead_id column?
-- The Leads feature has been removed from the app — run this
-- once against an existing database to drop it cleanly:
--
--   alter table properties drop column if exists lead_id;
--   drop table if exists leads cascade;
--
-- =========================================================

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
alter table properties enable row level security;
alter table tasks      enable row level security;
alter table projects   enable row level security;
alter table kpi_metrics enable row level security;
alter table kpi_meta   enable row level security;
alter table call_logs     enable row level security;
alter table campaign_logs enable row level security;

-- Drop existing permissive policies if re-running
drop policy if exists "anon full access users"      on users;
drop policy if exists "anon full access properties" on properties;
drop policy if exists "anon full access tasks"      on tasks;
drop policy if exists "anon full access projects"   on projects;
drop policy if exists "anon full access kpi_metrics" on kpi_metrics;
drop policy if exists "anon full access kpi_meta"    on kpi_meta;
drop policy if exists "anon full access call_logs"     on call_logs;
drop policy if exists "anon full access campaign_logs" on campaign_logs;

create policy "anon full access users"      on users      for all to anon using (true) with check (true);
create policy "anon full access properties" on properties for all to anon using (true) with check (true);
create policy "anon full access tasks"      on tasks      for all to anon using (true) with check (true);
create policy "anon full access projects"   on projects   for all to anon using (true) with check (true);
create policy "anon full access kpi_metrics" on kpi_metrics for all to anon using (true) with check (true);
create policy "anon full access kpi_meta"    on kpi_meta    for all to anon using (true) with check (true);
create policy "anon full access call_logs"     on call_logs     for all to anon using (true) with check (true);
create policy "anon full access campaign_logs" on campaign_logs for all to anon using (true) with check (true);

-- =========================================================
-- Done. Now:
--   1. Copy config.example.js -> config.js
--   2. Fill in your project URL and anon key
--   3. Open index.html — the "Local" badge should turn green ("Supabase")
-- =========================================================
