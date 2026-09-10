// إعدادات Supabase
// ضع بيانات مشروعك هنا من Supabase Dashboard > Project Settings > API
// لا تضع service_role key في الواجهة الأمامية أبداً.
const SUPABASE_URL = "https://nkkkhwybvsvsrnivmqyy.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5ra2tod3lidnN2c3JuaXZtcXl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgzMTQ5NDIsImV4cCI6MjEwMzg5MDk0Mn0.a6z5LENrZswHQJjAQ5o1v3COoqP2oHkII2FzDr89cMc";


const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storage: window.localStorage }
});


