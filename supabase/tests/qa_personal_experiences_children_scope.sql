-- QA personal and paired Experience root/child privacy test, rollback.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.other',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE o uuid:=current_setting('qa.owner')::uuid;
 p uuid:=current_setting('qa.peer')::uuid; x uuid:=current_setting('qa.other')::uuid;
 pair uuid:=current_setting('qa.space')::uuid;
 private_ex uuid;shared_ex uuid;comment_id uuid; n int;
BEGIN
 IF o IS NULL OR p IS NULL OR x IS NULL THEN RAISE EXCEPTION 'QA fixture missing';END IF;
 INSERT INTO public.shared_experiences(private_space_id,created_by,visibility,category,title)
 VALUES(o,o,'private','movie','QA private film') RETURNING id INTO private_ex;
 INSERT INTO public.shared_experiences(space_id,created_by,visibility,category,title)
 VALUES(pair,o,'shared','movie','QA shared film') RETURNING id INTO shared_ex;
 INSERT INTO public.shared_experience_comments(experience_id,created_by,body)
 VALUES(private_ex,o,'QA private comment') RETURNING id INTO comment_id;
 INSERT INTO public.shared_experience_interests(experience_id,user_id,choice)
 VALUES(private_ex,o,'yes');
 INSERT INTO public.shared_experience_reviews(experience_id,user_id,rating,review)
 VALUES(private_ex,o,4,'My private review');
 UPDATE public.shared_experiences SET description='Private plan revision' WHERE id=private_ex;
 SELECT count(*) INTO n FROM public.record_action_history WHERE record_id=private_ex AND private_space_id=o;
 IF n=0 THEN RAISE EXCEPTION 'Owner private Experience audit missing';END IF;
 SELECT count(*) INTO n FROM public.shared_experience_revisions WHERE experience_id=private_ex;
 IF n=0 THEN RAISE EXCEPTION 'Owner private Experience revision missing';END IF;
 SELECT count(*) INTO n FROM public.record_action_history
   WHERE record_id=comment_id AND record_kind='experience_comment'
     AND private_space_id=o;
 IF n=0 THEN RAISE EXCEPTION 'Owner private Experience comment audit missing';END IF;
 PERFORM set_config('request.jwt.claim.sub',p::text,true);
 SELECT count(*) INTO n FROM public.shared_experiences WHERE id=private_ex;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees personal Experience';END IF;
 SELECT count(*) INTO n FROM public.shared_experience_comments WHERE id=comment_id;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private comment';END IF;
 SELECT count(*) INTO n FROM public.shared_experience_reviews WHERE experience_id=private_ex;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private review';END IF;
 SELECT count(*) INTO n FROM public.shared_experience_interests WHERE experience_id=private_ex;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private interest';END IF;
 SELECT count(*) INTO n FROM public.shared_experience_revisions WHERE experience_id=private_ex;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private revision';END IF;
 SELECT count(*) INTO n FROM public.shared_experiences WHERE id=shared_ex;
 IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see shared Experience';END IF;
 PERFORM set_config('request.jwt.claim.sub',x::text,true);
 SELECT count(*) INTO n FROM public.shared_experiences WHERE id in(private_ex,shared_ex);
 IF n<>0 THEN RAISE EXCEPTION 'Outsider sees Experiences';END IF;
 PERFORM set_config('request.jwt.claim.sub',o::text,true);
 BEGIN
 UPDATE public.shared_experiences SET space_id=pair,private_space_id=NULL,visibility='shared'
 WHERE id=private_ex;
 RAISE EXCEPTION 'BUG: private Experience reparent';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private Experience reparent' THEN RAISE;END IF;END;
 BEGIN
 UPDATE public.shared_experience_comments SET experience_id=shared_ex WHERE id=comment_id;
 RAISE EXCEPTION 'BUG: private comment reparent';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private comment reparent' THEN RAISE;END IF;END;
 BEGIN
 INSERT INTO public.shared_experiences(space_id,created_by,visibility,category,title)
 VALUES(pair,o,'private','movie','QA old private shared Experience');
 RAISE EXCEPTION 'BUG: stale coupled Experience private write';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: stale coupled Experience private write' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS account/private and shared Experiences, comments/reviews/interests/revisions and audit; rolled back' result;