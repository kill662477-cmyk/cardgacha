-- 투기장 주간 정산. 월요일 00:00 KST = 일요일 15:00 UTC.
-- cron 은 UTC 로 돈다(로또가 10/15/20 KST 를 1/6/11 UTC 로 잡아둔 것과 같은 기준).
-- settle_week 는 인자가 없으면 "하루 전"의 주 키를 쓰므로 방금 끝난 주가 정산된다.
select cron.schedule(
  'gacha-s2-arena-weekly-settle',
  '0 15 * * 0',
  $cron$select public.gacha_s2_arena_settle_week();$cron$
);

do $$
declare v_count integer;
begin
  select count(*) into v_count from cron.job where jobname = 'gacha-s2-arena-weekly-settle';
  if v_count <> 1 then
    raise exception 'arena weekly settle cron not registered: %', v_count;
  end if;
end;
$$;
