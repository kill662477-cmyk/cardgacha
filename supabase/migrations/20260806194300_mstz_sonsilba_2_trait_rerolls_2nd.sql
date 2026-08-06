-- Mstz_손실바 계정 랜덤특성변경권 2장 추가 지급 (2차)

begin;

create table if not exists public.gacha_s2_mstz_sonsilba_2_trait_rerolls_2nd_20260806 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_mstz_sonsilba_2_trait_rerolls_2nd_20260806 (user_id)
select id from public.gacha_s2_accounts
where nickname = 'Mstz_손실바'
on conflict (user_id) do nothing;

with pending as (
  select user_id from public.gacha_s2_mstz_sonsilba_2_trait_rerolls_2nd_20260806
  where granted = false
)
update public.gacha_s2_player_states state
set support_items = coalesce(support_items, '{}'::jsonb) ||
                    jsonb_build_object(
                      'traitReroll', coalesce((support_items->>'traitReroll')::integer, 0) + 2
                    ),
    revision = revision + 1,
    updated_at = now()
from pending
where state.user_id = pending.user_id;

update public.gacha_s2_mstz_sonsilba_2_trait_rerolls_2nd_20260806
set granted = true, granted_at = now()
where granted = false;

revoke all on table public.gacha_s2_mstz_sonsilba_2_trait_rerolls_2nd_20260806
  from public, anon, authenticated;

commit;
