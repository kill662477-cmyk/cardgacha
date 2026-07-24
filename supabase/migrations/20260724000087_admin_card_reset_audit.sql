-- Records one-off administrator card-reset operations for recovery and review.
create table if not exists public.gacha_s2_admin_card_reset_audit (
  operation_key text primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete restrict,
  nickname text not null,
  formation_before text[] not null,
  formation_cards_before jsonb not null,
  reset_cards_before jsonb not null,
  reset_count integer not null check (reset_count >= 0),
  created_at timestamptz not null default now()
);

revoke all on table public.gacha_s2_admin_card_reset_audit
  from public, anon, authenticated;
