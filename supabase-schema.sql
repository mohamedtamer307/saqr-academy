-- ============================================
-- SAQR ACADEMY - Supabase Database - STEP 3
-- ============================================
-- شغّل هذا الملف داخل Supabase > SQL Editor

create extension if not exists "pgcrypto";

-- 1) بيانات المستخدم
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- 2) الباقات
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text,
  price numeric(10,2) not null default 0,
  duration_days integer not null default 30,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 3) الكورسات
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  description text,
  level text,
  thumbnail_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 4) ربط الباقات بالكورسات
create table if not exists public.plan_courses (
  plan_id uuid not null references public.plans(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  primary key (plan_id, course_id)
);

-- 5) دروس/فيديوهات الكورس
create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  description text,
  video_url text,
  duration_seconds integer,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 6) اشتراكات العملاء
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  status text not null default 'active'
    check (status in ('pending','active','expired','cancelled')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  payment_reference text,
  created_at timestamptz not null default now()
);

-- 7) تقدم العميل في الدروس
create table if not exists public.lesson_progress (
  user_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  watched_seconds integer not null default 0,
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

-- Trigger لإنشاء profile تلقائياً بعد التسجيل
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- تفعيل RLS
alter table public.profiles enable row level security;
alter table public.plans enable row level security;
alter table public.courses enable row level security;
alter table public.plan_courses enable row level security;
alter table public.lessons enable row level security;
alter table public.subscriptions enable row level security;
alter table public.lesson_progress enable row level security;

-- Profiles: المستخدم يرى ويعدل بياناته فقط
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
for select to authenticated using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Plans: الباقات النشطة متاحة للزوار
drop policy if exists "plans_public_read" on public.plans;
create policy "plans_public_read" on public.plans
for select to anon, authenticated using (is_active = true);

-- Courses: الكورسات النشطة متاحة كبيانات عامة، لكن فتح الفيديو سيتم التحكم فيه من خلال الاشتراك
drop policy if exists "courses_public_read" on public.courses;
create policy "courses_public_read" on public.courses
for select to anon, authenticated using (is_active = true);

-- Plan/Course mapping
drop policy if exists "plan_courses_authenticated_read" on public.plan_courses;
create policy "plan_courses_authenticated_read" on public.plan_courses
for select to authenticated using (true);

-- الدروس: المستخدم يرى الدروس فقط إذا كان لديه اشتراك نشط يسمح بالكورس
drop policy if exists "lessons_subscriber_read" on public.lessons;
create policy "lessons_subscriber_read" on public.lessons
for select to authenticated
using (
  exists (
    select 1
    from public.plan_courses pc
    join public.subscriptions s on s.plan_id = pc.plan_id
    where pc.course_id = lessons.course_id
      and s.user_id = auth.uid()
      and s.status = 'active'
      and s.ends_at > now()
  )
);

-- الاشتراك: المستخدم يرى اشتراكاته فقط
drop policy if exists "subscriptions_own_read" on public.subscriptions;
create policy "subscriptions_own_read" on public.subscriptions
for select to authenticated using (user_id = auth.uid());

-- التقدم: المستخدم يدير تقدمه فقط
drop policy if exists "progress_own_all" on public.lesson_progress;
create policy "progress_own_all" on public.lesson_progress
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- بيانات تجريبية للباقات
insert into public.plans (name, slug, description, price, duration_days)
values
('Basic', 'basic', 'الباقة الأساسية', 99, 30),
('Pro', 'pro', 'الباقة المتقدمة', 199, 30),
('Elite', 'elite', 'الباقة الاحترافية', 299, 30)
on conflict (slug) do nothing;

-- بيانات تجريبية للكورسات
insert into public.courses (title, slug, description, level)
values
('Boxing Fundamentals', 'boxing-fundamentals', 'أساسيات الملاكمة من البداية', 'Beginner'),
('Punching Techniques', 'punching-techniques', 'Jab و Cross و Hook و Uppercut', 'Technique'),
('Defense & Movement', 'defense-movement', 'الحركة والدفاع والمراوغة', 'Defense'),
('Advanced Boxing', 'advanced-boxing', 'تقنيات وتدريبات متقدمة', 'Advanced')
on conflict (slug) do nothing;

-- ربط مبدئي للباقات بالكورسات
insert into public.plan_courses (plan_id, course_id)
select p.id, c.id
from public.plans p cross join public.courses c
where
  (p.slug = 'basic' and c.slug = 'boxing-fundamentals')
  or
  (p.slug = 'pro' and c.slug in ('boxing-fundamentals','punching-techniques','defense-movement'))
  or
  (p.slug = 'elite' and c.slug in ('boxing-fundamentals','punching-techniques','defense-movement','advanced-boxing'))
on conflict do nothing;
