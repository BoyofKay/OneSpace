-- QA-only signed-in lifecycle regression. One transaction, always rolled back.
-- Requires a QA database with at least one paired space and one solo owner.
BEGIN;
DO $setup$
DECLARE pair record; solo record;
BEGIN
  SELECT s.id AS space_id,s.created_by AS owner_id,
    (SELECT sm.user_id FROM public.space_members sm
      WHERE sm.space_id=s.id AND sm.user_id<>s.created_by LIMIT 1) partner_id
  INTO pair
  FROM public.spaces s
  WHERE (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=s.id)=2
  LIMIT 1;
  IF pair.space_id IS NULL OR pair.partner_id IS NULL THEN
    RAISE EXCEPTION 'Requires one QA paired space';
  END IF;
  SELECT s.id,s.created_by INTO solo FROM public.spaces s
    WHERE (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=s.id)=1
    LIMIT 1;
  IF solo.id IS NULL THEN RAISE EXCEPTION 'Requires one QA solo space'; END IF;
  IF EXISTS(SELECT 1 FROM public.space_lifecycle_jobs j
    WHERE j.original_space_id IN (pair.space_id,solo.id)
      AND j.status NOT IN ('completed','failed','cancelled')) THEN
    RAISE EXCEPTION 'Refusing test on space with active real lifecycle job';
  END IF;
  PERFORM set_config('qa.test.owner',pair.owner_id::text,true);
  PERFORM set_config('qa.test.partner',pair.partner_id::text,true);
  PERFORM set_config('qa.test.paired_space',pair.space_id::text,true);
  PERFORM set_config('qa.test.solo_owner',solo.created_by::text,true);
  PERFORM set_config('qa.test.solo_space',solo.id::text,true);
END $setup$;
SET LOCAL ROLE authenticated;
DO $tests$
DECLARE response jsonb; readiness jsonb; job uuid; denied boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',current_setting('qa.test.owner'),true);
  response:=public.my_space_lifecycle_status();
  IF response->>'role'<>'owner' OR response->>'can_leave'<>'false'
    OR response->>'can_remove_partner'<>'true' THEN
    RAISE EXCEPTION 'Owner permissions incorrect: %',response; END IF;
  denied:=false;
  BEGIN PERFORM public.request_space_lifecycle_action('partner_leaves');
  EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Owner was able to leave'; END IF;
  response:=public.request_space_lifecycle_action('owner_removes_partner');
  IF response->>'separation_completed'<>'false'
    OR response->>'status'<>'awaiting_verified_export' THEN
    RAISE EXCEPTION 'Removal incorrectly marked completed'; END IF;
  job:=(response->>'id')::uuid;
  denied:=false;
  BEGIN PERFORM public.request_space_lifecycle_action('owner_deletes_space');
  EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Duplicate lifecycle request accepted'; END IF;
  readiness:=public.space_lifecycle_readiness();
  IF readiness->>'safe_to_separate'<>'false' THEN
    RAISE EXCEPTION 'Unsafe separation gate'; END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('qa.test.partner'),true);
  response:=public.my_space_lifecycle_status();
  IF response->>'role'<>'partner' OR response->>'can_delete_space'<>'false'
    OR response->>'can_leave'<>'true' THEN
    RAISE EXCEPTION 'Partner permissions incorrect'; END IF;
  IF public.cancel_space_lifecycle_action(job) THEN
    RAISE EXCEPTION 'Partner cancelled an owner request'; END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('qa.test.owner'),true);
  IF NOT public.cancel_space_lifecycle_action(job) THEN
    RAISE EXCEPTION 'Owner cancellation failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('qa.test.partner'),true);
  denied:=false;
  BEGIN PERFORM public.request_space_lifecycle_action('owner_deletes_space');
  EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Partner could delete space'; END IF;
  response:=public.request_space_lifecycle_action('partner_leaves');
  IF response->>'separation_completed'<>'false' THEN
    RAISE EXCEPTION 'Leaving prematurely completed'; END IF;
  IF NOT public.cancel_space_lifecycle_action((response->>'id')::uuid) THEN
    RAISE EXCEPTION 'Partner cancellation failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('qa.test.solo_owner'),true);
  response:=public.my_space_lifecycle_status();
  IF response->>'role'<>'owner' OR response->>'can_remove_partner'<>'false'
    OR response->>'can_delete_space'<>'true' THEN
    RAISE EXCEPTION 'Solo permissions incorrect'; END IF;
  denied:=false;
  BEGIN PERFORM public.request_space_lifecycle_action('owner_removes_partner');
  EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Removed nonexistent partner'; END IF;
  response:=public.request_space_lifecycle_action('owner_deletes_space');
  IF response->>'separation_completed'<>'false' THEN
    RAISE EXCEPTION 'Solo space prematurely deleted'; END IF;
  IF NOT public.cancel_space_lifecycle_action((response->>'id')::uuid) THEN
    RAISE EXCEPTION 'Solo cancellation failed'; END IF;
  IF (SELECT count(*) FROM public.space_members
       WHERE space_id=current_setting('qa.test.solo_space')::uuid)<>1 THEN
    RAISE EXCEPTION 'Solo membership changed'; END IF;
END $tests$;
ROLLBACK;
SELECT 'QA lifecycle owner, partner, solo, IDOR, duplicate, cancel, gate: PASS (rolled back)' AS result;
