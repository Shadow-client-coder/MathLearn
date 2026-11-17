import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return Response.json({ error: 'Chỉ hỗ trợ POST.' }, { status: 405, headers: cors });
  try {
    const { username, password } = await request.json();
    const expectedUser = Deno.env.get('ADMIN_USERNAME') || 'Admin';
    const expectedPassword = Deno.env.get('ADMIN_PASSWORD');
    if (!expectedPassword) return Response.json({ error: 'Chưa cấu hình ADMIN_PASSWORD trong Edge Function Secrets.' }, { status: 503, headers: cors });
    if (username !== expectedUser || password !== expectedPassword) return Response.json({ error: 'Sai tài khoản hoặc mật khẩu Owner.' }, { status: 401, headers: cors });

    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const publicKey = Deno.env.get('MATH_LEARN_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY');
    if (!serviceKey || !publicKey) return Response.json({ error: 'Supabase Edge Function thiếu key hệ thống.' }, { status: 503, headers: cors });

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const email = 'math-learn-owner@learnmath.invalid';
    const listed = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (listed.error) throw listed.error;
    let owner = listed.data.users.find((item) => item.email === email);
    if (!owner) {
      const created = await admin.auth.admin.createUser({ email, password: expectedPassword, email_confirm: true, user_metadata: { username: 'Admin' } });
      if (created.error) throw created.error;
      owner = created.data.user;
    } else {
      const updated = await admin.auth.admin.updateUserById(owner.id, { password: expectedPassword, email_confirm: true, user_metadata: { username: 'Admin' } });
      if (updated.error) throw updated.error;
    }
    const profile = await admin.from('users').upsert({ id: owner.id, username: 'Admin', role: 'owner', is_owner: true }, { onConflict: 'id' });
    if (profile.error) throw profile.error;

    const publicClient = createClient(url, publicKey, { auth: { persistSession: false } });
    const signed = await publicClient.auth.signInWithPassword({ email, password: expectedPassword });
    if (signed.error) throw signed.error;
    return Response.json({ session: signed.data.session }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : 'Lỗi đăng nhập Owner.' }, { status: 500, headers: cors });
  }
});
