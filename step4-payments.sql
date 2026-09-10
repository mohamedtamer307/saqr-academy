-- SAQR STEP 4: payment records
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  provider text not null default 'moyasar',
  provider_payment_id text unique,
  amount numeric(10,2) not null,
  currency text not null default 'SAR',
  status text not null default 'initiated'
    check (status in ('initiated','paid','failed','refunded','voided','authorized','captured')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.payments enable row level security;

drop policy if exists "payments_own_read" on public.payments;
create policy "payments_own_read" on public.payments
for select to authenticated using (user_id = auth.uid());

-- Writes should be performed by the Edge Function/backend after payment verification.
