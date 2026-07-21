import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://rljvzultuyiudhjjfotg.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsanZ6dWx0dXlpdWRoampmb3RnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MTY3NTM2NSwiZXhwIjoyMDk3MjUxMzY1fQ.MXfVQ5emn6H2NC2ZT8T_XGchWJg1XiidjkAYscjBpI8';

const supabase = createClient(supabaseUrl, supabaseKey);

async function check() {
  const { data, error } = await supabase
    .from('gacha_s2_live_events')
    .select('*')
    .eq('event_type', 'nine_star_success')
    .order('created_at', { ascending: true });

  if (error) {
    console.error(error);
  } else {
    console.log(`Total 9-star success events: ${data.length}`);
    if (data.length > 0) {
      console.log('First 9-star event:');
      console.log(data[0]);
      console.log('Last 9-star event:');
      console.log(data[data.length - 1]);
    }
  }
}

check();
