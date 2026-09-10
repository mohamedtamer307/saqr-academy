-- SAQR Academy STEP 11 - Admin upgrade + reliable payment activation

alter table public.courses add column if not exists category text;
alter table public.courses add column if not exists thumbnail_url text;
alter table public.courses add column if not exists is_featured boolean not null default false;
alter table public.lessons add column if not exists duration_minutes integer not null default 0;
alter table public.lessons add column if not exists is_preview boolean not null default false;

-- Reliable, atomic admin payment confirmation. This avoids partial updates where
-- payment becomes paid but subscription stays pending (or vice versa).
create or replace function public.admin_confirm_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.payments%rowtype;
  s public.subscriptions%rowtype;
  dur integer;
  started timestamptz := now();
  finished timestamptz;
begin
  if not public.is_admin() then
    raise exception 'ليس لديك صلاحية الإدارة';
  end if;

  select * into p from public.payments where id = p_payment_id for update;
  if not found then
    return jsonb_build_object('success',false,'message','عملية الدفع غير موجودة');
  end if;

  if p.status = 'paid' then
    return jsonb_build_object('success',true,'message','تم تفعيل هذه العملية مسبقًا');
  end if;

  select * into s
  from public.subscriptions
  where user_id = p.user_id
    and plan_id = p.plan_id
    and status = 'pending'
  order by created_at desc
  limit 1
  for update;

  if not found then
    return jsonb_build_object('success',false,'message','لم يتم العثور على اشتراك قيد المراجعة لهذا الدفع');
  end if;

  select duration_days into dur from public.plans where id = p.plan_id;
  finished := started + (coalesce(dur,30) || ' days')::interval;

  update public.payments
  set status='paid', confirmed_at=started, confirmed_by=auth.uid(), updated_at=started
  where id=p.id;

  update public.subscriptions
  set status='active', starts_at=started, ends_at=finished,
      activated_at=started, activated_by=auth.uid()
  where id=s.id;

  update public.profiles set account_status='active' where id=p.user_id;

  insert into public.admin_audit_logs(admin_id,action,target_type,target_id,details)
  values(auth.uid(),'confirm_payment','payment',p.id,
         jsonb_build_object('user_id',p.user_id,'plan_id',p.plan_id,'subscription_id',s.id,'amount',p.amount,'currency',p.currency));

  return jsonb_build_object('success',true,'message','تم تفعيل الاشتراك','subscription_id',s.id);
end;
$$;
revoke all on function public.admin_confirm_payment(uuid) from public;
grant execute on function public.admin_confirm_payment(uuid) to authenticated;

-- Useful admin audit access.
alter table public.admin_audit_logs enable row level security;
drop policy if exists "admin_audit_select" on public.admin_audit_logs;
create policy "admin_audit_select" on public.admin_audit_logs
for select to authenticated using (public.is_admin());

create index if not exists idx_courses_featured on public.courses(is_featured, is_active);
create index if not exists idx_lessons_course_sort on public.lessons(course_id, sort_order);
