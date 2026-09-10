-- SAQR Academy STEP 12
-- Staff accounts + granular permissions + atomic payment activation
-- IMPORTANT: passwords stay in Supabase Auth. Never store plaintext passwords here.

create table if not exists public.staff_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  access_role text not null default 'course_manager' check (access_role in ('admin','course_manager')),
  can_manage_users boolean not null default false,
  can_manage_payments boolean not null default false,
  can_manage_courses boolean not null default false,
  can_manage_plans boolean not null default false,
  can_view_reports boolean not null default false,
  can_manage_settings boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.staff_access enable row level security;
drop policy if exists "staff_self_read" on public.staff_access;
drop policy if exists "staff_admin_all" on public.staff_access;

create or replace function public.has_staff_access(required_permission text default null)
returns boolean language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.staff_access s
    where s.user_id=auth.uid() and s.is_active=true
      and (
        required_permission is null
        or (required_permission='admin' and s.access_role='admin')
        or (required_permission='users' and s.can_manage_users)
        or (required_permission='payments' and s.can_manage_payments)
        or (required_permission='courses' and s.can_manage_courses)
        or (required_permission='plans' and s.can_manage_plans)
        or (required_permission='reports' and s.can_view_reports)
        or (required_permission='settings' and s.can_manage_settings)
      )
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select public.has_staff_access('admin'); $$;

create policy "staff_self_read" on public.staff_access for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "staff_admin_all" on public.staff_access for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Add missing Step 10/11 fields safely.
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.courses add column if not exists category text;
alter table public.courses add column if not exists thumbnail_url text;
alter table public.courses add column if not exists is_featured boolean not null default false;
alter table public.lessons add column if not exists duration_minutes integer not null default 0;
alter table public.lessons add column if not exists is_preview boolean not null default false;
alter table public.lessons add column if not exists video_path text;
alter table public.lessons add column if not exists progress_percent integer not null default 0;

-- Final payment fields.
create table if not exists public.payments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 plan_id uuid not null references public.plans(id), provider text not null default 'manual', provider_payment_id text unique,
 amount numeric(10,2) not null, currency text not null default 'EGP',
 status text not null default 'pending_confirmation', payment_method text, customer_reference text,
 sender_phone text, proof_path text, admin_note text, confirmed_at timestamptz, confirmed_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.payments add column if not exists payment_method text;
alter table public.payments add column if not exists customer_reference text;
alter table public.payments add column if not exists sender_phone text;
alter table public.payments add column if not exists proof_path text;
alter table public.payments add column if not exists admin_note text;
alter table public.payments add column if not exists confirmed_at timestamptz;
alter table public.payments add column if not exists confirmed_by uuid references public.profiles(id);
alter table public.payments alter column currency set default 'EGP';
alter table public.payments drop constraint if exists payments_status_check;
alter table public.payments add constraint payments_status_check check (status in ('pending_confirmation','paid','failed','refunded','initiated','voided','authorized','captured'));
alter table public.payments enable row level security;
drop policy if exists "payments_own_read" on public.payments;
drop policy if exists "payments_own_insert" on public.payments;
drop policy if exists "payments_admin_all" on public.payments;
create policy "payments_own_read" on public.payments for select to authenticated using (user_id=auth.uid() or public.has_staff_access('payments') or public.is_admin());
create policy "payments_own_insert" on public.payments for insert to authenticated with check (user_id=auth.uid());
create policy "payments_admin_all" on public.payments for all to authenticated using (public.has_staff_access('payments') or public.is_admin()) with check (public.has_staff_access('payments') or public.is_admin());

alter table public.subscriptions alter column starts_at drop not null;
alter table public.subscriptions alter column ends_at drop not null;
alter table public.subscriptions add column if not exists activated_at timestamptz;
alter table public.subscriptions add column if not exists activated_by uuid references public.profiles(id);

-- Admin/course-manager course policies.
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.plan_courses enable row level security;
drop policy if exists "courses_staff_all" on public.courses;
drop policy if exists "lessons_staff_all" on public.lessons;
drop policy if exists "plan_courses_staff_all" on public.plan_courses;
create policy "courses_staff_all" on public.courses for all to authenticated using (public.has_staff_access('courses') or public.is_admin()) with check (public.has_staff_access('courses') or public.is_admin());
create policy "lessons_staff_all" on public.lessons for all to authenticated using (public.has_staff_access('courses') or public.is_admin()) with check (public.has_staff_access('courses') or public.is_admin());
create policy "plan_courses_staff_all" on public.plan_courses for all to authenticated using (public.has_staff_access('courses') or public.is_admin()) with check (public.has_staff_access('courses') or public.is_admin());

-- Storage buckets.
insert into storage.buckets(id,name,public) values ('academy-videos','academy-videos',false) on conflict(id) do update set public=false;
insert into storage.buckets(id,name,public) values ('payment-proofs','payment-proofs',false) on conflict(id) do update set public=false;

drop policy if exists "academy_videos_staff" on storage.objects;
drop policy if exists "academy_videos_read_admin" on storage.objects;
drop policy if exists "payment_proofs_staff" on storage.objects;
create policy "academy_videos_staff" on storage.objects for all to authenticated using (bucket_id='academy-videos' and (public.has_staff_access('courses') or public.is_admin())) with check (bucket_id='academy-videos' and (public.has_staff_access('courses') or public.is_admin()));
create policy "academy_videos_read_admin" on storage.objects for select to authenticated using (bucket_id='academy-videos' and public.is_admin());
create policy "payment_proofs_staff" on storage.objects for select to authenticated using (bucket_id='payment-proofs' and (public.has_staff_access('payments') or public.is_admin()));

-- Atomic confirmation for admins or payment managers.
create or replace function public.confirm_payment(p_payment_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare p public.payments%rowtype; s public.subscriptions%rowtype; dur integer; started timestamptz:=now(); finished timestamptz;
begin
 if not public.has_staff_access('payments') and not public.is_admin() then raise exception 'ليس لديك صلاحية إدارة المدفوعات'; end if;
 select * into p from public.payments where id=p_payment_id for update;
 if not found then return jsonb_build_object('success',false,'message','عملية الدفع غير موجودة'); end if;
 if p.status='paid' then return jsonb_build_object('success',true,'message','تم تفعيل العملية مسبقًا'); end if;
 select * into s from public.subscriptions where user_id=p.user_id and plan_id=p.plan_id and status='pending' order by created_at desc limit 1 for update;
 if not found then return jsonb_build_object('success',false,'message','لا يوجد اشتراك قيد المراجعة لهذا الدفع'); end if;
 select duration_days into dur from public.plans where id=p.plan_id; finished:=started+(coalesce(dur,30)||' days')::interval;
 update public.payments set status='paid',confirmed_at=started,confirmed_by=auth.uid(),updated_at=started where id=p.id;
 update public.subscriptions set status='active',starts_at=started,ends_at=finished,activated_at=started,activated_by=auth.uid() where id=s.id;
 update public.profiles set account_status='active' where id=p.user_id;
 if to_regclass('public.admin_audit_logs') is not null then insert into public.admin_audit_logs(admin_id,action,target_type,target_id,details) values(auth.uid(),'confirm_payment','payment',p.id,jsonb_build_object('user_id',p.user_id,'plan_id',p.plan_id,'subscription_id',s.id,'amount',p.amount,'currency',p.currency)); end if;
 return jsonb_build_object('success',true,'message','تم تفعيل الاشتراك','subscription_id',s.id);
end $$;
revoke all on function public.confirm_payment(uuid) from public;
grant execute on function public.confirm_payment(uuid) to authenticated;

-- Keep old RPC name working if an older frontend calls it.
create or replace function public.admin_confirm_payment(p_payment_id uuid)
returns jsonb language sql security definer set search_path=public
as $$ select public.confirm_payment(p_payment_id); $$;
revoke all on function public.admin_confirm_payment(uuid) from public;
grant execute on function public.admin_confirm_payment(uuid) to authenticated;

create index if not exists idx_staff_access_active on public.staff_access(is_active,access_role);
create index if not exists idx_staff_permissions_user on public.staff_access(user_id);
create index if not exists idx_courses_featured on public.courses(is_featured,is_active);
create index if not exists idx_lessons_course_sort on public.lessons(course_id,sort_order);

-- ================================================================
-- إنشاء حساب موظف / مدير لأول مرة
-- 1) أنشئ الحساب من Supabase > Authentication > Users > Add user.
-- 2) بعد إنشاءه، استخدم الاستعلام التالي بعد استبدال البريد:
--
-- insert into public.staff_access
-- (user_id,access_role,can_manage_users,can_manage_payments,can_manage_courses,can_manage_plans,can_view_reports,can_manage_settings,is_active)
-- select id,'admin',true,true,true,true,true,true,true
-- from auth.users where email='YOUR-ADMIN-EMAIL@example.com'
-- on conflict (user_id) do update set
-- access_role='admin',can_manage_users=true,can_manage_payments=true,can_manage_courses=true,
-- can_manage_plans=true,can_view_reports=true,can_manage_settings=true,is_active=true,updated_at=now();
--
-- لحساب مدير الكورسات:
-- insert into public.staff_access (user_id,access_role,can_manage_courses,is_active)
-- select id,'course_manager',true,true from auth.users where email='YOUR-COURSE-EMAIL@example.com'
-- on conflict (user_id) do update set access_role='course_manager',can_manage_courses=true,is_active=true,updated_at=now();
