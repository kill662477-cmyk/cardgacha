import { createClient } from '@supabase/supabase-js';
import cards from '../_shared/generated/cards.json' with { type: 'json' };
import { createServerCommandRouter } from '../_shared/generated/server-command-router.js';

const MAX_BODY_BYTES = 128 * 1024;

function allowedOrigins() {
  return new Set((Deno.env.get('GAME_ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean));
}

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin');
  const allowed = allowedOrigins();
  if (!origin || !allowed.has(origin)) return { Vary: 'Origin' };
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(req: Request, body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders(req), 'Cache-Control': 'no-store' },
  });
}

function statusFor(body: Record<string, unknown>) {
  if (body?.ok !== false) return 200;
  if (body.code === 'AUTH_REQUIRED') return 401;
  if (body.code === 'FORBIDDEN') return 403;
  if (body.code === 'RATE_LIMITED') return 429;
  if (body.code === 'VERSION_CONFLICT') return 409;
  if (body.code === 'VALIDATION_FAILED') return 400;
  return 200;
}

function adminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

async function readLimitedText(req: Request) {
  if (!req.body) return '';
  const reader = req.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let text = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new Error('BODY_TOO_LARGE');
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  if (origin && !allowedOrigins().has(origin)) return json(req, { ok: false, code: 'FORBIDDEN', message: '허용되지 않은 출처입니다.' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, code: 'VALIDATION_FAILED', message: 'POST 요청만 허용됩니다.' }, 405);
  const contentLength = Number(req.headers.get('content-length') ?? 0);
  if (contentLength > MAX_BODY_BYTES) return json(req, { ok: false, code: 'VALIDATION_FAILED', message: '요청이 너무 큽니다.' }, 413);

  const jwt = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return json(req, { ok: false, code: 'AUTH_REQUIRED', message: '로그인이 필요합니다.' }, 401);
  
  const supabaseAdmin = adminClient();
  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(jwt);

  if (userError || !user?.id) {
    return json(req, { ok: false, code: 'AUTH_REQUIRED', message: '로그인이 필요합니다.' }, 401);
  }

  let body: Record<string, unknown>;
  try {
    const raw = await readLimitedText(req);
    body = JSON.parse(raw);
  } catch {
    return json(req, { ok: false, code: 'VALIDATION_FAILED', message: 'JSON 요청이 올바르지 않습니다.' }, 400);
  }

  const gateway = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      const { data, error } = await supabaseAdmin.rpc(name, args);
      if (error) throw new Error(`RPC_FAILED:${name}:${error.code ?? 'unknown'}`);
      return data;
    },
    activeBalanceVersion: async () => {
      const { data, error } = await supabaseAdmin
        .from('gacha_s2_balance_versions')
        .select('version')
        .eq('active', true)
        .single();
      if (error) throw new Error(`BALANCE_LOOKUP_FAILED:${error.code ?? 'unknown'}`);
      return data?.version ?? null;
    },
  };
  const { data: accountId, error: accountError } = await supabaseAdmin.rpc('gacha_s2_resolve_auth_account', {
    p_auth_user_id: user.id,
  });
  if (accountError || !accountId) {
    return json(req, { ok: false, code: 'AUTH_REQUIRED', message: '게임 계정 연결이 필요합니다.' }, 401);
  }
  const userId = String(accountId);
  const router = createServerCommandRouter({ gateway, cards });

  if (body.kind === 'snapshot') {
    try {
      const snapshot = await router.loadSnapshot(userId);
      return json(req, { ok: true, serverTime: Date.now(), snapshot });
    } catch {
      return json(req, { ok: false, code: 'INTERNAL_ERROR', message: '계정 상태를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'worldBossStatus') {
    try {
      const status = await gateway.rpc('gacha_s2_get_world_boss_status', {
        p_user_id: userId,
        p_event_id: typeof body.eventId === 'string' ? body.eventId : null,
      });
      return json(req, { ok: true, serverTime: Date.now(), status });
    } catch {
      return json(req, { ok: false, code: 'INTERNAL_ERROR', message: '월드보스 상태를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'powerRanking') {
    try {
      const ranking = await router.getPowerRanking(userId);
      return json(req, { ok: true, serverTime: Date.now(), ranking });
    } catch {
      return json(req, { ok: false, code: 'INTERNAL_ERROR', message: '전투력 랭킹을 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'bridgeStatus') {
    try {
      const status = await gateway.rpc('gacha_s2_get_bridge_status', { p_user_id: userId });
      return json(req, { ok: true, serverTime: Date.now(), status });
    } catch {
      return json(req, { ok: false, code: 'INTERNAL_ERROR', message: 'API 연동 권한을 확인하지 못했습니다.' }, 500);
    }
  }
  if (body.kind !== 'command' || !body.command) {
    return json(req, { ok: false, code: 'VALIDATION_FAILED', message: '요청 종류가 올바르지 않습니다.' }, 400);
  }
  const result = await router.execute(userId, body.command);
  return json(req, result, statusFor(result));
});
