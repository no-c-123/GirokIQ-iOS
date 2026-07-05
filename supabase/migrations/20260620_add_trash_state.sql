alter table public.notebooks
add column if not exists trashed_at timestamptz;

alter table public.folders
add column if not exists trashed_at timestamptz;

create index if not exists notebooks_user_trashed_at_idx
on public.notebooks (user_id, trashed_at);

create index if not exists folders_user_trashed_at_idx
on public.folders (user_id, trashed_at);
