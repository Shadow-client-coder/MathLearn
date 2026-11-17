-- MATH LEARN — chạy một lần trên Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  role text not null default 'pending' check (role in ('pending','student','teacher','owner')),
  is_owner boolean not null default false,
  avatar_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(), name text not null, avatar_url text,
  invite_code text not null unique default ('LEARN-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,4))||'-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,4))),
  created_by uuid not null references public.users(id), created_at timestamptz not null default now()
);
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(), class_id uuid not null references public.classes(id) on delete cascade,
  name text not null, color text not null default '#929fff', separate_display boolean not null default false,
  can_manage_class boolean not null default false, can_manage_chat boolean not null default false,
  can_manage_members boolean not null default false, can_manage_forum boolean not null default false,
  created_at timestamptz not null default now(), unique(class_id,name)
);
create table if not exists public.class_members (
  class_id uuid not null references public.classes(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  class_role text not null default 'student' check(class_role in ('teacher','student','custom')),
  role_id uuid references public.roles(id) on delete set null,
  muted_until timestamptz, banned boolean not null default false,
  created_at timestamptz not null default now(), primary key(class_id,user_id)
);
create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(), class_id uuid not null references public.classes(id) on delete cascade,
  slug text not null, name text not null, kind text not null default 'chat' check(kind in ('announcement','chat','qa','ai','forum')),
  created_by uuid references public.users(id), created_at timestamptz not null default now(), unique(class_id,slug)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(), class_id uuid not null references public.classes(id) on delete cascade,
  channel_id text not null, user_id uuid not null references public.users(id), content text not null check(length(content)<=12000),
  attachment_path text, mentions uuid[] not null default '{}', pinned boolean not null default false, is_ai boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.forum_posts (
  id uuid primary key default gen_random_uuid(), class_id uuid not null references public.classes(id) on delete cascade,
  channel_id uuid references public.channels(id) on delete set null, author_id uuid not null references public.users(id),
  title text not null, body text not null default '', attachment_path text, created_at timestamptz not null default now()
);
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(), post_id uuid not null references public.forum_posts(id) on delete cascade,
  student_id uuid not null references public.users(id), storage_path text not null, grade numeric(5,2) check(grade between 0 and 10),
  feedback text, graded_by uuid references public.users(id), submitted_at timestamptz not null default now(), graded_at timestamptz,
  unique(post_id,student_id)
);
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key, class_id uuid not null references public.classes(id) on delete cascade,
  actor_id uuid references public.users(id), action text not null, details jsonb not null default '{}', created_at timestamptz not null default now()
);

-- Bổ sung các cột còn thiếu nếu đang nâng cấp từ bản schema trước đó.
alter table public.roles add column if not exists can_manage_forum boolean not null default false;
alter table public.messages add column if not exists attachment_path text;
alter table public.messages add column if not exists mentions uuid[] not null default '{}';
alter table public.messages add column if not exists pinned boolean not null default false;
alter table public.messages add column if not exists is_ai boolean not null default false;
alter table public.forum_posts add column if not exists attachment_path text;
alter table public.submissions add column if not exists storage_path text;
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='submissions' and column_name='file_url') then
    alter table public.submissions alter column file_url drop not null;
  end if;
end $$;

-- Gỡ các policy của bản cũ để không bị cộng quyền (Postgres OR các policy permissive).
drop policy if exists "profiles visible to authenticated" on public.users;
drop policy if exists "user updates own profile" on public.users;
drop policy if exists "profile insert own" on public.users;
drop policy if exists "classes visible to members or owner" on public.classes;
drop policy if exists "class creator updates" on public.classes;
drop policy if exists "member list visible in class" on public.class_members;
drop policy if exists "managers manage membership" on public.class_members;
drop policy if exists "users join themselves" on public.class_members;
drop policy if exists "roles visible in class" on public.roles;
drop policy if exists "managers change roles" on public.roles;
drop policy if exists "channels visible in class" on public.channels;
drop policy if exists "managers create channels" on public.channels;
drop policy if exists "messages visible to class" on public.messages;
drop policy if exists "members send messages" on public.messages;
drop policy if exists "author or chat manager deletes" on public.messages;
drop policy if exists "forum posts visible" on public.forum_posts;
drop policy if exists "managers publish forum" on public.forum_posts;
drop policy if exists "submissions private to student and teacher" on public.submissions;
drop policy if exists "students submit own work" on public.submissions;
drop policy if exists "teachers grade" on public.submissions;
drop policy if exists "audit visible to managers" on public.audit_logs;
drop policy if exists "audit writes by members" on public.audit_logs;
drop policy if exists users_read_for_members on public.users;
drop policy if exists users_insert_self on public.users;
drop policy if exists users_update_self on public.users;
drop policy if exists classes_read_member_owner on public.classes;
drop policy if exists classes_create_teacher on public.classes;
drop policy if exists classes_update_managers on public.classes;
drop policy if exists classes_delete_owner_teacher on public.classes;
drop policy if exists roles_read_members on public.roles;
drop policy if exists roles_manage on public.roles;
drop policy if exists members_read_class on public.class_members;
drop policy if exists members_manage_update on public.class_members;
drop policy if exists channels_read_members on public.channels;
drop policy if exists channels_create_managers on public.channels;
drop policy if exists channels_update_managers on public.channels;
drop policy if exists channels_delete_managers on public.channels;
drop policy if exists messages_read_members on public.messages;
drop policy if exists messages_insert_members on public.messages;
drop policy if exists messages_update_manager on public.messages;
drop policy if exists messages_delete_own_or_manager on public.messages;
drop policy if exists posts_read_members on public.forum_posts;
drop policy if exists posts_create_managers on public.forum_posts;
drop policy if exists posts_update_managers on public.forum_posts;
drop policy if exists posts_delete_managers on public.forum_posts;
drop policy if exists submissions_read_student_or_teacher on public.submissions;
drop policy if exists submissions_insert_self on public.submissions;
drop policy if exists submissions_resubmit_ungraded on public.submissions;
drop policy if exists submissions_grade_teacher on public.submissions;
drop policy if exists audit_read_managers on public.audit_logs;
drop policy if exists audit_insert_members on public.audit_logs;
drop policy if exists class_files_read_members on storage.objects;
drop policy if exists class_files_upload_members on storage.objects;
drop policy if exists class_files_update_managers on storage.objects;
drop policy if exists class_files_delete_managers on storage.objects;
drop policy if exists submissions_read_own_or_teacher on storage.objects;
drop policy if exists submissions_upload_self on storage.objects;
drop policy if exists submissions_update_self_or_teacher on storage.objects;

create or replace function public.is_owner() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users where id=auth.uid() and is_owner)
$$;
create or replace function public.is_class_member(cid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.is_owner() or exists(select 1 from public.class_members where class_id=cid and user_id=auth.uid() and not banned)
$$;
create or replace function public.can_manage_class(cid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.is_owner() or exists(select 1 from public.classes where id=cid and created_by=auth.uid()) or
    exists(select 1 from public.class_members m join public.roles r on r.id=m.role_id where m.class_id=cid and m.user_id=auth.uid() and r.can_manage_class)
$$;
create or replace function public.can_manage_chat(cid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.can_manage_class(cid) or exists(select 1 from public.class_members m join public.roles r on r.id=m.role_id where m.class_id=cid and m.user_id=auth.uid() and r.can_manage_chat)
$$;
create or replace function public.can_manage_members(cid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.can_manage_class(cid) or exists(select 1 from public.class_members m join public.roles r on r.id=m.role_id where m.class_id=cid and m.user_id=auth.uid() and r.can_manage_members)
$$;
create or replace function public.can_manage_forum(cid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.can_manage_class(cid) or exists(select 1 from public.class_members m join public.roles r on r.id=m.role_id where m.class_id=cid and m.user_id=auth.uid() and r.can_manage_forum)
$$;

create or replace function public.on_auth_user_created() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.users(id,username,role) values(new.id,coalesce(new.raw_user_meta_data->>'username',split_part(new.email,'@',1)),'pending') on conflict(id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists learn_math_auth_user_created on auth.users;
create trigger learn_math_auth_user_created after insert on auth.users for each row execute function public.on_auth_user_created();

create or replace function public.create_class_with_defaults(p_name text,p_avatar_url text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.classes;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập'; end if;
  if not exists(select 1 from public.users where id=auth.uid() and (role='teacher' or is_owner)) then raise exception 'Chỉ giáo viên mới được tạo lớp'; end if;
  insert into public.classes(name,avatar_url,created_by) values(trim(p_name),p_avatar_url,auth.uid()) returning * into c;
  insert into public.class_members(class_id,user_id,class_role) values(c.id,auth.uid(),'teacher');
  insert into public.channels(class_id,slug,name,kind,created_by) values
    (c.id,'thông-báo','thông-báo','announcement',auth.uid()),(c.id,'chat-chung','chat-chung','chat',auth.uid()),
    (c.id,'hỏi-đáp','hỏi-đáp','qa',auth.uid()),(c.id,'ai-chat','ai-chat','ai',auth.uid()),(c.id,'bài-tập','bài-tập','forum',auth.uid());
  insert into public.audit_logs(class_id,actor_id,action,details) values(c.id,auth.uid(),'class.created',jsonb_build_object('name',c.name));
  return to_jsonb(c);
end $$;
create or replace function public.join_class_by_code(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.classes;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập'; end if;
  select * into c from public.classes where invite_code=upper(trim(p_code));
  if c.id is null then raise exception 'Mã mời không hợp lệ'; end if;
  if exists(select 1 from public.class_members where class_id=c.id and user_id=auth.uid() and banned) then raise exception 'Bạn bị cấm khỏi lớp này'; end if;
  insert into public.class_members(class_id,user_id,class_role) values(c.id,auth.uid(),'student') on conflict(class_id,user_id) do nothing;
  return to_jsonb(c);
end $$;
create or replace function public.manage_member_action(p_class_id uuid,p_user_id uuid,p_action text,p_minutes integer default 10) returns void language plpgsql security definer set search_path=public as $$
declare protected boolean;
begin
  if not public.can_manage_members(p_class_id) then raise exception 'Bạn không có quyền quản lý thành viên'; end if;
  select (u.is_owner or c.created_by=p_user_id or m.class_role='teacher') into protected from public.users u join public.class_members m on m.user_id=u.id join public.classes c on c.id=m.class_id where m.class_id=p_class_id and m.user_id=p_user_id;
  if coalesce(protected,false) then raise exception 'Không thể xử lý Owner hoặc giáo viên tạo lớp'; end if;
  if p_action='mute' then update public.class_members set muted_until=now()+make_interval(mins=>greatest(p_minutes,1)) where class_id=p_class_id and user_id=p_user_id;
  elsif p_action='unmute' then update public.class_members set muted_until=null where class_id=p_class_id and user_id=p_user_id;
  elsif p_action='kick' then delete from public.class_members where class_id=p_class_id and user_id=p_user_id;
  elsif p_action='ban' then update public.class_members set banned=true where class_id=p_class_id and user_id=p_user_id;
  else raise exception 'Thao tác không hợp lệ'; end if;
  insert into public.audit_logs(class_id,actor_id,action,details) values(p_class_id,auth.uid(),'member.'||p_action,jsonb_build_object('user_id',p_user_id));
end $$;

create or replace function public.audit_row_change() returns trigger language plpgsql security definer set search_path=public as $$
declare cid uuid; act text; rowdata jsonb;
begin
  if tg_table_name='classes' then cid=coalesce(new.id,old.id); elsif tg_op='DELETE' then cid=old.class_id; else cid=new.class_id; end if;
  act=lower(tg_table_name)||'.'||lower(tg_op); rowdata=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  insert into public.audit_logs(class_id,actor_id,action,details) values(cid,auth.uid(),act,jsonb_build_object('id',rowdata->>'id','name',rowdata->>'name','slug',rowdata->>'slug'));
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists audit_classes on public.classes;
create trigger audit_classes after update or delete on public.classes for each row execute function public.audit_row_change();
drop trigger if exists audit_channels on public.channels;
create trigger audit_channels after insert or update or delete on public.channels for each row execute function public.audit_row_change();
drop trigger if exists audit_messages on public.messages;
create trigger audit_messages after update or delete on public.messages for each row execute function public.audit_row_change();
drop trigger if exists audit_members on public.class_members;
create trigger audit_members after insert or update or delete on public.class_members for each row execute function public.audit_row_change();
drop trigger if exists audit_roles on public.roles;
create trigger audit_roles after insert or update or delete on public.roles for each row execute function public.audit_row_change();
drop trigger if exists audit_posts on public.forum_posts;
create trigger audit_posts after insert or update or delete on public.forum_posts for each row execute function public.audit_row_change();
drop trigger if exists audit_submissions on public.submissions;
create trigger audit_submissions after insert or update or delete on public.submissions for each row execute function public.audit_row_change();

alter table public.users enable row level security;
alter table public.classes enable row level security;
alter table public.roles enable row level security;
alter table public.class_members enable row level security;
alter table public.channels enable row level security;
alter table public.messages enable row level security;
alter table public.forum_posts enable row level security;
alter table public.submissions enable row level security;
alter table public.audit_logs enable row level security;

create policy users_read_for_members on public.users for select to authenticated using(true);
create policy users_insert_self on public.users for insert to authenticated with check(id=auth.uid() and not is_owner and role in ('pending','student','teacher'));
create policy users_update_self on public.users for update to authenticated using(id=auth.uid() and not is_owner) with check(id=auth.uid() and not is_owner and role in ('pending','student','teacher'));
create policy classes_read_member_owner on public.classes for select to authenticated using(public.is_class_member(id));
create policy classes_create_teacher on public.classes for insert to authenticated with check(created_by=auth.uid() and exists(select 1 from public.users where id=auth.uid() and (role='teacher' or is_owner)));
create policy classes_update_managers on public.classes for update to authenticated using(public.can_manage_class(id)) with check(public.can_manage_class(id));
create policy classes_delete_owner_teacher on public.classes for delete to authenticated using(public.is_owner() or created_by=auth.uid());
create policy roles_read_members on public.roles for select to authenticated using(public.is_class_member(class_id));
create policy roles_manage on public.roles for all to authenticated using(public.can_manage_class(class_id)) with check(public.can_manage_class(class_id));
create policy members_read_class on public.class_members for select to authenticated using(public.is_class_member(class_id));
create policy members_manage_update on public.class_members for update to authenticated using(public.can_manage_members(class_id) and class_role<>'teacher' and not exists(select 1 from public.users where id=user_id and is_owner)) with check(public.can_manage_members(class_id) and class_role<>'teacher' and not exists(select 1 from public.users where id=user_id and is_owner));
create policy channels_read_members on public.channels for select to authenticated using(public.is_class_member(class_id));
create policy channels_create_managers on public.channels for insert to authenticated with check(public.can_manage_class(class_id) and created_by=auth.uid());
create policy channels_update_managers on public.channels for update to authenticated using(public.can_manage_class(class_id)) with check(public.can_manage_class(class_id));
create policy channels_delete_managers on public.channels for delete to authenticated using(public.can_manage_class(class_id));
create policy messages_read_members on public.messages for select to authenticated using(public.is_class_member(class_id));
create policy messages_insert_members on public.messages for insert to authenticated with check(user_id=auth.uid() and not is_ai and public.is_class_member(class_id) and not exists(select 1 from public.class_members where class_id=messages.class_id and user_id=auth.uid() and (banned or muted_until>now())) and (channel_id<>'thông-báo' or public.can_manage_class(class_id)) and (channel_id not like 'forum-%' or public.can_manage_forum(class_id)));
create policy messages_update_manager on public.messages for update to authenticated using(public.can_manage_chat(class_id)) with check(public.can_manage_chat(class_id));
create policy messages_delete_own_or_manager on public.messages for delete to authenticated using(user_id=auth.uid() or public.can_manage_chat(class_id));
create policy posts_read_members on public.forum_posts for select to authenticated using(public.is_class_member(class_id));
create policy posts_create_managers on public.forum_posts for insert to authenticated with check(author_id=auth.uid() and public.can_manage_forum(class_id));
create policy posts_update_managers on public.forum_posts for update to authenticated using(public.can_manage_forum(class_id)) with check(public.can_manage_forum(class_id));
create policy posts_delete_managers on public.forum_posts for delete to authenticated using(public.can_manage_class(class_id));
create policy submissions_read_student_or_teacher on public.submissions for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.forum_posts p where p.id=post_id and public.can_manage_class(p.class_id)));
create policy submissions_insert_self on public.submissions for insert to authenticated with check(student_id=auth.uid() and exists(select 1 from public.forum_posts p where p.id=post_id and public.is_class_member(p.class_id)));
create policy submissions_resubmit_ungraded on public.submissions for update to authenticated using(student_id=auth.uid() and grade is null) with check(student_id=auth.uid() and grade is null and graded_by is null and feedback is null);
create policy submissions_grade_teacher on public.submissions for update to authenticated using(exists(select 1 from public.forum_posts p where p.id=post_id and public.can_manage_class(p.class_id))) with check(exists(select 1 from public.forum_posts p where p.id=post_id and public.can_manage_class(p.class_id)));
create policy audit_read_managers on public.audit_logs for select to authenticated using(public.can_manage_class(class_id));
create policy audit_insert_members on public.audit_logs for insert to authenticated with check(actor_id=auth.uid() and public.is_class_member(class_id));

grant execute on function public.create_class_with_defaults(text,text) to authenticated;
grant execute on function public.join_class_by_code(text) to authenticated;
grant execute on function public.manage_member_action(uuid,uuid,text,integer) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
  ('class-files','class-files',false,20971520,array['image/png','image/jpeg','image/webp','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('submissions','submissions',false,20971520,array['image/png','image/jpeg','image/webp','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do nothing;
create policy class_files_read_members on storage.objects for select to authenticated using(bucket_id='class-files' and public.is_class_member(((storage.foldername(name))[1])::uuid));
create policy class_files_upload_members on storage.objects for insert to authenticated with check(bucket_id='class-files' and (public.can_manage_class(((storage.foldername(name))[1])::uuid) or ((storage.foldername(name))[2]='chat' and (storage.foldername(name))[3]=auth.uid()::text and public.is_class_member(((storage.foldername(name))[1])::uuid))));
create policy class_files_update_managers on storage.objects for update to authenticated using(bucket_id='class-files' and public.can_manage_class(((storage.foldername(name))[1])::uuid)) with check(bucket_id='class-files' and public.can_manage_class(((storage.foldername(name))[1])::uuid));
create policy class_files_delete_managers on storage.objects for delete to authenticated using(bucket_id='class-files' and public.can_manage_class(((storage.foldername(name))[1])::uuid));
create policy submissions_read_own_or_teacher on storage.objects for select to authenticated using(bucket_id='submissions' and (public.can_manage_class(((storage.foldername(name))[1])::uuid) or (storage.foldername(name))[3]=auth.uid()::text));
create policy submissions_upload_self on storage.objects for insert to authenticated with check(bucket_id='submissions' and (storage.foldername(name))[3]=auth.uid()::text and public.is_class_member(((storage.foldername(name))[1])::uuid) and exists(select 1 from public.forum_posts p where p.id=((storage.foldername(name))[2])::uuid and p.class_id=((storage.foldername(name))[1])::uuid));
create policy submissions_update_self_or_teacher on storage.objects for update to authenticated using(bucket_id='submissions' and (public.can_manage_class(((storage.foldername(name))[1])::uuid) or (storage.foldername(name))[3]=auth.uid()::text)) with check(bucket_id='submissions' and (public.can_manage_class(((storage.foldername(name))[1])::uuid) or (storage.foldername(name))[3]=auth.uid()::text));

do $$ begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.forum_posts; exception when duplicate_object then null; when undefined_object then null; end $$;

