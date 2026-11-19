-- QA 0186: partner check-in acknowledgement is historical shared content
-- only after the referenced check-in was actually responded to.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
   where source_table='partner_checkin_acknowledgements'
     and relation_kind='dependent'
     and canonical_parent='partner_checkin_requests'
     and disposition='review_required' and not approved)<>1 then
   raise exception 'Check-in receipt scope needs review';end if;
end $guard$;
update private.qa_archive_table_policy set disposition='shared_only',
  approved=true,reviewed_at=now(),
  policy_note='Response acknowledgement belongs to original sender and recipient only, after responded_at. Acknowledging actor must be original sender, as enforced by insert RLS; outsider and incomplete replies fail closed. Old shared history reference-only, cannot be restored into new relationship.'
where source_table='partner_checkin_acknowledgements'
 and relation_kind='dependent'
 and canonical_parent='partner_checkin_requests'
 and disposition='review_required' and not approved;

create or replace function private.qa_checkin_ack_history_preview(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  root public.partner_checkin_requests%rowtype;
  check_row jsonb;
  row_count int;
  payload jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Check-in history not found';end if;
 select r.* into root from public.partner_checkin_requests r
 join public.space_members m on m.space_id=r.space_id and m.user_id=me
 where r.id=p_request_id and me in (r.sender_id,r.recipient_id);
 if not found then raise exception 'Check-in history not found';end if;
 if (select count(*) from private.qa_archive_table_policy
   where source_table in ('partner_checkin_requests',
      'partner_checkin_acknowledgements')
      and disposition='shared_only' and approved)<>2 then
   raise exception 'Check-in written-history scope not approved';end if;
 if not exists(select 1 from public.space_members m
     where m.space_id=root.space_id and m.user_id=root.sender_id)
 or not exists(select 1 from public.space_members m
     where m.space_id=root.space_id and m.user_id=root.recipient_id)
 then raise exception 'Check-in original pair lineage mismatch';end if;
 select count(*) into row_count from public.partner_checkin_acknowledgements ack
 where ack.request_id=root.id;
 if row_count>1 then raise exception 'Invalid duplicate check-in receipt';end if;
 if row_count>0 and (root.responded_at is null or
      exists(select 1 from public.partner_checkin_acknowledgements a
         where a.request_id=root.id and a.user_id<>root.sender_id))
 then raise exception 'Check-in acknowledgement lineage or response mismatch';end if;
 select to_jsonb(a) into check_row
 from public.partner_checkin_acknowledgements a
 where a.request_id=root.id;
 payload:=jsonb_build_object(
   'schema','onespace.partner-checkin-ack-preview.v1',
   'kind','shared_reference_only',
   'sender_id',root.sender_id,'recipient_id',me,
   'source_space_id',root.space_id,
   'root',jsonb_build_object(
     'table','partner_checkin_requests','source_id',root.id,
     'structured',private.qa_structured_value(to_jsonb(root))),
   'acknowledgement',case when check_row is null then 'null'::jsonb
       else private.qa_structured_value(check_row) end
 );
 return jsonb_build_object(
   'payload',payload,
   'payload_sha256',encode(extensions.digest(
      convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Old shared check-in history is reference-only and cannot be restored as active partner content.');
end $fn$;
revoke all on function private.qa_checkin_ack_history_preview(uuid)
 from public,anon,authenticated;
grant execute on function private.qa_checkin_ack_history_preview(uuid)
 to authenticated;
