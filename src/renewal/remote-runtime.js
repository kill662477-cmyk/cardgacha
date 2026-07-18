import { createClient } from '../vendor/supabase.js';
import { createAuthSessionService } from './auth-session-service.js';
import { createSupabaseGameService } from './supabase-game-service.js';

export function readRemoteConfig(source = globalThis.__CARD_GACHA_CONFIG__) {
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
  });
  function subscribeWorldBoss(onChange) {
    if (typeof onChange !== 'function') return () => {};
    const channel = supabase
      .channel('gacha-s2-world-boss-events')
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'gacha_s2_world_boss_events',
      }, () => onChange())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }
  async function getLiveEvents() {
    const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from('gacha_s2_live_events')
      .select('id,event_type,nickname,card_id,member,rarity,enhancement,created_at')
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
    supabase, auth, game, subscribeWorldBoss, getLiveEvents, subscribeLiveEvents,
    now: () => Date.now(), random: () => Math.random(),
  };
}

export function mergeServerSnapshot(snapshot, clientCache = {}) {
  return {
    ...snapshot,
    worldBoss: snapshot.worldBoss?.eventId ? snapshot.worldBoss : clientCache.worldBoss,
    currentStage: Math.max(1, Math.min(50, Number(clientCache.currentStage ?? snapshot.clearedStage + 1) || 1)),
    autoBattle: Boolean(clientCache.autoBattle),
    soundEnabled: clientCache.soundEnabled !== false,
  };
}
