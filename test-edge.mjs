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
  let { data: { user }, error: authError } = await supabase.auth.signInWithPassword({
    email: 'test2@example.com',
    password: 'password123'
  });
  
  if (authError) {
    const signupRes = await supabase.auth.signUp({
      email: 'test2@example.com',
      password: 'password123'
    });
    if (signupRes.error) {
      console.log('Signup Error:', signupRes.error.message);
      return;
    }
    user = signupRes.data.user;
  }
  
  console.log('User signed in:', user?.id);
  const { data, error } = await supabase.functions.invoke('game-command', {
    body: { kind: 'snapshot' }
  });
  
  console.log('Function Data:', data);
  console.log('Function Error:', error);
}

run();
