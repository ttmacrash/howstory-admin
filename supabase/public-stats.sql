-- 1) 사이트가 읽는 공개 숫자: 이달 완료 건수, 누적 완료 건수 (접수 내용은 노출하지 않음)
create or replace function public.howstory_public_stats()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'month_done', (
      select count(*) from public.requests
      where status = 'done' and coalesce(source, 'site') <> 'test'
        and date_trunc('month', created_at at time zone 'Asia/Seoul')
          = date_trunc('month', now() at time zone 'Asia/Seoul')
    ),
    'total_done', (
      select count(*) from public.requests
      where status = 'done' and coalesce(source, 'site') <> 'test'
    ),
    'cap', 10
  );
$$;
grant execute on function public.howstory_public_stats() to anon, authenticated;

-- 2) 방문자는 '신규' 상태로만 넣을 수 있게 (완료 건수를 조작 못 하도록)
drop policy if exists "anyone can insert" on public.requests;
create policy "anyone can insert" on public.requests
  for insert to anon with check (status = 'new');
drop policy if exists "admin can insert" on public.requests;
create policy "admin can insert" on public.requests
  for insert to authenticated with check (public.is_howstory_admin());

-- 3) 하우스토리 001 (김희대 고객님) 완료 건
insert into public.requests (name, contact, purpose, budget, memo, status, note, source)
values ('김희대', '(직접 수령)', '게임', null,
        '하우스토리 001 · 첫 번째 고객. 화이트 케이스, 지포스 RTX, 듀얼타워 공랭, ARGB 팬.',
        'done', '첫 조립 완료. 후기: "조합이 끝내주는 컴퓨터 조립이었습니다."', 'site');
