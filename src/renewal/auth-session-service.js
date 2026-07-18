function exchangeEndpoint(projectUrl) {
  return `${projectUrl.replace(/\/+$/, '')}/functions/v1/session-exchange`;
}

export function createAuthSessionService(options = {}) {
  const projectUrl = String(options.projectUrl ?? '').trim();
  const publishableKey = String(options.publishableKey ?? '').trim();
  const auth = options.auth;
  const fetchImpl = options.fetch ?? globalThis.fetch;
  if (!/^https:\/\/[^/]+$/.test(projectUrl) || !publishableKey) throw new Error('Supabase public configuration required.');
  if (!auth || typeof auth.getSession !== 'function' || typeof auth.signInAnonymously !== 'function' || typeof auth.signOut !== 'function') throw new Error('Supabase Auth client required.');

  async function ensureSession() {
    const current = await auth.getSession();
    if (current?.data?.session?.access_token) return current.data.session;
    const created = await auth.signInAnonymously();
    if (created?.error || !created?.data?.session?.access_token) throw new Error('ANONYMOUS_AUTH_FAILED');
    return created.data.session;
  }

  // 공통 바인딩 POST. body 필드(loginKey 또는 soopExchange)만 다르다.
  async function postExchange(body) {
    const session = await ensureSession();
    const response = await fetchImpl(exchangeEndpoint(projectUrl), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey: publishableKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    let payload = null;
    try { payload = await response.json(); } catch { /* normalized below */ }
    if (!response.ok || !payload?.ok) return payload ?? { ok: false, code: 'INTERNAL_ERROR' };
    return { ...payload, session };
  }

  async function signInWithLoginKey(loginKey) {
    const key = String(loginKey ?? '').trim();
    if (key.length < 16 || key.length > 256) return { ok: false, code: 'INVALID_CREDENTIALS' };
    return postExchange({ loginKey: key });
  }

  // Phase 2: SOOP 숲 로그인. OAuth 콜백이 fragment로 전달한 일회성 exchange 코드로
  // 익명 세션을 soop_id 계정에 바인딩한다.
  async function signInWithSoopExchange(exchangeCode) {
    const code = String(exchangeCode ?? '').trim();
    if (code.length < 16 || code.length > 256) return { ok: false, code: 'INVALID_CREDENTIALS' };
    return postExchange({ soopExchange: code });
  }

  async function getAccessToken() {
    const result = await auth.getSession();
    return result?.data?.session?.access_token ?? null;
  }

  async function signOut() {
    try {
      const result = await auth.signOut({ scope: 'local' });
      if (result?.error) return { ok: false, code: 'SIGN_OUT_FAILED' };
      return { ok: true };
    } catch {
      return { ok: false, code: 'SIGN_OUT_FAILED' };
    }
  }

  return { ensureSession, signInWithLoginKey, signInWithSoopExchange, getAccessToken, signOut };
}
