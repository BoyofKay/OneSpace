begin;
do $qa$
declare sid uuid;a uuid;b uuid;note_id uuid;expid uuid;hidden_id uuid;
 report_a jsonb;report_b jsonb;oldhash text;newhash text;err text;
begin
select s.id,s.created_by,sm.user_id into sid,a,b
from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
if sid is null then raise exception 'QA pair missing';end if;
if has_function_privilege('anon','public.qa_archive_source_coverage_report()','execute')
or has_function_privilege('anon','private.qa_archive_source_coverage_report()','execute')
then raise exception 'Full archive coverage report accessible anonymously';end if;
perform set_config('request.jwt.claim.sub',a::text,true);
insert into public.notes(space_id,created_by,title,body,visibility)
values(sid,a,'QA census full written note','Private writing remains owned by A','private')
returning id into note_id;
insert into public.shared_experiences(space_id,created_by,category,title)
values(sid,a,'movie','QA shared census movie') returning id into expid;
insert into public.shared_experience_comments(experience_id,created_by,body)
values(expid,a,'A visible shared thought');
insert into public.shared_experience_comments(experience_id,created_by,body)
values(expid,b,'B author-only comment after archiving') returning id into hidden_id;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
report_a:=public.qa_archive_source_coverage_report();
if (report_a->>'classified_table_types')::int<>69
 or (report_a->>'private_eligible_table_types_censused')::int<>46
 or (report_a->>'shared_only_table_types_censused')::int<>12
 or (report_a->>'media_excluded_table_types')::int<>4
 or (report_a->>'operational_excluded_table_types')::int<>7
 or (report_a->>'table_types_accounted_for')::int<>69
 or report_a->>'mixed_visibility_shared_rows_censused'<>'false'
 or report_a->>'full_per_row_source_manifest_complete'<>'false'
 or report_a->>'independently_verified_encrypted_archive'<>'false'
 or report_a->>'can_restore'<>'false'
 or report_a->>'safe_to_archive'<>'false'
 or report_a::text like '%Private writing remains owned by A%'
 or report_a::text like '%B author-only comment after archiving%'
 then raise exception 'Unified source report has missing privacy or unsafe archive claim';end if;
oldhash:=report_a->>'source_coverage_sha256';
report_b:=public.qa_archive_source_coverage_report();
if report_b->>'source_coverage_sha256'<>oldhash
 then raise exception 'Stable source fingerprint changed with no writes';end if;
perform set_config('request.jwt.claim.sub',b::text,true);
report_b:=public.qa_archive_source_coverage_report();
if report_b->>'source_coverage_sha256'=oldhash then
 raise exception 'Owner A and B source fingerprints were equal';end if;
if (report_b->>'private_source_rows_counted')::int<>0 then
 raise exception 'Partner B source inventory included owner A private note';end if;
perform set_config('role','postgres',true);
update public.shared_experience_comments set archived_at=now()
where id=hidden_id;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
report_a:=public.qa_archive_source_coverage_report();
newhash:=report_a->>'source_coverage_sha256';
if newhash=oldhash then raise exception 'Archived B comment did not change A visible shared count hash';end if;
if (select (x->>'visible_shared_rows')::int
 from jsonb_array_elements(report_a->'shared_only_per_table') x
 where x->>'source_table'='shared_experience_comments')<>1
 then raise exception 'A retains partner B archived comment';end if;
perform set_config('request.jwt.claim.sub',b::text,true);
report_b:=public.qa_archive_source_coverage_report();
if (select (x->>'visible_shared_rows')::int
 from jsonb_array_elements(report_b->'shared_only_per_table') x
 where x->>'source_table'='shared_experience_comments')<>2
 then raise exception 'Author B lost own archived comment';end if;
perform set_config('role','postgres',true);
create table public.qa_unregistered_archive_coverage_0205(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id),
 created_by uuid not null references auth.users(id),
 content text
);
alter table public.qa_unregistered_archive_coverage_0205 enable row level security;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
begin
 perform public.qa_archive_source_coverage_report();
 raise exception 'Future unclassified source table did not invalidate manifest';
exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Archive classification schema is out of date' then
 raise exception 'Wrong future schema denial: %',err;end if;
end;
end $qa$;
rollback;
select 'PASS: unified 69-type policy census, owner private and archived shared comment privacy, 11 exclusions, changing hashes, future-schema fail closed and no restoration; rollback' result;
