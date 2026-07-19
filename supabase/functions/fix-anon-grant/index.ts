import * as postgres from 'https://deno.land/x/postgres@v0.17.0/mod.ts';

Deno.serve(async (req) => {
  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL');
    if (!dbUrl) throw new Error('No DB URL');
    const pool = new postgres.Pool(dbUrl, 1, true);
    const conn = await pool.connect();
    
    await conn.queryObject(`
      grant select on table public.gacha_s2_live_events to anon;
      drop policy if exists gacha_s2_live_events_recent_read on public.gacha_s2_live_events;
      create policy gacha_s2_live_events_recent_read
        on public.gacha_s2_live_events
        for select
        to authenticated, anon
        using (created_at >= now() - interval '10 minutes');
    `);
    
    conn.release();
    return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: err.message }), { status: 500 });
  }
});
