-- 하우스토리 고객 후기. Supabase SQL Editor 에 통째로 붙여넣고 Run.

-- 1) 접수 건마다 후기 링크용 토큰
alter table public.requests add column if not exists review_token uuid not null default gen_random_uuid();
create unique index if not exists requests_review_token_idx on public.requests (review_token);

-- 2) 후기 테이블 (접수 1건당 후기 1개)
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null unique references public.requests(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  rating      integer not null check (rating between 1 and 5),
  body        text not null check (char_length(body) between 1 and 1000),
  media       jsonb not null default '[]'::jsonb,   -- [{path, type}] type: image | video
  approved    boolean not null default false
);
alter table public.reviews enable row level security;

drop policy if exists "admin reads reviews" on public.reviews;
create policy "admin reads reviews" on public.reviews for select to authenticated using (public.is_howstory_admin());
drop policy if exists "admin updates reviews" on public.reviews;
create policy "admin updates reviews" on public.reviews for update to authenticated using (public.is_howstory_admin()) with check (public.is_howstory_admin());
drop policy if exists "admin deletes reviews" on public.reviews;
create policy "admin deletes reviews" on public.reviews for delete to authenticated using (public.is_howstory_admin());

-- 3) 이름 가리기: 김희대 -> 김*대, 이훈 -> 이*, 외자/영문은 앞글자만
create or replace function public.mask_name(n text)
returns text language sql immutable as $$
  select case
    when n is null or length(trim(n)) = 0 then '고객'
    when length(trim(n)) = 1 then trim(n)
    when length(trim(n)) = 2 then left(trim(n), 1) || '*'
    else left(trim(n), 1) || repeat('*', length(trim(n)) - 2) || right(trim(n), 1)
  end
$$;

-- 4) 후기 링크를 연 손님에게 보여줄 정보 (토큰이 맞고 완료된 건만)
create or replace function public.review_context(t uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'ok', true,
    'name', public.mask_name(r.name),
    'purpose', r.purpose,
    'done_at', r.created_at,
    'review', (select json_build_object('rating', v.rating, 'body', v.body, 'media', v.media, 'approved', v.approved)
               from public.reviews v where v.request_id = r.id)
  )
  from public.requests r
  where r.review_token = t and r.status = 'done'
  limit 1
$$;
grant execute on function public.review_context(uuid) to anon, authenticated;

-- 5) 후기 저장 (처음이면 생성, 이미 있으면 수정. 수정하면 다시 승인 대기)
create or replace function public.submit_review(t uuid, p_rating integer, p_body text, p_media jsonb default '[]'::jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  select id into rid from public.requests where review_token = t and status = 'done';
  if rid is null then raise exception 'invalid token'; end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'rating'; end if;
  if p_body is null or char_length(trim(p_body)) = 0 or char_length(p_body) > 1000 then raise exception 'body'; end if;
  if jsonb_typeof(p_media) <> 'array' or jsonb_array_length(p_media) > 12 then raise exception 'media'; end if;
  insert into public.reviews (request_id, rating, body, media, approved)
  values (rid, p_rating, trim(p_body), p_media, false)
  on conflict (request_id) do update
    set rating = excluded.rating, body = excluded.body, media = excluded.media, approved = false, updated_at = now();
  return json_build_object('ok', true);
end $$;
grant execute on function public.submit_review(uuid, integer, text, jsonb) to anon, authenticated;

-- 6) 사이트에 보여줄 승인된 후기 (이름은 가린 채)
create or replace function public.public_reviews()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
    'name', public.mask_name(r.name),
    'purpose', r.purpose,
    'budget', r.budget,
    'rating', v.rating,
    'body', v.body,
    'media', v.media,
    'at', v.updated_at
  ) order by v.updated_at desc), '[]'::json)
  from public.reviews v join public.requests r on r.id = v.request_id
  where v.approved = true
$$;
grant execute on function public.public_reviews() to anon, authenticated;

-- 7) 사진·동영상 저장소: reviews 버킷 (공개 읽기, 파일당 50MB, 이미지/동영상만)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reviews', 'reviews', true, 52428800,
        array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public = true, file_size_limit = 52428800,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/quicktime','video/webm'];

-- 손님은 자기 토큰 폴더(reviews/<token>/...)에만 올리고 지울 수 있음. 완료된 건의 토큰만 유효.
drop policy if exists "review media upload" on storage.objects;
create policy "review media upload" on storage.objects for insert to anon, authenticated
  with check (
    bucket_id = 'reviews'
    and (storage.foldername(name))[1] in (select review_token::text from public.requests where status = 'done')
  );
drop policy if exists "review media delete" on storage.objects;
create policy "review media delete" on storage.objects for delete to anon, authenticated
  using (
    bucket_id = 'reviews'
    and (storage.foldername(name))[1] in (select review_token::text from public.requests where status = 'done')
  );
drop policy if exists "review media public read" on storage.objects;
create policy "review media public read" on storage.objects for select to anon, authenticated
  using (bucket_id = 'reviews');
