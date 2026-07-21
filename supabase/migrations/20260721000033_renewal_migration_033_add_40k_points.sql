-- Give 40,000 points to all users except the streamer "손실바"
begin;

update public.gacha_s2_player_states
set points = points + 40000,
    revision = revision + 1
where user_id in (
  select id
  from public.gacha_s2_accounts
  where is_streamer = true
    and nickname <> '손실바'
);

commit;
