-- QA 0240: Today, Coming up, Needs attention and Remember include the
-- person's own private records (personal space from 0238, and the
-- account-scoped Notes / To-do / Reminders / Calendar rows from 0230-0237).
-- Remember also works while unpaired.
-- Each function is patched by exact text replacement; the migration fails if
-- an expected fragment is not found, so a silent partial patch is impossible.

create or replace function private.patch_function(p_fn regprocedure, p_pairs text[])
returns void language plpgsql security definer set search_path=''
as $fn$
declare def text; i int; before text;
begin
  def:=pg_catalog.pg_get_functiondef(p_fn);
  for i in 1..array_length(p_pairs,1)/2 loop
    before:=def;
    def:=replace(def,p_pairs[2*i-1],p_pairs[2*i]);
    if def=before then
      raise exception 'Fragment % not found in %',i,p_fn;
    end if;
  end loop;
  execute def;
end $fn$;
revoke all on function private.patch_function(regprocedure,text[]) from public,anon,authenticated;

-- Coming up (next 7 days)
select private.patch_function('public.onespace_coming_up(date)'::regprocedure, array[
$a$ with my_spaces as (
   select space_id from public.space_members
   where user_id=(select auth.uid())
 )$a$,
$b$ with my_spaces as (
   select space_id from public.space_members
   where user_id=(select auth.uid())
   union all
   select s.id from public.spaces s where s.personal_owner=(select auth.uid())
   union all
   select (select auth.uid())
 )$b$,
$a$   from public.space_events e
   join my_spaces sm on sm.space_id=e.space_id$a$,
$b$   from public.space_events e
   join my_spaces sm on sm.space_id=coalesce(e.space_id,e.private_space_id)$b$,
$a$   join public.reminders r on r.id=rr.reminder_id
   join my_spaces sm on sm.space_id=r.space_id$a$,
$b$   join public.reminders r on r.id=rr.reminder_id
   join my_spaces sm on sm.space_id=coalesce(r.space_id,r.private_space_id)$b$,
$a$   from public.tasks t
   join my_spaces sm on sm.space_id=t.space_id$a$,
$b$   from public.tasks t
   join my_spaces sm on sm.space_id=coalesce(t.space_id,t.private_space_id)$b$
]);

-- Needs attention
select private.patch_function('public.onespace_my_attention(date)'::regprocedure, array[
$a$ my_space as (
   select space_id from public.space_members m,me
   where m.user_id=me.id
 ),$a$,
$b$ my_space as (
   select space_id from public.space_members m,me
   where m.user_id=me.id
   union all
   select s.id from public.spaces s,me where s.personal_owner=me.id
   union all
   select me.id from me
 ),$b$,
$a$   join public.reminders r on r.id=rr.reminder_id
   join my_space m on m.space_id=r.space_id
$a$,
$b$   join public.reminders r on r.id=rr.reminder_id
   join my_space m on m.space_id=coalesce(r.space_id,r.private_space_id)
$b$,
$a$   from public.tasks t join my_space m on m.space_id=t.space_id,me$a$,
$b$   from public.tasks t join my_space m on m.space_id=coalesce(t.space_id,t.private_space_id),me$b$
]);

-- Today extras (on this day, items to sort badge)
select private.patch_function('public.onespace_today(date)'::regprocedure, array[
$a$        where i.space_id=(snap->>'space_id')::uuid and i.sorted_at is null$a$,
$b$        where (i.space_id=(snap->>'space_id')::uuid
               or i.space_id=(select s2.id from public.spaces s2 where s2.personal_owner=auth.uid()))
          and i.sorted_at is null$b$,
$a$     where m.space_id=(snap->>'space_id')::uuid and m.archived_at is null$a$,
$b$     where (m.space_id=(snap->>'space_id')::uuid
            or m.space_id=(select s2.id from public.spaces s2 where s2.personal_owner=auth.uid()))
       and m.archived_at is null$b$
]);

-- Remember overview: works unpaired and counts private records.
select private.patch_function('public.get_remember_overview(date)'::regprocedure, array[
$a$   WHERE t.space_id = own.space_id and t.migrated_to_list is null AND t.status = 'open'$a$,
$b$   WHERE (t.space_id in (own.space_id,own.personal_id) or t.private_space_id=own.me)
     and t.migrated_to_list is null AND t.status = 'open'$b$,
$a$   WHERE n.space_id = own.space_id AND n.archived_at IS NULL$a$,
$b$   WHERE (n.space_id in (own.space_id,own.personal_id) or n.private_space_id=own.me)
     AND n.archived_at IS NULL$b$,
$a$   WHERE e.space_id = own.space_id AND e.archived_at IS NULL$a$,
$b$   WHERE (e.space_id in (own.space_id,own.personal_id) or e.private_space_id=own.me)
     AND e.archived_at IS NULL$b$,
$a$     WHERE ev.space_id=own.space_id AND ev.archived_at IS NULL$a$,
$b$     WHERE (ev.space_id in (own.space_id,own.personal_id) or ev.private_space_id=own.me)
       AND ev.archived_at IS NULL$b$,
$a$     WHERE t.space_id=own.space_id and t.migrated_to_list is null AND t.status='open'$a$,
$b$     WHERE (t.space_id in (own.space_id,own.personal_id) or t.private_space_id=own.me)
       and t.migrated_to_list is null AND t.status='open'$b$,
$a$     FROM public.activities a
     WHERE a.space_id=own.space_id AND a.archived_at IS NULL$a$,
$b$     FROM public.activities a
     WHERE a.space_id in (own.space_id,own.personal_id) AND a.archived_at IS NULL$b$,
$a$       ON a.id=c.activity_id
     WHERE a.space_id=own.space_id AND a.archived_at IS NULL$a$,
$b$       ON a.id=c.activity_id
     WHERE a.space_id in (own.space_id,own.personal_id) AND a.archived_at IS NULL$b$,
$a$     WHERE n.space_id=own.space_id AND n.archived_at IS NULL$a$,
$b$     WHERE (n.space_id in (own.space_id,own.personal_id) or n.private_space_id=own.me)
       AND n.archived_at IS NULL$b$,
$a$FROM public.space_members own
WHERE own.user_id=(SELECT auth.uid())$a$,
$b$FROM (SELECT (SELECT m.space_id FROM public.space_members m
                WHERE m.user_id=(SELECT auth.uid()) LIMIT 1) AS space_id,
             (SELECT s.id FROM public.spaces s
                WHERE s.personal_owner=(SELECT auth.uid())) AS personal_id,
             (SELECT auth.uid()) AS me) own
WHERE own.me IS NOT NULL$b$
]);
