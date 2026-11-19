-- QA 0185: protect location/visit written history from cross-partner
-- associations. Original place's visibility controls the preview scope.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
     where source_table='place_visits' and relation_kind='root'
      and disposition='review_required' and not approved)<>1 then
   raise exception 'Place visit policy needs manual re-review';end if;
end $guard$;
update private.qa_archive_table_policy
set disposition='private_shared',approved=true,reviewed_at=now(),
 policy_note='Place visit notes inherit parent places visibility. Private root requires all visit authors be owner. Shared root requires original pair membership. Require same space_id for place and visits; optional memory link must be in same space and is stripped as nonportable navigation pointer. planned_trip_id stripped from root; written captions remain.'
where source_table='place_visits' and relation_kind='root'
  and disposition='review_required' and not approved;

create or replace function private.qa_place_visit_history_preview(p_place_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid();
 p public.places%rowtype;
 bad_count int; n int;
 data jsonb; payload jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Place not found';end if;
 select places.* into p from public.places places
  join public.space_members m on m.space_id=places.space_id
    and m.user_id=me
  where places.id=p_place_id and
        (places.visibility='shared' or places.created_by=me);
 if not found then raise exception 'Place not found';end if;
 if p.visibility not in ('private','shared') then
   raise exception 'Unsupported place visibility';end if;
 if (select count(*) from private.qa_archive_table_policy
     where source_table in ('places','place_visits')
       and disposition='private_shared' and approved)<>2
 then raise exception 'Place visit archive scope unapproved';end if;
 if not exists(select 1 from public.space_members sm
      where sm.space_id=p.space_id and sm.user_id=p.created_by)
 then raise exception 'Place owner lineage mismatch';end if;
 select count(*) into bad_count from public.place_visits v
 where v.place_id=p.id and (
   v.space_id is distinct from p.space_id
   or (p.visibility='private' and v.created_by is distinct from p.created_by)
   or (p.visibility='shared' and not exists(
     select 1 from public.space_members sm
     where sm.space_id=p.space_id and sm.user_id=v.created_by))
   or (v.memory_id is not null and not exists (
     select 1 from public.memories memory
     where memory.id=v.memory_id and memory.space_id=p.space_id))
 );
 if bad_count>0 then raise exception 'Place visit association or author mismatch';end if;
 select count(*) into n from public.place_visits where place_id=p.id;
 if n>500 then raise exception 'Place visits exceed 500 records';end if;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',v.id,
    'structured',private.qa_structured_value(to_jsonb(v))-'memory_id')
    order by v.visited_on,v.id),'[]'::jsonb)
 into data from public.place_visits v where v.place_id=p.id;
 payload:=jsonb_build_object(
  'schema','onespace.place-visit-history-preview.v1',
  'kind',case when p.visibility='private' then 'private_owner_only'
       else 'shared_reference_only' end,
  'owner_id',p.created_by,'recipient_id',me,'source_space_id',p.space_id,
  'root',jsonb_build_object('table','places','source_id',p.id,
    'structured',private.qa_structured_value(to_jsonb(p))-'planned_trip_id'),
  'visits',data,'visit_count',n
 );
 if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
   raise exception 'Place visit history exceeds 2 MiB';end if;
 return jsonb_build_object('payload',payload,
   'payload_sha256',encode(extensions.digest(
      convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Written place visits only. Previous relationship links are nonportable; no restore or file attachments.');
end $fn$;
revoke all on function private.qa_place_visit_history_preview(uuid)
 from public,anon,authenticated;
grant execute on function private.qa_place_visit_history_preview(uuid)
 to authenticated;
