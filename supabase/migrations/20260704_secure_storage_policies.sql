insert into storage.buckets (id, name, public)
values ('page-drawings', 'page-drawings', false)
on conflict (id) do nothing;

drop policy if exists "Authenticated users can read canvas images" on storage.objects;
drop policy if exists "Authenticated users can upload canvas images" on storage.objects;
drop policy if exists "Authenticated users can update canvas images" on storage.objects;
drop policy if exists "Authenticated users can delete canvas images" on storage.objects;

drop policy if exists "Owners read own drawings" on storage.objects;
drop policy if exists "Owners write own drawings" on storage.objects;
drop policy if exists "Owners update own drawings" on storage.objects;
drop policy if exists "Owners delete own drawings" on storage.objects;

create policy "Owners read own drawings"
on storage.objects for select to authenticated
using (
  bucket_id in ('page-drawings', 'canvas-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Owners write own drawings"
on storage.objects for insert to authenticated
with check (
  bucket_id in ('page-drawings', 'canvas-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Owners update own drawings"
on storage.objects for update to authenticated
using (
  bucket_id in ('page-drawings', 'canvas-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Owners delete own drawings"
on storage.objects for delete to authenticated
using (
  bucket_id in ('page-drawings', 'canvas-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);
