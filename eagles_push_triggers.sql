-- EAGLES push notifications: triggers + 7:00 AM IST overdue digest
-- Run once in Supabase -> SQL Editor. Safe to re-run. Does not change existing data.

create or replace function public.ea_trg_push_message() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_sender text; v_conv text; v_ids uuid[]; v_preview text;
begin
  if new.msg_type is distinct from 'text' then return new; end if;
  select name into v_sender from ea_users where id = new.sender_id;
  select name into v_conv from ea_conversations where id = new.conversation_id;
  v_preview := left(coalesce(new.content,''), 120);
  select coalesce(array_agg(distinct m.user_id), '{}') into v_ids
  from ea_conversation_members m
  join ea_users u on u.id = m.user_id and u.active
  left join ea_push_prefs p on p.user_id = m.user_id
  where m.conversation_id = new.conversation_id
    and m.user_id <> new.sender_id
    and (
      coalesce(p.chat_all,false)
      or (new.mentions is not null and m.user_id = any(new.mentions::uuid[]))
      or (new.content ilike '%@' || split_part(u.name,' ',1) || '%')
    );
  perform ea_push_send(v_ids, coalesce(v_sender,'New message') || ' · ' || coalesce(v_conv,'Chat'), v_preview, '/?c=' || new.conversation_id, 'chat-' || new.conversation_id);
  return new;
end $$;
drop trigger if exists ea_push_on_message on public.ea_messages;
create trigger ea_push_on_message after insert on public.ea_messages for each row execute function public.ea_trg_push_message();

create or replace function public.ea_trg_push_assignment() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_task record; v_ok boolean;
begin
  select t.title, t.due_date, t.created_by, c.name as proj into v_task
  from ea_tasks t join ea_conversations c on c.id=t.conversation_id where t.id = new.task_id;
  if v_task.created_by = new.user_id then return new; end if;
  select coalesce((select assigned from ea_push_prefs where user_id=new.user_id), true)
     and exists(select 1 from ea_users where id=new.user_id and active) into v_ok;
  if v_ok then
    perform ea_push_send(array[new.user_id], 'New task · ' || coalesce(v_task.proj,''),
      v_task.title || case when v_task.due_date is not null then ' (due ' || to_char(v_task.due_date,'DD Mon') || ')' else '' end,
      '/?t=' || new.task_id, 'task-' || new.task_id);
  end if;
  return new;
end $$;
drop trigger if exists ea_push_on_assignment on public.ea_task_assignees;
create trigger ea_push_on_assignment after insert on public.ea_task_assignees for each row execute function public.ea_trg_push_assignment();

create or replace function public.ea_push_overdue_digest() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r record; v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  for r in
    select a.user_id, count(*) as n, min(t.title) as sample
    from ea_task_assignees a
    join ea_tasks t on t.id=a.task_id and t.status='active'
    join ea_users u on u.id=a.user_id and u.active
    left join ea_push_prefs p on p.user_id=a.user_id
    where a.status <> 'completed' and t.due_date < v_today and coalesce(p.overdue,true)
    group by a.user_id
  loop
    perform ea_push_send(array[r.user_id],
      case when r.n=1 then '1 overdue task' else r.n || ' overdue tasks' end,
      case when r.n=1 then r.sample else r.sample || ' and ' || (r.n-1) || ' more' end,
      '/?view=overdue', 'overdue-digest');
  end loop;
end $$;
revoke all on function public.ea_push_overdue_digest() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname='ea-overdue-digest') then perform cron.unschedule('ea-overdue-digest'); end if;
  perform cron.schedule('ea-overdue-digest', '30 1 * * *', 'select public.ea_push_overdue_digest()');
end $$;
