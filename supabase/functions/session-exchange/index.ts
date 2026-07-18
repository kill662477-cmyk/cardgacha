import { createSupabaseContext } from '@supabase/server';

const MAX_BODY_BYTES = 4 * 1024;

function allowedOrigins() {
  return new Set((Deno.env.get('GAME_ALLOWED_ORIGINS') ?? '').split(',').map((value) => value.trim()).filter(Boolean));
}

function headers(req: Request): Record<string, string> {
  const origin = req.headers.get('origin');
  const allowed = allowedOrigins();
  return {
    ...(origin && allowed.has(origin) ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Cache-Control': 'no-store',
    Vary: 'Origin',
  };
}

function json(req: Request, body: unknown, status = 200) {
  return Response.json(body, { status, headers: headers(req) });
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function hmac(value: string, secret: string) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  if (origin && !allowedOrigins().has(origin)) return json(req, { ok: false, code: 'FORBIDDEN' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(req) });
  if (req.method !== 'POST') return json(req, { ok: false, code: 'INVALID_REQUEST' }, 405);
  if (Number(req.headers.get('content-length') ?? 0) > MAX_BODY_BYTES) return json(req, { ok: false, code: 'INVALID_REQUEST' }, 413);

  const pepper = Deno.env.get('AUTH_RATE_LIMIT_PEPPER');
  if (!pepper || pepper.length < 32) return json(req, { ok: false, code: 'SERVER_MISCONFIGURED' }, 503);
  const { data: context, error: authError } = await createSupabaseContext(req, { auth: 'user' });
  if (authError || !context?.userClaims?.id) return json(req, { ok: false, code: 'AUTH_REQUIRED' }, 401);

  let raw: string;
  try {
    raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) throw new Error('too large');
  } catch {
    return json(req, { ok: false, code: 'INVALID_REQUEST' }, 400);
  }
  let parsed: { loginKey?: unknown; soopExchange?: unknown } = {};
  try { parsed = JSON.parse(raw) ?? {}; } catch { /* generic failure */ }

  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  const clientAddress = forwarded || req.headers.get('cf-connecting-ip') || 'unknown';

  // Phase 2: SOOP 숲 로그인 분기. soopExchange 코드가 오면 soop_id 바인딩 RPC로.
  const soopExchange = String(parsed.soopExchange ?? '').trim();
  if (soopExchange && soopExchange.length >= 16 && soopExchange.length <= 256) {
    const rateKey = await hmac(clientAddress, pepper);
    const { data, error } = await (context.supabaseAdmin as any).rpc('gacha_s2_bind_soop_session', {
      p_auth_user_id: context.userClaims.id,
      p_exchange_code: soopExchange,
      p_rate_key: rateKey,
    });
    if (error) return json(req, { ok: false, code: 'INTERNAL_ERROR' }, 500);
    if (!data?.ok) {
      const status = data?.code === 'RATE_LIMITED' ? 429 : data?.code === 'AUTH_REQUIRED' ? 401 : 401;
      return json(req, data, status);
    }
    return json(req, data);
  }

  const loginKey = String(parsed.loginKey ?? '').trim();
  if (loginKey.length < 16 || loginKey.length > 256) return json(req, { ok: false, code: 'INVALID_CREDENTIALS' }, 401);

  const [keyHash, rateKey] = await Promise.all([sha256(loginKey), hmac(clientAddress, pepper)]);
  const { data, error } = await (context.supabaseAdmin as any).rpc('gacha_s2_bind_auth_session', {
    p_auth_user_id: context.userClaims.id,
    p_login_key_hash: keyHash,
    p_rate_key: rateKey,
  });
  if (error) return json(req, { ok: false, code: 'INTERNAL_ERROR' }, 500);
  if (!data?.ok) {
    const status = data?.code === 'RATE_LIMITED' ? 429 : data?.code === 'AUTH_REQUIRED' ? 401 : 401;
    return json(req, data, status);
  }
  return json(req, data);
});
