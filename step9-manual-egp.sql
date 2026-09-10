
-- SAQR Academy STEP 9
-- Egyptian Pound + manual payment confirmation.
-- Customer payment NEVER activates a subscription automatically.

alter table public.plans
  add column if not exists currency text not null default 'EGP';

alter table public.payments
  add column if not exists payment_method text,
  add column if not exists customer_reference text,
  add column if not exists admin_note text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid references public.profiles(id);

-- Keep all new subscriptions pending until an admin confirms the payment.
alter table public.subscriptions
  add column if not exists activated_at timestamptz,
  add column if not exists activated_by uuid references public.profiles(id);

-- Admin-only payment management.
drop policy if exists "admin_payments_all" on public.payments;
create policy "admin_payments_all" on public.payments
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Admin-only subscription management.
drop policy if exists "admin_subscriptions_all" on public.subscriptions;
create policy "admin_subscriptions_all" on public.subscriptions
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Helpful indexes.
create index if not exists idx_payments_status_created
on public.payments(status, created_at desc);

create index if not exists idx_subscriptions_status_created
on public.subscriptions(status, created_at desc);

-- Recommended payment status values:
-- pending_confirmation, paid, failed, refunded
-- Recommended subscription status values:
-- pending, active, expired, cancelled
