-- 하우스토리 견적 요청 테이블. Supabase 대시보드 > SQL Editor 에 붙여넣고 Run.
create table if not exists public.requests (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  name        text,
  contact     text not null,
  purpose     text,
  budget      integer,          -- 만원
  memo        text,
  status      text not null default 'new',   -- new | contacted | quoted | building | done | canceled
  note        text,             -- 어드민 메모
  source      text default 'site'
);

alter table public.requests enable row level security;

-- 누구나(사이트 방문자) 신청은 넣을 수 있음
drop policy if exists "anyone can insert" on public.requests;
create policy "anyone can insert" on public.requests
  for insert to anon, authenticated with check (true);

-- 로그인한 관리자만 조회/수정/삭제
drop policy if exists "admin can read" on public.requests;
create policy "admin can read" on public.requests
  for select to authenticated using (true);

drop policy if exists "admin can update" on public.requests;
create policy "admin can update" on public.requests
  for update to authenticated using (true) with check (true);

drop policy if exists "admin can delete" on public.requests;
create policy "admin can delete" on public.requests
  for delete to authenticated using (true);

create index if not exists requests_created_at_idx on public.requests (created_at desc);
