-- 사진·동영상 업로드 권한 수정: 방문자는 requests 를 못 읽어서 폴더 검사가 항상 실패했음.
-- 검사를 security definer 함수로 옮김.
create or replace function public.is_review_folder(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.requests r
    where r.status = 'done'
      and r.review_token::text = split_part(p_name, '/', 1)
  )
$$;
grant execute on function public.is_review_folder(text) to anon, authenticated;

drop policy if exists "review media upload" on storage.objects;
create policy "review media upload" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'reviews' and public.is_review_folder(name));

drop policy if exists "review media delete" on storage.objects;
create policy "review media delete" on storage.objects for delete to anon, authenticated
  using (bucket_id = 'reviews' and public.is_review_folder(name));
