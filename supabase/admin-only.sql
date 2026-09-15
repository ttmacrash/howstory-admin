-- 관리자(ttmacrash@shortply.co.kr)만 조회/수정/삭제. Supabase SQL Editor 에 붙여넣고 Run.
create or replace function public.is_howstory_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'ttmacrash@shortply.co.kr'
$$;

drop policy if exists "admin can read"   on public.requests;
drop policy if exists "admin can update" on public.requests;
drop policy if exists "admin can delete" on public.requests;

create policy "admin can read" on public.requests
  for select to authenticated using (public.is_howstory_admin());

create policy "admin can update" on public.requests
  for update to authenticated using (public.is_howstory_admin()) with check (public.is_howstory_admin());

create policy "admin can delete" on public.requests
  for delete to authenticated using (public.is_howstory_admin());
