import fs from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const envText = fs.readFileSync('.env.local', 'utf8');
const env = envText.split('\n').reduce((acc, line) => {
  const [k, v] = line.split('=');
  if(k && v) acc[k] = v.replace(/['"\r]/g, '');
  return acc;
}, {});

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

async function run() {
  const { data: { user }, error: authError } = await supabase.auth.signInWithPassword({
    email: 'test@example.com',
    password: 'password123'
  });
  if (authError) {
    console.log('Auth Error:', authError.message);
    return;
  }
  
  const { data, error } = await supabase.functions.invoke('game-command', {
    body: { kind: 'snapshot' }
  });
  
  console.log('Function Data:', data);
  console.log('Function Error:', error);
}

run();
