
-- SAQR Academy STEP 7
-- Course + lessons manager, plan/course assignment, private video upload.

-- The original schema uses ends_at and sort_order.
-- Add the video_path field if it is not already present.
alter table public.lessons add column if not exists video_path text;

-- Admin helper: role must be in auth.users.app_metadata, not user-editable metadata.
create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

-- Admin CRUD policies
drop policy if exists "admin_plans_all" on public.plans;
create policy "admin_plans_all" on public.plans
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin_courses_all" on public.courses;
create policy "admin_courses_all" on public.courses
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin_lessons_all" on public.lessons;
create policy "admin_lessons_all" on public.lessons
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin_plan_courses_all" on public.plan_courses;
create policy "admin_plan_courses_all" on public.plan_courses
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin_subscriptions_all" on public.subscriptions;
create policy "admin_subscriptions_all" on public.subscriptions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Private video bucket. Create this bucket in Storage if it doesn't exist:
-- academy-videos (Private)
--
-- Storage policies:
drop policy if exists "admin_video_upload" on storage.objects;
create policy "admin_video_upload"
on storage.objects for insert to authenticated
with check (bucket_id = 'academy-videos' and public.is_admin());

drop policy if exists "admin_video_update" on storage.objects;
create policy "admin_video_update"
on storage.objects for update to authenticated
using (bucket_id = 'academy-videos' and public.is_admin())
with check (bucket_id = 'academy-videos' and public.is_admin());

drop policy if exists "admin_video_delete" on storage.objects;
create policy "admin_video_delete"
on storage.objects for delete to authenticated
using (bucket_id = 'academy-videos' and public.is_admin());

-- Admin can read object metadata; actual video access is still through signed URLs.
drop policy if exists "admin_video_select" on storage.objects;
create policy "admin_video_select"
on storage.objects for select to authenticated
using (bucket_id = 'academy-videos' and public.is_admin());
