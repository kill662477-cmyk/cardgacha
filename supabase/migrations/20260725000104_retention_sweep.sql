-- 보존기간 자동 정리(retention sweep).
--
-- 배경: gacha_s2_idempotency 와 gacha_s2_pack_draws 를 지우는 주체가 아무것도 없어서
-- 무한히 커졌다. 2026-07-25 기준 idempotency 3.8GB(만료 39만 행 방치) / pack_draws 1.9GB,
-- DB 전체 6.25GB 에 하루 약 1GB씩 증가. 디스크가 꽉 차 Postgres 가 읽기 전용으로 떨어지고
-- 재시작하는 장애가 실제로 발생했다.
--
-- 왜 "잘게" 도는가: 한 번에 15만 행을 지우면 WAL 이 급증해 오히려 디스크를 더 먹는다
-- (장애 당시 그렇게 터졌다). 2만 행 배치는 실측상 수 초 내에 끝나고 WAL 스파이크가 없다.
-- 그래서 한 번 실행에 테이블당 2만 행만 지우고, 5분마다 반복해 서서히 따라잡는다.
--
-- 보존 기준
--   * gacha_s2_idempotency: expires_at(생성 +24시간) 이 1시간 더 지난 행.
--     여유 1시간은 "아직 재시도될 수도 있는" 행을 실수로 지우지 않기 위한 안전 마진이다.
--   * gacha_s2_pack_draws: 3일. 게임 로직은 이 테이블을 읽지 않는다.
--     실시간 티커는 INSERT 트리거로 복사되는 gacha_s2_live_events 를 읽는다.
--     남는 용도는 "어떤 서버 시드가 어떤 카드를 냈는가" 감사뿐이라 3일이면 분쟁 확인에 충분하다.
--
-- 두 테이블 모두 이를 참조하는 외래키가 없어 삭제가 다른 테이블로 번지지 않는다(확인함).

create extension if not exists pg_cron;

create or replace function public.gacha_s2_retention_sweep(
  p_batch integer default 20000
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_idempotency integer := 0;
  v_pack_draws integer := 0;
begin
  -- 배치 크기를 강제로 묶는다. 큰 값이 들어오면 WAL 스파이크가 나 장애로 이어진다.
  if p_batch is null or p_batch < 1000 or p_batch > 50000 then
    p_batch := 20000;
  end if;

  with doomed as (
    select ctid from public.gacha_s2_idempotency
    where expires_at < now() - interval '1 hour'
    limit p_batch
  )
  delete from public.gacha_s2_idempotency t using doomed where t.ctid = doomed.ctid;
  get diagnostics v_idempotency = row_count;

  with doomed as (
    select ctid from public.gacha_s2_pack_draws
    where created_at < now() - interval '3 days'
    limit p_batch
  )
  delete from public.gacha_s2_pack_draws t using doomed where t.ctid = doomed.ctid;
  get diagnostics v_pack_draws = row_count;

  return jsonb_build_object(
    'idempotencyDeleted', v_idempotency,
    'packDrawsDeleted', v_pack_draws,
    'batch', p_batch,
    'at', now()
  );
end;
$$;

revoke all on function public.gacha_s2_retention_sweep(integer) from public, anon, authenticated;

-- 5분마다. 배치 2만 x 2테이블 = 실행당 최대 4만 행.
select cron.unschedule('gacha-s2-retention-sweep')
where exists (select 1 from cron.job where jobname = 'gacha-s2-retention-sweep');

select cron.schedule(
  'gacha-s2-retention-sweep',
  '*/5 * * * *',
  $cron$select public.gacha_s2_retention_sweep(20000)$cron$
);
