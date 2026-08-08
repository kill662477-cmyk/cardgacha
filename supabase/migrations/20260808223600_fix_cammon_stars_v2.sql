-- 우편 본문 오타 수정 (V1 -> V2)

begin;

update public.gacha_s2_mailbox
set body = replace(body, '캄몬스타즈 V1 가즈아', '캄몬스타즈 V2 가즈아')
where title = '🌟 [축하] K-중만컵 캄몬스타즈 5:2 대승리 기념 특별 축하금! 🌟';

commit;
