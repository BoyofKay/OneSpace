-- QA relationship-bound custom gestures and automated schedules, rollback.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE own uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 outside uuid:=current_setting('qa.outside')::uuid;
 couple uuid:=current_setting('qa.space')::uuid;
 templ uuid;sch uuid;n int;
BEGIN
 IF own IS NULL OR peer IS NULL OR outside IS NULL THEN
  RAISE EXCEPTION 'QA member/outsider fixture missing';END IF;
 INSERT INTO public.gesture_templates(space_id,creator_id,recipient_id,kind,title,message)
 VALUES(couple,own,peer,'hug','QA current partner','QA paired-only hug')
 RETURNING id INTO templ;
 INSERT INTO public.gesture_schedules(space_id,sender_id,recipient_id,moment,enabled)
 VALUES(couple,own,peer,'goodnight',false) RETURNING id INTO sch;
 SELECT count(*) INTO n FROM public.gesture_templates WHERE id=templ;
 IF n<>1 THEN RAISE EXCEPTION 'Sender cannot see custom gesture';END IF;
 UPDATE public.gesture_templates SET message='QA changed for current partner' WHERE id=templ;
 SELECT count(*) INTO n FROM public.gesture_schedules WHERE id=sch;
 IF n<>1 THEN RAISE EXCEPTION 'Sender cannot see own schedule';END IF;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO n FROM public.gesture_templates WHERE id=templ;
 IF n<>0 THEN RAISE EXCEPTION 'Recipient can read sender-only private template';END IF;
 SELECT count(*) INTO n FROM public.gesture_schedules WHERE id=sch;
 IF n<>0 THEN RAISE EXCEPTION 'Recipient can see sender schedule';END IF;
 PERFORM set_config('request.jwt.claim.sub',outside::text,true);
 SELECT count(*) INTO n FROM public.gesture_templates WHERE id=templ;
 IF n<>0 THEN RAISE EXCEPTION 'Outsider reads old couple gesture';END IF;
 PERFORM set_config('request.jwt.claim.sub',own::text,true);
 BEGIN
  UPDATE public.gesture_templates SET recipient_id=outside WHERE id=templ;
  RAISE EXCEPTION 'BUG: template readdressed to future partner';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.gesture_schedules SET private_space_id=own,space_id=NULL WHERE id=sch;
  RAISE EXCEPTION 'BUG: partner schedule moved to personal store';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.gesture_templates(space_id,creator_id,recipient_id,kind,title,message)
  VALUES(couple,own,outside,'hug','Old future partner','Should reject');
  RAISE EXCEPTION 'BUG: template addresses nonpartner';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS current-pair-only gesture templates/schedules, sender-only access and immutable recipient/scope; rolled back' result;