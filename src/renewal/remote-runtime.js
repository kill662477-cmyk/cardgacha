import { createClient } from '../vendor/supabase.js';
import { createAuthSessionService } from './auth-session-service.js?v=202607241835';
import { createSupabaseGameService } from './supabase-game-service.js?v=202607290900';

export function readRemoteConfig(source = globalThis.__CARD_GACHA_CONFIG__) {
  if (globalThis.location && new URLSearchParams(globalThis.location.search).has('local')) {
    return { enabled: false, projectUrl: '', publishableKey: '' };
  }
  const projectUrl = String(source?.supabaseUrl ?? '').trim();
  const publishableKey = String(source?.supabasePublishableKey ?? '').trim();
  return {
    enabled: /^https:\/\/[^/]+$/.test(projectUrl) && Boolean(publishableKey),
    projectUrl,
    publishableKey,
  };
}

export function createRemoteRuntime(config = readRemoteConfig(), options = {}) {
  if (!config.enabled) return null;
  const supabase = (options.createClient ?? createClient)(config.projectUrl, config.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  });
  const auth = createAuthSessionService({
    projectUrl: config.projectUrl,
    publishableKey: config.publishableKey,
    auth: supabase.auth,
    fetch: options.fetch,
  });
  const game = createSupabaseGameService({
    projectUrl: config.projectUrl,
    publishableKey: config.publishableKey,
    getAccessToken: auth.getAccessToken,
    fetch: options.fetch,
    readRpc: (name, args) => supabase.rpc(name, args),
  });
  async function getLiveEvents() {
    const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from('gacha_s2_live_events')
      .select('id,event_type,nickname,card_id,member,rarity,enhancement,event_rank,points,lotto_round_id,created_at')
      .gte('created_at', cutoff)
      .order('created_at', { ascending: false })
      .limit(20);
    if (error) throw new Error(`LIVE_EVENTS_FAILED:${error.code ?? 'unknown'}`);
    return data ?? [];
  }
  function subscribeLiveEvents(onEvent) {
    if (typeof onEvent !== 'function') return () => {};
    const channel = supabase
      .channel('gacha-s2-live-events')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'gacha_s2_live_events',
      }, (payload) => onEvent(payload.new))
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }
  return {
    supabase, auth, game, getLiveEvents, subscribeLiveEvents,
    now: () => Date.now(), random: () => Math.random(),
  };
}

export function mergeServerSnapshot(snapshot, clientCache = {}) {
  const activeRunStage = snapshot.adventureRun?.active ? snapshot.adventureRun.currentStage : null;
  return {
    ...snapshot,
    worldBoss: snapshot.worldBoss?.eventId ? snapshot.worldBoss : clientCache.worldBoss,
    currentStage: Math.max(1, Math.min(100, Number(activeRunStage ?? clientCache.currentStage ?? snapshot.clearedStage + 1) || 1)),
    autoBattle: Boolean(clientCache.autoBattle),
    soundEnabled: clientCache.soundEnabled !== false,
  };
}
