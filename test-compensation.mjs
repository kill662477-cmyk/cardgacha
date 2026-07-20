import fs from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const envText = fs.readFileSync('.env.local', 'utf8');
const env = envText.split('\n').reduce((acc, line) => {
  const [k, v] = line.split('=');
  if(k && v) acc[k] = v.replace(/['"\r]/g, '');
  return acc;
}, {});

const supabaseAdmin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);

async function run() {
  const { error } = await supabaseAdmin.rpc('gacha_s2_test_execute_sql', {
    sql: `
      UPDATE public.gacha_s2_player_states
      SET points = points + 10000,
          revision = revision + 1,
          updated_at = now();
    `
  });
  
  if (error) {
    console.error('Failed to distribute compensation via RPC, will do via CLI migration...', error);
  } else {
    console.log('Compensation 10000 points distributed successfully to all players!');
  }
}
run();
