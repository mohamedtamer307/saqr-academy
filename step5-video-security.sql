-- SAQR Academy — Step 5
alter table public.lessons add column if not exists video_path text;

create index if not exists idx_lessons_course_id on public.lessons(course_id);
create index if not exists idx_progress_user_lesson on public.lesson_progress(user_id, lesson_id);

-- Supabase Storage:
-- Create bucket: academy-videos
-- Public bucket: OFF (Private)
-- Put paths such as COURSE_ID/lesson-1.mp4 in lessons.video_path.
