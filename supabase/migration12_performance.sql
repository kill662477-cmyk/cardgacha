-- Broadcast traffic hardening: ranking, bulk grants, and hot read indexes.

alter table public.gacha_users alter column points set default 5000;

create index if not exists idx_gacha_users_ranking
  on public.gacha_users (ranking_score desc, id asc);
create index if not exists idx_gacha_announcements_recent
  on public.gacha_announcements (created_at desc);

-- Returns only the visible top 50 and the requesting user's rank.
create or replace function public.gacha_get_ranking(p_user_id uuid)
returns table(rankings jsonb, my_rank integer, my_nickname text, my_score integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id, nickname, ranking_score
    from public.gacha_users
    where id = p_user_id and nickname <> '플로우검증봇'
  ), top_rows as (
    select row_number() over (order by ranking_score desc, id asc)::integer as rank,
      nickname, ranking_score
    from (
      select id, nickname, ranking_score
      from public.gacha_users
      where nickname <> '플로우검증봇'
      order by ranking_score desc, id asc
      limit 50
    ) ordered
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object('rank', rank, 'nickname', nickname, 'score', ranking_score) order by rank)
      from top_rows
    ), '[]'::jsonb),
    (
      select count(*)::integer + 1
      from public.gacha_users ranked
      where ranked.nickname <> '플로우검증봇'
        and (ranked.ranking_score > me.ranking_score
          or (ranked.ranking_score = me.ranking_score and ranked.id < me.id))
    ),
    me.nickname,
    me.ranking_score
  from me;
$$;

-- Atomic all-account grant. No read-then-write race and one DB request only.
create or replace function public.gacha_grant_all_points(p_amount integer)
returns table(updated_count integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  if p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid grant amount';
  end if;

  update public.gacha_users
  set points = public.gacha_users.points + p_amount
  where public.gacha_users.id is not null;
  get diagnostics v_updated = row_count;
  return query select v_updated;
end;
$$;

revoke all on function public.gacha_get_ranking(uuid) from public;
revoke all on function public.gacha_grant_all_points(integer) from public;
grant execute on function public.gacha_get_ranking(uuid) to service_role;
grant execute on function public.gacha_grant_all_points(integer) to service_role;
