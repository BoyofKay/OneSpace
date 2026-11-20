-- QA account-owned gesture preferences; current-pair delivery only, rollback.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.other',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE own uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 other uuid:=current_setting('qa.other')::uuid;
 pair uuid:=current_setting('qa.space')::uuid;
 override_id uuid;sent_id uuid;n int;
BEGIN
 IF own IS NULL OR peer IS NULL OR other IS NULL OR pair IS NULL THEN
   RAISE EXCEPTION 'QA pair/outsider missing';END IF;
 INSERT INTO public.gesture_message_overrides(private_space_id,owner_id,kind,message_index,message)
 VALUES(own,own,'hug',4,'QA personal customized hug') RETURNING id INTO override_id;
 INSERT INTO public.partner_gestures(space_id,sender_id,recipient_id,kind,message)
 VALUES(pair,own,peer,'hug','QA sent shared hug') RETURNING id INTO sent_id;
 SELECT count(*) INTO n FROM public.gesture_message_overrides WHERE id=override_id;
 IF n<>1 THEN RAISE EXCEPTION 'Owner lost personal preset';END IF;
 UPDATE public.gesture_message_overrides SET message='QA new personal text' WHERE id=override_id;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO n FROM public.gesture_message_overrides WHERE id=override_id;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees owner gesture settings';END IF;
 SELECT count(*) INTO n FROM public.partner_gestures WHERE id=sent_id;
 IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see delivered gesture';END IF;
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 SELECT count(*) INTO n FROM public.gesture_message_overrides WHERE id=override_id;
 IF n<>0 THEN RAISE EXCEPTION 'Outsider sees preference';END IF;
 SELECT count(*) INTO n FROM public.partner_gestures WHERE id=sent_id;
 IF n<>0 THEN RAISE EXCEPTION 'Outsider sees delivered gesture';END IF;
 PERFORM set_config('request.jwt.claim.sub',own::text,true);
 BEGIN
  UPDATE public.gesture_message_overrides SET private_space_id=NULL,space_id=pair
  WHERE id=override_id;
  RAISE EXCEPTION 'BUG: preference ownership transfer';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: preference ownership transfer' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.gesture_message_overrides(space_id,owner_id,kind,message_index,message)
  VALUES(pair,own,'hug',5,'QA old scope');
  RAISE EXCEPTION 'BUG: old gesture override coupled scope';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: old gesture override coupled scope' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.partner_gestures(space_id,sender_id,recipient_id,kind,message)
  VALUES(pair,own,other,'hug','QA wrong recipient');
  RAISE EXCEPTION 'BUG: delivered gesture to nonpartner';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: delivered gesture to nonpartner' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS gesture preference owner isolation and paired delivery; rolled back' result;