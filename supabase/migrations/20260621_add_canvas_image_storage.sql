insert into storage.buckets (id, name, public)
values ('canvas-images', 'canvas-images', false)
on conflict (id) do nothing;

create policy "Authenticated users can read canvas images"
on storage.objects
for select
to authenticated
using (bucket_id = 'canvas-images');

create policy "Authenticated users can upload canvas images"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'canvas-images');

create policy "Authenticated users can update canvas images"
on storage.objects
for update
to authenticated
using (bucket_id = 'canvas-images')
with check (bucket_id = 'canvas-images');

create policy "Authenticated users can delete canvas images"
on storage.objects
for delete
to authenticated
using (bucket_id = 'canvas-images');
