-- SAQR Academy STEP 10
-- Registration -> choose plan -> manual EGP payment -> admin confirmation.
-- Also adds payment proof screenshot, sender number, account status, and admin controls.

-- 1) User profile details
alter table public.profiles
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists account_status text not null default 'active'
    check (account_status in ('active','suspended'));

-- Keep profile data in sync for newly registered users.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, phone, account_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    nullif(new.raw_user_meta_data->>'phone', ''),
    'active'
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    email = excluded.email,
    phone = excluded.phone;
  return new;
end;
$$;

-- 2) Payment proof fields
alter table public.payments
  add column if not exists sender_phone text,
  add column if not exists proof_path text;

-- 3) Pending subscriptions must be allowed to have no dates yet.
alter table public.subscriptions alter column starts_at drop not null;
alter table public.subscriptions alter column ends_at drop not null;

-- 4) Admin can read/manage profiles.
drop policy if exists "admin_profiles_all" on public.profiles;
create policy "admin_profiles_all" on public.profiles
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 5) Customer can read their own payments/subscription status.
drop policy if exists "payments_own_read" on public.payments;
create policy "payments_own_read" on public.payments
for select to authenticated
using (user_id = auth.uid());

-- Customer may create a payment request only for themselves.
drop policy if exists "payments_own_insert" on public.payments;
create policy "payments_own_insert" on public.payments
for insert to authenticated
with check (user_id = auth.uid());

-- Customer may read their own subscriptions (already exists in step 3, kept here for safety).
drop policy if exists "subscriptions_own_read" on public.subscriptions;
create policy "subscriptions_own_read" on public.subscriptions
for select to authenticated
using (user_id = auth.uid());

-- Customer may create a pending subscription for themselves.
drop policy if exists "subscriptions_own_pending_insert" on public.subscriptions;
create policy "subscriptions_own_pending_insert" on public.subscriptions
for insert to authenticated
with check (user_id = auth.uid() and status = 'pending');

-- 6) Private payment proof bucket.
-- Create a PRIVATE bucket named: payment-proofs
-- The customer uploads only inside their own folder: <user_id>/...

drop policy if exists "payment_proofs_own_insert" on storage.objects;
create policy "payment_proofs_own_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "payment_proofs_own_select" on storage.objects;
create policy "payment_proofs_own_select"
on storage.objects for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
);

drop policy if exists "admin_payment_proofs_delete" on storage.objects;
create policy "admin_payment_proofs_delete"
on storage.objects for delete to authenticated
using (bucket_id = 'payment-proofs' and public.is_admin());

-- 7) Helpful indexes.
create index if not exists idx_profiles_created_at on public.profiles(created_at desc);
create index if not exists idx_profiles_account_status on public.profiles(account_status);
create index if not exists idx_payments_user_created on public.payments(user_id, created_at desc);

-- 8) Course access must require an active account as well as an active subscription.
drop policy if exists "lessons_subscriber_read" on public.lessons;
create policy "lessons_subscriber_read" on public.lessons
for select to authenticated
using (
  exists (
    select 1
    from public.plan_courses pc
    join public.subscriptions s on s.plan_id = pc.plan_id
    join public.profiles pr on pr.id = s.user_id
    where pc.course_id = lessons.course_id
      and s.user_id = auth.uid()
      and s.status = 'active'
      and s.ends_at > now()
      and pr.account_status = 'active'
  )
);

-- 9) Make plans explicitly EGP for this build.
update public.plans set currency = 'EGP' where currency is null or currency <> 'EGP';

-- NOTE: Set the admin role securely in Supabase Auth app_metadata, not user metadata.
