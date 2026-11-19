-- QA 0212: use per-owner transaction advisory lock before quota scan.
CREATE OR REPLACE FUNCTION public.qa_subset_reserve_service(p_owner uuid, p_space uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare assigned_id uuid:=gen_random_uuid(); object_key text; n int;
begin
 if p_owner is null or p_space is null or not exists(
   select 1 from public.space_members sm
   where sm.user_id=p_owner and sm.space_id=p_space)
   or (select count(*) from public.space_members sm
       where sm.user_id=p_owner)<>1
 then raise exception 'QA subset owner/space mismatch';end if;
 -- Serialize active reservations by original user; two parallel uploads
 -- must not both observe a slot and exceed the three-file quota.
 perform pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended('qa-vault-subset:'||p_owner::text,0));
 select count(*) into n from private.qa_vault_subset_staging
 where owner_id=p_owner and state in ('pending','available')
   and expires_at>now();
 if n>=3 then raise exception 'QA subset staging quota exceeded';end if;
 object_key:=p_owner::text||'/qa-subsets/'||assigned_id::text||'.osa';
 insert into private.qa_vault_subset_staging(
 id,owner_id,source_space_id,object_path)
 values(assigned_id,p_owner,p_space,object_key);
 return jsonb_build_object('staging_id',assigned_id,
    'object_path',object_key,'is_verified_archive',false,
    'can_restore',false);
end $function$
;