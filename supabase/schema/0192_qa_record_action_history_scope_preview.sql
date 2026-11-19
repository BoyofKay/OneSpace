-- QA 0192: last remaining space-linked table, action-history event audit.
-- Every one of 15 record kinds resolves to an original-space source and
-- caller visibility. Deleted/mismatched parents fail closed, never replay.
create or replace function private.qa_action_history_record_scope(
 p_kind text,p_id uuid,p_space uuid,p_recipient uuid
) returns text language plpgsql stable security definer set search_path='' as $fn$
declare tab text; v record; membership int;
begin
 if auth.uid() is null or auth.uid()<>p_recipient then return 'blocked';end if;
 if not exists(select 1 from public.space_members m
  where m.space_id=p_space and m.user_id=p_recipient) then return 'blocked';end if;
 if p_kind in ('note','task','memory','event','reminder','occasion','trip','activity','experience') then
 return private.qa_portable_target_scope(p_kind,p_id,p_space,p_recipient);
 end if;
 if p_kind='experience_comment' then
   select c.created_by,c.archived_at,x.space_id into v
     from public.shared_experience_comments c
     join public.shared_experiences x on x.id=c.experience_id
     where c.id=p_id and x.space_id=p_space;
   if v is null then return 'blocked';end if;
   if v.archived_at is not null then
     return case when v.created_by=p_recipient then 'private' else 'blocked' end;
   end if;
   return 'shared';
 end if;
 if p_kind='checkin_request' then
  if exists(select 1 from public.partner_checkin_requests r
      where r.id=p_id and r.space_id=p_space and p_recipient in (r.sender_id,r.recipient_id)
        and exists(select 1 from public.space_members m where m.space_id=p_space and m.user_id=r.sender_id)
        and exists(select 1 from public.space_members m where m.space_id=p_space and m.user_id=r.recipient_id))
  then return 'shared';end if;
  return 'blocked';
 end if;
 tab:=case p_kind
 when 'goal' then 'goals'
 when 'contact' then 'saved_contacts'
 when 'sort_item' then 'items_to_sort'
 when 'checkin' then 'daily_checkins'
 else null end;
 if tab is null then return 'blocked';end if;
 execute format('select t.created_by,t.visibility from public.%I t
 where t.id=$1 and t.space_id=$2',tab) into v using p_id,p_space;
 if v is null then return 'blocked';end if;
 if v.visibility='shared' then return 'shared';end if;
 if v.visibility='private' and v.created_by=p_recipient then return 'private';end if;
 return 'blocked';
end $fn$;
revoke all on function private.qa_action_history_record_scope(text,uuid,uuid,uuid)
 from public,anon,authenticated;

do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
     where source_table='record_action_history' and relation_kind='root'
       and disposition='review_required' and not approved)<>1 then
 raise exception 'Action-history root classification requires review';end if;
end $guard$;
update private.qa_archive_table_policy set approved=true,
 disposition='private_shared',reviewed_at=now(),
 policy_note='Every action must resolve through its 15 record kinds to an existing original-space source with recipient-scoped visibility; archived experience comments are author-only, partner check-in requests require original pair, and private source audit actors must be owner. Missing/foreign parent fails closed. Written audit event is reference-only and must not be replayed as new actions.'
where source_table='record_action_history'
 and relation_kind='root' and disposition='review_required' and not approved;

create or replace function private.qa_record_action_history_preview(p_history_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare me uuid:=auth.uid(); hist public.record_action_history%rowtype;
 scope text; payload jsonb; bad int;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'History action not found';end if;
 select h.* into hist from public.record_action_history h
 join public.space_members sm on sm.space_id=h.space_id and sm.user_id=me
 where h.id=p_history_id;
 if not found then raise exception 'History action not found';end if;
 if (select count(*) from private.qa_archive_table_policy
 where source_table='record_action_history' and approved
 and disposition='private_shared')<>1 then raise exception 'Audit archive scope not approved';end if;
 scope:=private.qa_action_history_record_scope(hist.record_kind,hist.record_id,hist.space_id,me);
 if scope='blocked' then raise exception 'History action not found';end if;
 if scope='private' and hist.actor_id is not null and hist.actor_id<>me
 then raise exception 'Private record audit actor mismatch';end if;
 if scope='shared' and hist.actor_id is not null and not exists(
   select 1 from public.space_members sm
   where sm.space_id=hist.space_id and sm.user_id=hist.actor_id)
 then raise exception 'Shared record audit actor mismatch';end if;
 payload:=jsonb_build_object(
   'schema','onespace.record-action-history-preview.v1',
   'kind',case when scope='private' then 'private_owner_only' else 'shared_reference_only' end,
   'recipient_id',me,'source_space_id',hist.space_id,
   'event',private.qa_structured_value(to_jsonb(hist)));
 return jsonb_build_object('payload',payload,
   'payload_sha256',encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,'encrypted',false,
   'is_verified_archive',false,'can_restore',false,'safe_to_separate',false,
   'warning','This is an auditable historical event, not an instruction to replay actions or restore private/shared records.');
end $fn$;
revoke all on function private.qa_record_action_history_preview(bigint)
 from public,anon,authenticated;
grant execute on function private.qa_record_action_history_preview(bigint)
 to authenticated;
