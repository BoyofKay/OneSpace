-- QA 0187: owner-checked reminder receipt/action written history.
-- No notifications are restored, scheduled or dispatched by previews.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
 where source_table in ('reminder_actions','reminder_recipients')
 and canonical_parent='reminders' and relation_kind='dependent'
 and disposition='review_required' and not approved) <> 2 then
 raise exception 'Reminder recipient/action scope must be re-reviewed';end if;
end $guard$;
update private.qa_archive_table_policy
set disposition='private_shared',approved=true,reviewed_at=now(),
policy_note=case source_table
 when 'reminder_actions' then
 'Historical action notes follow reminder owner/private or original pair shared scope; recipient belongs to parent pair, actor belongs to pair or NULL system action; private parent requires actor/recipient owner. Never reschedule actions on restore.'
 else 'Recipient state/outcome text follows parent privacy; private parent permits owner-only recipient. In shared original pair recipient and historical status are reference only; next alert/snooze state excluded from portable preview.'
end
where source_table in ('reminder_actions','reminder_recipients')
 and disposition='review_required' and not approved;

create or replace function private.qa_reminder_written_history_preview(p_reminder_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid(); root public.reminders%rowtype; n int; bad int; children jsonb; actions jsonb; recipients jsonb; payload jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Reminder not found';end if;
 select r.* into root from public.reminders r
 join public.space_members m on m.space_id=r.space_id and m.user_id=me
 where r.id=p_reminder_id and (r.visibility='shared' or r.created_by=me);
 if not found then raise exception 'Reminder not found';end if;
 if root.visibility not in ('shared','private') then
 raise exception 'Unsupported reminder visibility';end if;
 if (select count(*) from private.qa_archive_table_policy p
 where p.source_table in ('reminders','reminder_actions','reminder_recipients')
 and p.approved and p.disposition='private_shared')<>3
 then raise exception 'Reminder history catalog not approved';end if;
 if not exists(select 1 from public.space_members s
 where s.space_id=root.space_id and s.user_id=root.created_by)
 then raise exception 'Reminder owner lineage mismatch';end if;
 select count(*) into bad from public.reminder_recipients x
 where x.reminder_id=root.id and (
  (root.visibility='private' and x.recipient_id<>root.created_by)
  or (root.visibility='shared' and not exists(
    select 1 from public.space_members sm where sm.space_id=root.space_id and sm.user_id=x.recipient_id))
 );
 if bad>0 then raise exception 'Reminder recipient lineage mismatch';end if;
 select count(*) into bad from public.reminder_actions x
 where x.reminder_id=root.id and (
  (root.visibility='private' and
    (x.recipient_id<>root.created_by or x.actor_id is distinct from root.created_by))
  or (root.visibility='shared' and (
    not exists(select 1 from public.space_members sm where sm.space_id=root.space_id and sm.user_id=x.recipient_id)
    or (x.actor_id is not null and not exists(
      select 1 from public.space_members sm where sm.space_id=root.space_id and sm.user_id=x.actor_id))))
 );
 if bad>0 then raise exception 'Reminder action lineage mismatch';end if;
 select count(*) into n from (
  select id::text from public.reminder_recipients where reminder_id=root.id
  union all select id::text from public.reminder_actions where reminder_id=root.id
 ) records;
 if n>500 then raise exception 'Reminder history exceeds 500 records';end if;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',x.id,
   'structured',private.qa_structured_value(to_jsonb(x))
     - 'next_alert_at' - 'last_notified_at' - 'snoozed_until' - 'open_occurrence_at')
   order by x.updated_at,x.id),'[]'::jsonb)
 into recipients from public.reminder_recipients x where x.reminder_id=root.id;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',x.id,
   'structured',private.qa_structured_value(to_jsonb(x)) - 'next_alert_at')
   order by x.recorded_at,x.id),'[]'::jsonb)
 into actions from public.reminder_actions x where x.reminder_id=root.id;
 children:=jsonb_build_object('reminder_recipients',recipients,'reminder_actions',actions);
 payload:=jsonb_build_object(
   'schema','onespace.reminder-written-history-preview.v1',
   'kind',case when root.visibility='private' then 'private_owner_only' else 'shared_reference_only' end,
   'recipient_id',me,'owner_id',root.created_by,'source_space_id',root.space_id,
   'root',jsonb_build_object('table','reminders','source_id',root.id,
      'structured',private.qa_structured_value(to_jsonb(root))-'source_id'),
   'children',children,'child_record_count',n
 );
 if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
 raise exception 'Reminder preview exceeds 2 MiB';end if;
 return jsonb_build_object('payload',payload,'payload_sha256',encode(
 extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
 'media_included',false,'documents_included',false,'encrypted',false,
 'is_verified_archive',false,'can_restore',false,'safe_to_separate',false,
 'warning','Historic outcome notes only; reminder scheduling, alerts and former-partner recipients cannot be restored.');
end $fn$;
revoke all on function private.qa_reminder_written_history_preview(uuid) from public,anon,authenticated;
grant execute on function private.qa_reminder_written_history_preview(uuid) to authenticated;
