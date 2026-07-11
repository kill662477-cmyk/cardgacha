-- card-gacha 2차 마이그레이션
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요.
-- 실행 전에도 기존 기능은 정상 동작하며, 실행 후 출석 연속/도감 완성 보상/티커 실시간이 활성화됩니다.
-- 여러 번 실행해도 안전하도록(idempotent) 작성했습니다.

-- G. 출석 이코노미: 연속 출석 카운터
alter table gacha_users add column if not exists streak int not null default 0;

-- E. 도감 완성 보상 수령 기록 (멤버 단위, 1회)
create table if not exists gacha_member_rewards (
  user_id uuid references gacha_users(id) on delete cascade,
  member text not null,
  rewarded_at timestamptz default now(),
  primary key (user_id, member)
);
alter table gacha_member_rewards enable row level security;
-- (정책 미생성 = anon 전면 차단, service_role 만 통과)

-- F. 티커 실시간화: 공지는 공개 정보이므로 anon SELECT 허용 + realtime publication 등록
drop policy if exists "anon read announcements" on gacha_announcements;
create policy "anon read announcements"
  on gacha_announcements for select to anon using (true);

do $$
begin
  alter publication supabase_realtime add table gacha_announcements;
exception
  when duplicate_object then null;
end $$;
