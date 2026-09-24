create extension if not exists pgcrypto;

create extension if not exists moddatetime with schema extensions;

create table if not exists public.folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  parent_id uuid references public.folders (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  trashed_at timestamptz,
  deleted_at timestamptz
);

create table if not exists public.notebooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  folder_id uuid references public.folders (id) on delete set null,
  name text not null default 'Untitled',
  canvas_type text not null default 'infinite',
  page_dimensions jsonb,
  background_pattern text not null default 'blank',
  background_color_hex text not null default '#0F0F0E',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  trashed_at timestamptz,
  deleted_at timestamptz,
  constraint notebooks_canvas_type_check check (canvas_type in ('infinite', 'fixed')),
  constraint notebooks_background_pattern_check check (background_pattern in ('blank', 'grid', 'dots', 'lines', 'isometric'))
);

create table if not exists public.pages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  notebook_id uuid not null references public.notebooks (id) on delete cascade,
  title text not null default 'Page',
  page_index integer not null default 0,
  type text not null default 'canvas',
  settings jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  drawing_rev bigint not null default 0,
  drawing_hash text,
  drawing_bytes bigint not null default 0,
  deleted_at timestamptz,
  constraint pages_type_check check (type in ('canvas', 'note'))
);

create table if not exists public.canvas_elements (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null,
  content text,
  position_x double precision not null default 0,
  position_y double precision not null default 0,
  width double precision,
  height double precision,
  rotation double precision not null default 0,
  z_index integer not null default 0,
  style jsonb,
  user_resized boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  notebook_id uuid references public.notebooks (id) on delete set null,
  title text not null default 'New Chat',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  role text not null,
  content text not null,
  token_count integer,
  created_at timestamptz not null default timezone('utc', now()),
  constraint messages_role_check check (role in ('user', 'assistant', 'system'))
);

create table if not exists public.app_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_notebook_id uuid references public.notebooks (id) on delete set null,
  last_page_id uuid references public.pages (id) on delete set null,
  preferences jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists folders_user_created_idx
  on public.folders (user_id, created_at desc);

create index if not exists folders_user_trashed_at_idx
  on public.folders (user_id, trashed_at);

create index if not exists folders_user_updated_idx
  on public.folders (user_id, updated_at desc);

create index if not exists folders_user_updated_delta_idx
  on public.folders (user_id, updated_at);

create index if not exists notebooks_user_updated_idx
  on public.notebooks (user_id, updated_at desc);

create index if not exists notebooks_user_trashed_at_idx
  on public.notebooks (user_id, trashed_at);

create index if not exists notebooks_user_updated_delta_idx
  on public.notebooks (user_id, updated_at);

create index if not exists notebooks_folder_idx
  on public.notebooks (folder_id);

create unique index if not exists pages_notebook_page_index_uidx
  on public.pages (notebook_id, page_index);

create index if not exists pages_user_updated_idx
  on public.pages (user_id, updated_at desc);

create index if not exists pages_user_updated_delta_idx
  on public.pages (user_id, updated_at);

create index if not exists pages_notebook_idx
  on public.pages (notebook_id, page_index);

create index if not exists canvas_elements_page_idx
  on public.canvas_elements (page_id, z_index);

create index if not exists canvas_elements_user_updated_delta_idx
  on public.canvas_elements (user_id, updated_at);

create index if not exists chats_user_updated_idx
  on public.chats (user_id, updated_at desc);

create index if not exists chats_notebook_idx
  on public.chats (notebook_id);

create index if not exists messages_chat_created_idx
  on public.messages (chat_id, created_at asc);

alter table public.folders enable row level security;
alter table public.notebooks enable row level security;
alter table public.pages enable row level security;
alter table public.canvas_elements enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;
alter table public.app_state enable row level security;

drop policy if exists "Users manage own folders" on public.folders;
create policy "Users manage own folders"
on public.folders
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users manage own notebooks" on public.notebooks;
create policy "Users manage own notebooks"
on public.notebooks
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users manage own pages" on public.pages;
create policy "Users manage own pages"
on public.pages
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users manage own canvas elements" on public.canvas_elements;
create policy "Users manage own canvas elements"
on public.canvas_elements
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users manage own chats" on public.chats;
create policy "Users manage own chats"
on public.chats
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users read own messages" on public.messages;
create policy "Users read own messages"
on public.messages
for select
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = messages.chat_id
      and c.user_id = auth.uid()
  )
);

drop policy if exists "Users insert own messages" on public.messages;
create policy "Users insert own messages"
on public.messages
for insert
to authenticated
with check (
  exists (
    select 1
    from public.chats c
    where c.id = messages.chat_id
      and c.user_id = auth.uid()
  )
);

drop policy if exists "Users update own messages" on public.messages;
create policy "Users update own messages"
on public.messages
for update
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = messages.chat_id
      and c.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.chats c
    where c.id = messages.chat_id
      and c.user_id = auth.uid()
  )
);

drop policy if exists "Users delete own messages" on public.messages;
create policy "Users delete own messages"
on public.messages
for delete
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = messages.chat_id
      and c.user_id = auth.uid()
  )
);

drop policy if exists "Users manage own app state" on public.app_state;
create policy "Users manage own app state"
on public.app_state
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.set_current_timestamp_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_folders_updated_at on public.folders;
create trigger set_folders_updated_at
before update on public.folders
for each row
execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_notebooks_updated_at on public.notebooks;
create trigger set_notebooks_updated_at
before update on public.notebooks
for each row
execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_pages_updated_at on public.pages;
create trigger set_pages_updated_at
before update on public.pages
for each row
execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_canvas_elements_updated_at on public.canvas_elements;
create trigger set_canvas_elements_updated_at
before update on public.canvas_elements
for each row
execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_chats_updated_at on public.chats;
create trigger set_chats_updated_at
before update on public.chats
for each row
execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_app_state_updated_at on public.app_state;
create trigger set_app_state_updated_at
before update on public.app_state
for each row
execute function public.set_current_timestamp_updated_at();

insert into storage.buckets (id, name, public)
values
  ('canvas-images', 'canvas-images', false),
  ('page-drawings', 'page-drawings', false)
on conflict (id) do nothing;

create or replace function public.storage_usage_bytes()
returns bigint
language sql
security invoker
as $$
  select coalesce(sum(p.drawing_bytes), 0)
       + coalesce((
           select sum((o.metadata->>'size')::bigint)
           from storage.objects o
           where o.bucket_id = 'canvas-images'
             and (storage.foldername(o.name))[1] = auth.uid()::text
         ), 0)
  from public.pages p
  where p.user_id = auth.uid()
    and p.deleted_at is null;
$$;
