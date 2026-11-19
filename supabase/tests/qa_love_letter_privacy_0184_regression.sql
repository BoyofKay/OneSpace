-- QA 0184: draft/future author privacy, scheduled-open recipient, read
-- receipts and hidden reply references; fixtures rolled back.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; outsider uuid;
 draft_id uuid; future_id uuid; open_id uuid;
 p jsonb; msg text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture unavailable';end if;
 select u.id into outsider from auth.users u
 where u.id not in (select user_id from public.space_members where space_id=sid)
 limit 1;
 insert into public.couple_letters(
   space_id,author_id,title,body,status)
 values(sid,a,'QA LETTER DRAFT','PRIVATE_UNSENT_LOVE_LETTER','draft')
 returning id into draft_id;
 insert into public.couple_letters(
   space_id,author_id,title,body,status,open_on)
 values(sid,a,'QA LETTER FUTURE','SECRET_NOT_READY_YET','sent',current_date+7)
 returning id into future_id;
 insert into public.couple_letters(
   space_id,author_id,title,body,status,open_on,reply_to)
 values(sid,a,'QA LETTER OPEN','SHARED_LOVE_LETTER_VISIBLE','sent',
        current_date-1,draft_id)
 returning id into open_id;
 insert into public.couple_letter_reads(letter_id,reader_id)
 values(open_id,b);
 if has_function_privilege('anon',
   'private.qa_love_letter_history_preview(uuid)','execute') then
   raise exception 'Anonymous letter preview permitted';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_love_letter_history_preview(draft_id);
 if p#>>'{payload,kind}'<>'author_private_only'
   or p::text not like '%PRIVATE_UNSENT_LOVE_LETTER%'
   or p#>>'{payload,receipt_count}'<>'0'
   or p->>'can_restore'<>'false'
 then raise exception 'Author lost draft or received wrong scope';end if;
 p:=private.qa_love_letter_history_preview(future_id);
 if p#>>'{payload,kind}'<>'author_private_only'
   or p::text not like '%SECRET_NOT_READY_YET%'
 then raise exception 'Author lost future-open letter';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 for p in select jsonb_build_object('id',id) from
   (values(draft_id),(future_id)) as ids(id) loop
   begin
     perform private.qa_love_letter_history_preview((p->>'id')::uuid);
     raise exception 'Recipient accessed unsent/future letter';
   exception when others then
     get stacked diagnostics msg=message_text;
     if msg<>'Letter not found' then
       raise exception 'Wrong unopened-letter denial: %',msg;end if;
   end;
 end loop;
 p:=private.qa_love_letter_history_preview(open_id);
 if p#>>'{payload,kind}'<>'shared_reference_only'
   or p::text not like '%SHARED_LOVE_LETTER_VISIBLE%'
   or p#>>'{payload,receipt_count}'<>'1'
   or (p#>'{payload,root,structured}') ? 'reply_to'
   or p::text like '%PRIVATE_UNSENT_LOVE_LETTER%'
   or p::text like '%SECRET_NOT_READY_YET%'
 then raise exception 'Recipient history leaked hidden letter or receipt: %',
       left(p::text,950);end if;
 if p->>'payload_sha256'<>
   encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Letter history hash failed';end if;
 if outsider is not null then
   perform set_config('request.jwt.claim.sub',outsider::text,true);
   begin
     perform private.qa_love_letter_history_preview(open_id);
     raise exception 'Outsider saw private couple letter';
   exception when others then
     get stacked diagnostics msg=message_text;
     if msg<>'Letter not found' then
       raise exception 'Wrong outsider denial: %',msg;end if;
   end;
 end if;
 perform set_config('role','postgres',true);
 insert into public.couple_letter_reads(letter_id,reader_id)
 values(future_id,b);
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform private.qa_love_letter_history_preview(future_id);
   raise exception 'Future-open letter read receipt was silently accepted';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Letter read receipt lineage mismatch' then
     raise exception 'Wrong future-read failure: %',msg;end if;
 end;
end $qa$;
rollback;
select 'PASS: drafts/future-open letters owner-only, mature sent letters visible to pair, no hidden replies, receipt authorization and outsider denial; rolled back' result;
