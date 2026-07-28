import { createClient } from '@supabase/supabase-js';
import cards from '../_shared/generated/cards.json' with { type: 'json' };
import {
  buildGuildApplicantProfile,
  createServerCommandRouter,
} from '../_shared/generated/server-command-router.js';

const MAX_BODY_BYTES = 128 * 1024;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

function json(req: Request, body: unknown, status = 200, requestId?: string) {
  const responseBody = requestId
    && body
    && typeof body === 'object'
    && !Array.isArray(body)
    && (body as Record<string, unknown>).ok === false
    ? { ...(body as Record<string, unknown>), requestId }
    : body;
  return Response.json(responseBody, {
    status,
    headers: {
      ...corsHeaders(req),
      'Cache-Control': 'no-store',
      ...(requestId ? { 'X-Request-ID': requestId } : {}),
    },
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

function safeErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error ?? 'unknown');
  return message.slice(0, 500);
}

async function persistFailure(
  supabaseAdmin: ReturnType<typeof adminClient>,
  failure: Record<string, unknown>,
) {
  const { error } = await supabaseAdmin.from('gacha_s2_command_failures').insert(failure);
  if (error) {
    console.error('FAILURE_AUDIT_WRITE_FAILED', {
      requestId: failure.request_id,
      code: error.code,
    });
  }
}

function shouldPersistCommandFailure(code: unknown) {
  return new Set([
    'INTERNAL_ERROR',
    'VERSION_CONFLICT',
    'IDEMPOTENCY_KEY_REUSED',
    'RATE_LIMITED',
  ]).has(String(code ?? ''));
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
  const requestId = crypto.randomUUID();
  const respond = (body: unknown, status = 200) => json(req, body, status, requestId);
  const origin = req.headers.get('origin');
  if (origin && !allowedOrigins().has(origin)) return respond({ ok: false, code: 'FORBIDDEN', message: '허용되지 않은 출처입니다.' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'POST') return respond({ ok: false, code: 'VALIDATION_FAILED', message: 'POST 요청만 허용됩니다.' }, 405);
  const contentLength = Number(req.headers.get('content-length') ?? 0);
  if (contentLength > MAX_BODY_BYTES) return respond({ ok: false, code: 'VALIDATION_FAILED', message: '요청이 너무 큽니다.' }, 413);

  const jwt = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return respond({ ok: false, code: 'AUTH_REQUIRED', message: '로그인이 필요합니다.' }, 401);
  
  const supabaseAdmin = adminClient();
  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(jwt);

  if (userError || !user?.id) {
    return respond({ ok: false, code: 'AUTH_REQUIRED', message: '로그인이 필요합니다.' }, 401);
  }

  let body: Record<string, unknown>;
  try {
    const raw = await readLimitedText(req);
    body = JSON.parse(raw);
  } catch {
    return respond({ ok: false, code: 'VALIDATION_FAILED', message: 'JSON 요청이 올바르지 않습니다.' }, 400);
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
    return respond({ ok: false, code: 'AUTH_REQUIRED', message: '게임 계정 연결이 필요합니다.' }, 401);
  }
  const userId = String(accountId);
  const logFailure = async (
    requestKind: string,
    errorCode: string,
    httpStatus: number,
    errorSource: string,
    error: unknown,
    command?: Record<string, unknown>,
  ) => persistFailure(supabaseAdmin, {
    request_id: requestId,
    auth_user_id: user.id,
    user_id: userId,
    request_kind: requestKind,
    command_id: typeof command?.commandId === 'string' ? command.commandId : null,
    command_type: typeof command?.type === 'string' ? command.type : null,
    error_code: errorCode,
    http_status: httpStatus,
    error_source: errorSource,
    error_message: safeErrorMessage(error),
  });
  let internalCommandError: unknown = null;
  const router = createServerCommandRouter({
    gateway,
    cards,
    onError: (error: unknown) => {
      internalCommandError = error
        && typeof error === 'object'
        && 'reason' in error
        ? (error as Record<string, unknown>).reason
        : error;
    },
  });

  if (body.kind === 'snapshot') {
    try {
      const snapshot = await router.loadSnapshot(userId);
      return respond({ ok: true, serverTime: Date.now(), snapshot });
    } catch (e: any) {
      await logFailure('snapshot', 'INTERNAL_ERROR', 500, 'snapshot', e);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '계정 상태를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'worldBossStatus') {
    try {
      const status = await gateway.rpc('gacha_s2_get_world_boss_status', {
        p_user_id: userId,
        p_event_id: typeof body.eventId === 'string' ? body.eventId : null,
      });
      return respond({ ok: true, serverTime: Date.now(), status });
    } catch (error) {
      await logFailure('worldBossStatus', 'INTERNAL_ERROR', 500, 'worldBossStatus', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '월드보스 상태를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'lottoState') {
    try {
      const state = await gateway.rpc('gacha_s2_get_lotto_state_v2', { p_user_id: userId });
      if (state?.ok === false) return respond(state, statusFor(state));
      return respond({ ok: true, serverTime: Date.now(), state });
    } catch (error) {
      await logFailure('lottoState', 'INTERNAL_ERROR', 500, 'lottoState', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '로또 정보를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'powerRanking') {
    try {
      const ranking = await router.getPowerRanking(userId);
      return respond({ ok: true, serverTime: Date.now(), ranking });
    } catch (error) {
      await logFailure('powerRanking', 'INTERNAL_ERROR', 500, 'powerRanking', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '전투력 랭킹을 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'guildState') {
    try {
      const state = await gateway.rpc('gacha_s2_get_guild_state', {
        p_user_id: userId,
        p_guild_id: typeof body.guildId === 'string' ? body.guildId : null,
      }) as Record<string, any>;
      if (state?.weekly && state?.membership) {
        const personal = await gateway.rpc('gacha_s2_get_guild_weekly_member_progress', {
          p_user_id: userId,
        }) as Record<string, any>;
        state.weekly = {
          ...state.weekly,
          myContributions: Array.isArray(personal?.goals) ? personal.goals : [],
        };
      }
      return respond({ ok: true, serverTime: Date.now(), state });
    } catch (error) {
      await logFailure('guildState', 'INTERNAL_ERROR', 500, 'guildState', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '길드 정보를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'guildApplicantProfile') {
    if (typeof body.targetUserId !== 'string' || !UUID_PATTERN.test(body.targetUserId)) {
      return respond({ ok: false, code: 'VALIDATION_FAILED', message: '신청자 정보가 올바르지 않습니다.' }, 400);
    }
    try {
      const profile = await gateway.rpc('gacha_s2_get_guild_applicant_profile', {
        p_user_id: userId,
        p_target_user_id: body.targetUserId,
      }) as Record<string, unknown>;
      if (profile?.ok === false) return respond(profile, statusFor(profile));
      return respond({
        ok: true,
        serverTime: Date.now(),
        profile: buildGuildApplicantProfile(profile, cards),
      });
    } catch (error) {
      await logFailure('guildApplicantProfile', 'INTERNAL_ERROR', 500, 'guildApplicantProfile', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '신청자 정보를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'guildMemberProfile') {
    if (typeof body.targetUserId !== 'string' || !UUID_PATTERN.test(body.targetUserId)) {
      return respond({ ok: false, code: 'VALIDATION_FAILED', message: '길드원 정보가 올바르지 않습니다.' }, 400);
    }
    try {
      const profile = await gateway.rpc('gacha_s2_get_guild_member_profile', {
        p_user_id: userId,
        p_target_user_id: body.targetUserId,
      }) as Record<string, unknown>;
      if (profile?.ok === false) return respond(profile, statusFor(profile));
      return respond({
        ok: true,
        serverTime: Date.now(),
        profile: buildGuildApplicantProfile(profile, cards),
      });
    } catch (error) {
      await logFailure('guildMemberProfile', 'INTERNAL_ERROR', 500, 'guildMemberProfile', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '길드원 정보를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'guildRaidStatus') {
    try {
      const status = await gateway.rpc('gacha_s2_get_guild_raid_status', { p_user_id: userId });
      return respond({ ok: true, serverTime: Date.now(), status });
    } catch (error) {
      await logFailure('guildRaidStatus', 'INTERNAL_ERROR', 500, 'guildRaidStatus', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '길드 레이드 정보를 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'bridgeStatus') {
    try {
      const status = await gateway.rpc('gacha_s2_get_bridge_status', { p_user_id: userId });
      return respond({ ok: true, serverTime: Date.now(), status });
    } catch (error) {
      await logFailure('bridgeStatus', 'INTERNAL_ERROR', 500, 'bridgeStatus', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: 'API 연동 권한을 확인하지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'mailbox') {
    try {
      const mailbox = await gateway.rpc('gacha_s2_get_mailbox', {
        p_user_id: userId,
        p_limit: 50,
      });
      return respond({ ok: true, serverTime: Date.now(), mailbox });
    } catch (error) {
      await logFailure('mailbox', 'INTERNAL_ERROR', 500, 'mailbox', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '우편함을 불러오지 못했습니다.' }, 500);
    }
  }
  if (body.kind === 'mailboxRead') {
    if (typeof body.mailId !== 'string' || !UUID_PATTERN.test(body.mailId)) {
      return respond({ ok: false, code: 'VALIDATION_FAILED', message: '우편 정보가 올바르지 않습니다.' }, 400);
    }
    try {
      const result = await gateway.rpc('gacha_s2_mark_mail_read', {
        p_user_id: userId,
        p_mail_id: body.mailId,
      });
      if (result?.ok === false) return respond(result, statusFor(result));
      return respond({ ok: true, serverTime: Date.now(), result });
    } catch (error) {
      await logFailure('mailboxRead', 'INTERNAL_ERROR', 500, 'mailboxRead', error);
      return respond({ ok: false, code: 'INTERNAL_ERROR', message: '우편 읽음 처리를 완료하지 못했습니다.' }, 500);
    }
  }
  if (body.kind !== 'command' || !body.command) {
    return respond({ ok: false, code: 'VALIDATION_FAILED', message: '요청 종류가 올바르지 않습니다.' }, 400);
  }
  const result = await router.execute(userId, body.command);
  const status = statusFor(result);
  if (result?.ok === false && shouldPersistCommandFailure(result.code)) {
    await logFailure(
      'command',
      String(result.code),
      status,
      'commandRouter',
      internalCommandError ?? result.message ?? result.code,
      body.command as Record<string, unknown>,
    );
  }
  return respond(result, status);
});
