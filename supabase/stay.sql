-- 하우스토리 스테이 예약 시스템. Supabase SQL Editor 에 붙여넣고 Run.
-- (admin-only.sql 의 public.is_howstory_admin() 함수가 먼저 있어야 해요.)

-- 1) 플랜 (2인/4인/6인)
create table if not exists public.stay_plans (
  id             text primary key,       -- p2 | p4 | p6
  guests         integer not null,       -- 최대 인원
  weekday_price  integer not null,       -- 1박(일~목 밤), 원
  weekend_price  integer not null,       -- 1박(금·토 밤), 원
  sort           integer not null default 0,
  active         boolean not null default true
);
insert into public.stay_plans (id, guests, weekday_price, weekend_price, sort) values
  ('p2', 2, 120000, 150000, 1),
  ('p4', 4, 160000, 190000, 2),
  ('p6', 6, 200000, 240000, 3)
on conflict (id) do nothing;

-- 2) 달력 (기본은 열림. 막거나 요금을 덮어쓸 날만 저장)
create table if not exists public.stay_calendar (
  day     date primary key,
  status  text not null default 'open',   -- open | blocked | booked
  price   integer,                        -- 이 날만 다른 1박 요금(원). null 이면 플랜 요금
  note    text
);

-- 3) 예약 요청
create table if not exists public.stay_bookings (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  check_in    date not null,
  check_out   date not null,
  nights      integer not null,
  plan_id     text not null,
  guests      integer not null,
  total       integer not null,           -- 요청 시점 총액(원)
  name        text,
  contact     text not null,
  memo        text,
  lang        text default 'ko',
  status      text not null default 'new',  -- new | confirmed | declined | canceled
  note        text,                         -- 어드민 메모
  source      text default 'site'
);
create index if not exists stay_bookings_created_idx on public.stay_bookings (created_at desc);
create index if not exists stay_bookings_dates_idx on public.stay_bookings (check_in, check_out);

alter table public.stay_plans    enable row level security;
alter table public.stay_calendar enable row level security;
alter table public.stay_bookings enable row level security;

-- 플랜·달력: 누구나 읽기, 관리자만 쓰기
drop policy if exists "plans public read"  on public.stay_plans;
drop policy if exists "plans admin write"  on public.stay_plans;
create policy "plans public read" on public.stay_plans for select to anon, authenticated using (true);
create policy "plans admin write" on public.stay_plans for all to authenticated using (public.is_howstory_admin()) with check (public.is_howstory_admin());

drop policy if exists "calendar public read" on public.stay_calendar;
drop policy if exists "calendar admin write" on public.stay_calendar;
create policy "calendar public read" on public.stay_calendar for select to anon, authenticated using (true);
create policy "calendar admin write" on public.stay_calendar for all to authenticated using (public.is_howstory_admin()) with check (public.is_howstory_admin());

-- 예약 요청: 방문자는 '신규'로 넣기만, 관리자만 보고 고침
drop policy if exists "bookings anyone insert" on public.stay_bookings;
drop policy if exists "bookings admin read"    on public.stay_bookings;
drop policy if exists "bookings admin update"  on public.stay_bookings;
drop policy if exists "bookings admin delete"  on public.stay_bookings;
create policy "bookings anyone insert" on public.stay_bookings for insert to anon, authenticated
  with check (status = 'new' and check_out > check_in and nights between 1 and 30 and guests between 1 and 6);
create policy "bookings admin read"   on public.stay_bookings for select to authenticated using (public.is_howstory_admin());
create policy "bookings admin update" on public.stay_bookings for update to authenticated using (public.is_howstory_admin()) with check (public.is_howstory_admin());
create policy "bookings admin delete" on public.stay_bookings for delete to authenticated using (public.is_howstory_admin());
