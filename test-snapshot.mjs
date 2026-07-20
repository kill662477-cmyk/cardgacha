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
  const { data: usersData } = await supabaseAdmin.auth.admin.listUsers();
  if (!usersData.users || usersData.users.length === 0) return console.log('No users at all');
  
  const validUser = usersData.users[0];
  console.log('Testing with auth user:', validUser.id);
  
  const { data: accountId, error: accountError } = await supabaseAdmin.rpc('gacha_s2_resolve_auth_account', {
    p_auth_user_id: validUser.id,
  });
  
  if (accountError || !accountId) return console.log('Account resolve error:', accountError, accountId);
  
  console.log('Game Account ID:', accountId);
  
  const { data, error } = await supabaseAdmin.rpc('gacha_s2_get_player_snapshot', { p_user_id: accountId });
  console.log('Snapshot Error:', error);
  if (data) {
    console.log('Snapshot supportItems:', data.supportItems);
  }
}

run();
