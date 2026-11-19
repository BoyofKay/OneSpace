-- QA 0184: love-letter privacy is author/availability dependent.
-- Drafts and future-open sent letters belong exclusively to author.
-- Recipient's history includes SENT and OPEN-ELIGIBLE letters only.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
    where source_table in ('couple_letters','couple_letter_reads')
      and disposition='review_required' and not approved)<>2 then
   raise exception 'Love-letter privacy requires re-review';end if;
end $guard$;
update private.qa_archive_table_policy set
 disposition='private_shared',approved=true,reviewed_at=now(),
 policy_note=case source_table when 'couple_letters' then
  'Author-private drafts and future-open sent letters are owner-only. Sent/open-eligible letters visible to original pair, strictly by open_on date. Reply-to non-visible letters stripped. Not a restorable shared archive.'
 else
  'Read receipts only accompany sent and open-eligible letters. Reader must be other original space member; no draft/future read receipts may be copied. Non-restorable shared history.'
 end
where source_table in ('couple_letters','couple_letter_reads')
 and disposition='review_required' and not approved;

create or replace function private.qa_love_letter_history_preview(p_letter_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  source_letter public.couple_letters%rowtype;
  open_to_pair boolean;
  source_json jsonb;
  result_json jsonb;
  receipt_rows jsonb;
  invalid_receipts int;
  receipt_count int;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Letter not found';end if;
 select l.* into source_letter
 from public.couple_letters l
 join public.space_members sm on sm.space_id=l.space_id and sm.user_id=me
 where l.id=p_letter_id
   and (l.author_id=me or (l.status='sent' and
       (l.open_on is null or l.open_on<=current_date)));
 if not found then raise exception 'Letter not found';end if;
 if not exists(select 1 from public.space_members m
      where m.space_id=source_letter.space_id
        and m.user_id=source_letter.author_id) then
   raise exception 'Letter source author no longer belongs to original pair';end if;
 if (select count(*) from private.qa_archive_table_policy p
     where p.source_table in ('couple_letters','couple_letter_reads')
       and p.approved and p.disposition='private_shared')<>2 then
   raise exception 'Letter history scope unapproved';end if;
 open_to_pair:=source_letter.status='sent'
   and (source_letter.open_on is null or source_letter.open_on<=current_date);
 source_json:=private.qa_structured_value(to_jsonb(source_letter));
 -- Do not expose a private draft's identifier in reply_to when its author
 -- is the only member allowed to see the referenced letter.
 if source_letter.reply_to is not null and not exists(
   select 1 from public.couple_letters linked
   where linked.id=source_letter.reply_to
     and linked.space_id=source_letter.space_id
     and (linked.author_id=me or (linked.status='sent'
       and (linked.open_on is null or linked.open_on<=current_date))))
 then
   source_json:=source_json-'reply_to';
 end if;
 select count(*) into invalid_receipts from public.couple_letter_reads r
 where r.letter_id=source_letter.id and (
   not open_to_pair
   or r.reader_id=source_letter.author_id
   or not exists(select 1 from public.space_members m
       where m.space_id=source_letter.space_id and m.user_id=r.reader_id)
 );
 if invalid_receipts<>0 then raise exception 'Letter read receipt lineage mismatch';end if;
 select count(*) into receipt_count from public.couple_letter_reads
 where letter_id=source_letter.id;
 if receipt_count>50 then raise exception 'Letter receipt history too large';end if;
 select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))
    order by r.opened_at,r.reader_id),'[]'::jsonb)
 into receipt_rows from public.couple_letter_reads r
 where r.letter_id=source_letter.id and open_to_pair;
 result_json:=jsonb_build_object(
   'schema','onespace.love-letter-history-preview.v1',
   'kind',case when open_to_pair then 'shared_reference_only'
      else 'author_private_only' end,
   'author_id',source_letter.author_id,'recipient_id',me,
   'source_space_id',source_letter.space_id,
   'root',jsonb_build_object('table','couple_letters',
     'source_id',source_letter.id,'structured',source_json),
   'read_receipts',receipt_rows,'receipt_count',receipt_count
 );
 if octet_length(convert_to(result_json::text,'UTF8'))>2097152 then
   raise exception 'Letter history preview too large';end if;
 return jsonb_build_object(
   'payload',result_json,
   'payload_sha256',encode(extensions.digest(
     convert_to(result_json::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Author-only draft/future letters cannot be viewed by recipient until opened. Written preview is not an archive or restore.');
end $fn$;
revoke all on function private.qa_love_letter_history_preview(uuid)
 from public,anon,authenticated;
grant execute on function private.qa_love_letter_history_preview(uuid)
 to authenticated;
