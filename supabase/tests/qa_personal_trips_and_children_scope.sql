-- QA only: full parent/child owner, current partner and outsider isolation. Rollback.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.couple',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.couple') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.other',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.couple') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE own uuid:=current_setting('qa.owner')::uuid;
peer uuid:=current_setting('qa.peer')::uuid;
outside uuid:=current_setting('qa.other')::uuid;
couple uuid:=current_setting('qa.couple')::uuid;
personal uuid; shared uuid; i_personal uuid; i_shared uuid;
f_personal uuid; m_personal uuid; n integer;
BEGIN
IF own IS NULL OR peer IS NULL OR outside IS NULL OR couple IS NULL THEN
 RAISE EXCEPTION 'QA pair and unrelated account required'; END IF;
INSERT INTO public.shared_trips(private_space_id,created_by,visibility,title,travel_mode)
 VALUES(own,own,'private','QA personal journey rollback','road') RETURNING id INTO personal;
INSERT INTO public.shared_trips(space_id,created_by,visibility,title,travel_mode)
 VALUES(couple,own,'shared','QA shared journey rollback','road') RETURNING id INTO shared;
INSERT INTO public.trip_items(trip_id,created_by,kind,title)
 VALUES(personal,own,'note','QA personal itinerary') RETURNING id INTO i_personal;
INSERT INTO public.trip_items(trip_id,created_by,kind,title)
 VALUES(shared,own,'note','QA shared itinerary') RETURNING id INTO i_shared;
INSERT INTO public.trip_flight_options(trip_id,created_by,title)
 VALUES(personal,own,'QA personal flight option') RETURNING id INTO f_personal;
INSERT INTO public.trip_messages(trip_id,created_by,body)
 VALUES(personal,own,'QA personal trip message') RETURNING id INTO m_personal;
UPDATE public.trip_items SET details='Owner changed personal itinerary' WHERE id=i_personal;
SELECT count(*) INTO n FROM public.trip_revisions WHERE trip_id=personal AND record_id=i_personal;
IF n=0 THEN RAISE EXCEPTION 'Owner missing trip revision'; END IF;
SELECT count(*) INTO n FROM public.record_action_history WHERE record_id=personal AND private_space_id=own;
IF n=0 THEN RAISE EXCEPTION 'Owner missing private trip action history'; END IF;
PERFORM set_config('request.jwt.claim.sub',peer::text,true);
SELECT count(*) INTO n FROM public.shared_trips WHERE id=personal;
IF n<>0 THEN RAISE EXCEPTION 'Partner sees private trip';END IF;
SELECT count(*) INTO n FROM public.trip_items WHERE id=i_personal;
IF n<>0 THEN RAISE EXCEPTION 'Partner sees private itinerary';END IF;
SELECT count(*) INTO n FROM public.trip_flight_options WHERE id=f_personal;
IF n<>0 THEN RAISE EXCEPTION 'Partner sees private flight';END IF;
SELECT count(*) INTO n FROM public.trip_messages WHERE id=m_personal;
IF n<>0 THEN RAISE EXCEPTION 'Partner sees private trip message';END IF;
SELECT count(*) INTO n FROM public.trip_revisions WHERE trip_id=personal;
IF n<>0 THEN RAISE EXCEPTION 'Partner sees private trip revisions';END IF;
SELECT count(*) INTO n FROM public.shared_trips WHERE id=shared;
IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see current-couple trip';END IF;
SELECT count(*) INTO n FROM public.trip_items WHERE id=i_shared;
IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see current-couple itinerary';END IF;
PERFORM set_config('request.jwt.claim.sub',outside::text,true);
SELECT count(*) INTO n FROM public.shared_trips WHERE id IN(personal,shared);
IF n<>0 THEN RAISE EXCEPTION 'Outsider sees trips';END IF;
SELECT count(*) INTO n FROM public.trip_items WHERE id IN(i_personal,i_shared);
IF n<>0 THEN RAISE EXCEPTION 'Outsider sees itineraries';END IF;
PERFORM set_config('request.jwt.claim.sub',own::text,true);
BEGIN
 UPDATE public.shared_trips SET visibility='shared' WHERE id=personal;
 RAISE EXCEPTION 'BUG: personal trip visibility transfer allowed';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: personal trip visibility transfer allowed' THEN RAISE;END IF;END;
BEGIN
 UPDATE public.trip_items SET trip_id=shared WHERE id=i_personal;
 RAISE EXCEPTION 'BUG: personal itinerary moved to couple';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: personal itinerary moved to couple' THEN RAISE;END IF;END;
BEGIN
 INSERT INTO public.shared_trips(space_id,created_by,visibility,title) VALUES(couple,own,'private','QA stale private journey');
 RAISE EXCEPTION 'BUG: old couple-private Trip was saved';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: old couple-private Trip was saved' THEN RAISE;END IF;END;
BEGIN
 INSERT INTO public.trip_attachments(trip_id,created_by,title,file_name,mime_type,file_size,object_path)
 VALUES(personal,own,'Private doc','test.pdf','application/pdf',20,personal::text||'/'||own::text||'/'||gen_random_uuid()::text||'.pdf');
 RAISE EXCEPTION 'BUG: private doc accepted in shared Storage';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private doc accepted in shared Storage' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS account/private and current pair Trips children/flight/message/revisions/audit; old writes and files blocked, rolled back' result;