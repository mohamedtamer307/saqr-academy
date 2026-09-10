-- SAQR Academy STEP 6: Admin panel foundation
-- Set the admin user's UUID in the app_metadata.role using Supabase Admin/API,
-- or replace the helper below with your own role strategy.

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs enable row level security;

-- The UI uses an Edge Function for privileged mutations.
-- Do NOT expose service_role in the browser.

create index if not exists idx_admin_audit_created_at
on public.admin_audit_logs(created_at desc);
