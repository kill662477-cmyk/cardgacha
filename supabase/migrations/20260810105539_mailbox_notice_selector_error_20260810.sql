-- 카드 선택권 오류 안내 우편.
-- 보상은 이미 인벤토리에 직접 지급했다. 이 우편은 안내만 한다(points = 0).
-- event_key 로 중복 발송을 막는다.

-- 1) 전 계정 안내
insert into public.gacha_s2_mailbox (user_id, event_key, category, title, body, points)
select p.user_id,
  'sss-selector-error-notice-20260810',
  'SYSTEM',
  '🔧 SSS 카드 선택권 오류 안내 및 보상 지급',
  E'불편을 드려 죄송합니다.\n'
  || E'오늘 지급해 드린 SSS 카드 선택권에서 두 가지 오류가 있었고, 모두 수정을 마쳤습니다.\n\n'
  || E'━━━━━━━━━━━━━━\n\n'
  || E'▪ 오류 1 — 한 장만 골랐는데 두 장이 소모됨\n'
  || E'카드를 고르고 확인을 누른 뒤에도 선택 상태가 남아 있어, 결과 창을 닫는 동작이\n'
  || E'확인을 한 번 더 누른 것처럼 처리됐습니다. 그 결과 같은 카드로 두 번째 장이\n'
  || E'즉시 소모됐습니다. 서버에서 직접 차단하도록 수정을 마쳤습니다.\n\n'
  || E'▪ 오류 2 — "요청 처리 실패" 문구\n'
  || E'오늘 새로 추가된 SSS 카드(지두두 · 주하랑)를, 카드 추가 전부터 켜 두셨던\n'
  || E'화면에서 받으실 때 떴던 문구입니다.\n'
  || E'이 경우에도 카드는 정상 지급되었습니다. 서버 기록상 실패 건은 없습니다.\n'
  || E'도감에서 확인해 주시고, 다시 받으려 시도하지 않으셔도 됩니다.\n\n'
  || E'━━━━━━━━━━━━━━\n\n'
  || E'🎁 보상 (이미 인벤토리에 지급 완료)\n'
  || E'  · SSS 카드 선택권 1장\n'
  || E'  · 랜덤 특성 변경권 2장\n\n'
  || E'오류로 같은 카드를 두 장 받으신 경우, 그 카드는 회수하지 않았습니다.\n'
  || E'중복 카드는 강화 재료로 그대로 사용하실 수 있습니다.\n\n'
  || E'새로고침을 한 번 해 주시면 가장 최신 상태로 이용하실 수 있습니다.\n'
  || E'이상한 점이 있으면 언제든 말씀해 주세요.',
  0
from public.gacha_s2_player_states p
where not exists (
  select 1 from public.gacha_s2_mailbox m
  where m.user_id = p.user_id and m.event_key = 'sss-selector-error-notice-20260810'
);

-- 2) 오류가 실제로 발생한 계정에 추가분 안내
insert into public.gacha_s2_mailbox (user_id, event_key, category, title, body, points)
select g.user_id,
  'sss-selector-victim-extra-20260810',
  'SYSTEM',
  '🎁 SSS 카드 선택권 추가 보상 (오류 발생 계정)',
  E'회원님 계정에서 카드 선택권이 한 번에 두 장 소모된 기록이 확인되었습니다.\n\n'
  || E'전체 보상과 별도로 SSS 카드 선택권 1장을 추가 지급해 드렸습니다.\n'
  || E'(전체 보상 1장 + 추가 1장 = SSS 카드 선택권 총 2장)\n\n'
  || E'이미 인벤토리에 반영되어 있습니다. 별도 수령 절차는 없습니다.\n\n'
  || E'오류로 두 장이 된 카드는 회수하지 않았습니다.\n'
  || E'중복 카드는 강화 재료로 그대로 사용하실 수 있습니다.\n\n'
  || E'불편을 드려 죄송합니다.',
  0
from public.gacha_s2_sss_selector_victim_grant_20260810 g
where not exists (
  select 1 from public.gacha_s2_mailbox m
  where m.user_id = g.user_id and m.event_key = 'sss-selector-victim-extra-20260810'
);

do $$
declare
  v_states integer;
  v_all integer;
  v_victims integer;
  v_victim_mail integer;
  v_points integer;
begin
  select count(*) into v_states from public.gacha_s2_player_states;
  select count(*) into v_all from public.gacha_s2_mailbox
  where event_key = 'sss-selector-error-notice-20260810';
  if v_all <> v_states then
    raise exception 'notice coverage mismatch: % mails vs % states', v_all, v_states;
  end if;

  select count(*) into v_victims from public.gacha_s2_sss_selector_victim_grant_20260810;
  select count(*) into v_victim_mail from public.gacha_s2_mailbox
  where event_key = 'sss-selector-victim-extra-20260810';
  if v_victim_mail <> v_victims then
    raise exception 'victim notice mismatch: % mails vs % victims', v_victim_mail, v_victims;
  end if;

  -- 보상은 이미 인벤토리에 넣었다. 우편에 포인트가 붙어 있으면 이중 지급이 된다.
  select count(*) into v_points from public.gacha_s2_mailbox
  where event_key in ('sss-selector-error-notice-20260810', 'sss-selector-victim-extra-20260810')
    and points <> 0;
  if v_points > 0 then
    raise exception 'notice mail must not carry points (% rows)', v_points;
  end if;
end;
$$;
