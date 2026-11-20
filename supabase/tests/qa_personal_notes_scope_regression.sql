-- QA signed-in RLS regression for account-owned Notes. Fully rolled back.
-- Test requires two different members in existing QA, no persistent test rows.
begin;
select set_config('qa.note_a',
  (select m.user_id::text from public.space_members m
    group by m.user_id order by m.user_id limit 1),true);
select set_config('qa.note_b',
  (select m.user_id::text from public.space_members m
    where m.user_id::text<>current_setting('qa.note_a')
    order by m.user_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.note_a'),true);
set local role authenticated;
do $qa$
declare a uuid:=current_setting('qa.note_a')::uuid;
 b uuid:=current_setting('qa.note_b')::uuid;
 row_id uuid; n integer;
begin
 insert into public.notes(private_space_id,created_by,visibility,title,body)
 values (a,a,'private','Isolated temporary note','QA audit test')
 returning id into row_id;
 select count(*) into n from public.notes where id=row_id;
 if n<>1 then raise exception 'Private owner cannot read note';end if;
 select count(*) into n from public.record_action_history h
 where h.record_kind='note' and h.record_id=row_id and h.private_space_id=a;
 if n<>1 then raise exception 'Private note audit missing: %',n;end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 select count(*) into n from public.notes where id=row_id;
 if n<>0 then raise exception 'Foreign user sees personal note';end if;
 select count(*) into n from public.record_action_history
 where record_kind='note' and record_id=row_id;
 if n<>0 then raise exception 'Foreign user sees personal note audit';end if;
 begin
  insert into public.notes(private_space_id,created_by,visibility,title,body)
  values(a,b,'private','Forged owner','Should be rejected');
  raise exception 'BUG: owner spoofing accepted';
 exception when check_violation or insufficient_privilege or raise_exception then
  if sqlerrm='BUG: owner spoofing accepted' then raise;end if;
 end;
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set title='Private note updated' where id=row_id;
 select count(*) into n from public.notes
 where id=row_id and title='Private note updated';
 if n<>1 then raise exception 'Owner cannot update private note';end if;
end $qa$;
rollback;
