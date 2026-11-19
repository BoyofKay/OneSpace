begin;
do $qa$
declare sid uuid;a uuid;b uuid;shared_id uuid;private_id uuid;
 ra jsonb;rb jsonb;rb_after jsonb;ra_after jsonb;sha_shared text;sha_private text;
 hash_before text;hash_after text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'Original couple fixture missing';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA shared census report note','Both partners remember this','shared')
 returning id into shared_id;
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA private census report note','Only owner remembers this','private')
 returning id into private_id;
 perform set_config('role','authenticated',true);
 ra:=public.qa_archive_source_coverage_report();
 if (ra->>'mixed_visibility_shared_rows_censused')<>'true'
 or jsonb_array_length(ra->'mixed_shared_per_table')<>42
 or ra->>'all_written_records_durably_packaged'<>'false'
 or ra->>'full_per_row_source_manifest_complete'<>'false'
 or ra->>'can_restore'<>'false'
 or ra->>'safe_to_archive'<>'false'
 or ra::text like '%Both partners remember this%'
 or ra::text like '%Only owner remembers this%'
 then raise exception 'Updated truthful 69-family visibility source report failed';end if;
 select x->>'source_sha256' into sha_shared from jsonb_array_elements(ra->'mixed_shared_per_table') x
 where x->>'source_table'='notes';
 perform set_config('request.jwt.claim.sub',b::text,true);
 rb:=public.qa_archive_source_coverage_report();
 if (select x->>'source_sha256' from jsonb_array_elements(rb->'mixed_shared_per_table') x
   where x->>'source_table'='notes')<>sha_shared
 then raise exception 'Both partners must see same shared note snapshot hash';end if;
 hash_before:=rb->>'source_coverage_sha256';
 if (rb->>'private_source_rows_counted')::int<>0
 then raise exception 'B private source counts included A private note';end if;
 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set body='Shared plans were updated' where id=shared_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',b::text,true);
 rb_after:=public.qa_archive_source_coverage_report();
 hash_after:=rb_after->>'source_coverage_sha256';
 if hash_before=hash_after then
 raise exception 'Shared note edit failed to update partner B report fingerprint';end if;
 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set body='Only A knows new private details' where id=private_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',b::text,true);
 rb:=public.qa_archive_source_coverage_report();
 if rb->>'source_coverage_sha256'<>hash_after
 then raise exception 'A private note edit modified partner B source hash';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 ra_after:=public.qa_archive_source_coverage_report();
 if ra_after->>'source_coverage_sha256'=ra->>'source_coverage_sha256'
 or ra_after->>'source_coverage_sha256'=rb->>'source_coverage_sha256'
 then raise exception 'Owner private updates were not reflected independently';end if;
end $qa$;
rollback;
select 'PASS: 69 family visibility report includes 42 shared families; shared edits change both recipients, private edits affect owner only, no plaintext or archival readiness; rollback' result;
