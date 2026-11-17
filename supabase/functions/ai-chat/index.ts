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
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('MATH_LEARN_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY');
    if (!anon) return Response.json({ error: 'Chưa cấu hình publishable key cho Edge Functions.' }, { status: 503, headers: cors });
    const authorization = request.headers.get('Authorization') || '';
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return Response.json({ error: 'Bạn cần đăng nhập.' }, { status: 401, headers: cors });

    const key = Deno.env.get('OPENAI_API_KEY');
    if (!key) return Response.json({ error: 'Chưa cấu hình OPENAI_API_KEY trong Supabase Edge Function Secrets.' }, { status: 503, headers: cors });
    const body = await request.json();
    const prompt = String(body.prompt || '').slice(0, 8000);
    const classId = String(body.classId || '');
    const channelSlug = String(body.channelSlug || '');
    if (!prompt.trim()) return Response.json({ error: 'Hãy nhập câu hỏi Toán.' }, { status: 400, headers: cors });
    const channel = await userClient.from('channels').select('kind').eq('class_id', classId).eq('slug', channelSlug).maybeSingle();
    if (channel.error || channel.data?.kind !== 'ai') return Response.json({ error: 'Kênh AI hoặc quyền thành viên không hợp lệ.' }, { status: 403, headers: cors });
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: Deno.env.get('OPENAI_MODEL') || 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'Bạn là gia sư Toán học thân thiện. Trả lời bằng tiếng Việt, giải thích rõ từng bước và dùng công thức LaTeX giữa dấu $ hoặc $$.' },
          { role: 'user', content: prompt },
        ],
      }),
    });
    const result = await response.json();
    if (!response.ok) return Response.json({ error: result.error?.message || 'Không kết nối được AI.' }, { status: 502, headers: cors });
    const answer = result.choices?.[0]?.message?.content || 'AI chưa có câu trả lời.';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!serviceKey) return Response.json({ error: 'Supabase chưa cấp service key cho Edge Function.' }, { status: 503, headers: cors });
    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const saved = await service.from('messages').insert({ class_id: classId, channel_id: channelSlug, user_id: user.id, content: answer, is_ai: true });
    if (saved.error) throw saved.error;
    return Response.json({ answer }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : 'Lỗi Edge Function.' }, { status: 500, headers: cors });
  }
});
