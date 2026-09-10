
alter table public.lesson_progress
add column if not exists progress_percent numeric(5,2) not null default 0;
alter table public.lesson_progress
add column if not exists last_position numeric not null default 0;
