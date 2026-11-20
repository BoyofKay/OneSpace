-- QA letters: private drafts never become couple records in place; test rolled back.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.couple',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.couple') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.other',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.couple') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE owner_id uuid:=current_setting('qa.owner')::uuid;
 peer_id uuid:=current_setting('qa.peer')::uuid;
 other_id uuid:=current_setting('qa.other')::uuid;
 pair_id uuid:=current_setting('qa.couple')::uuid;
 draft_id uuid;sent_id uuid;n int;
BEGIN
 IF owner_id IS NULL OR peer_id IS NULL OR other_id IS NULL THEN
   RAISE EXCEPTION 'QA owner, partner and outsider required';END IF;
 INSERT INTO public.couple_letters(private_space_id,author_id,title,body,status)
 VALUES(owner_id,owner_id,'QA unsent draft rollback','Personal words','draft')
 RETURNING id INTO draft_id;
 INSERT INTO public.couple_letters(space_id,author_id,title,body,status)
 VALUES(pair_id,owner_id,'QA pair sent rollback','Shared words','sent')
 RETURNING id INTO sent_id;
 SELECT count(*) INTO n FROM public.couple_letters WHERE id=draft_id;
 IF n<>1 THEN RAISE EXCEPTION 'Owner cannot read private draft';END IF;
 UPDATE public.couple_letters SET body='Edited personal draft' WHERE id=draft_id;
 PERFORM set_config('request.jwt.claim.sub',peer_id::text,true);
 SELECT count(*) INTO n FROM public.couple_letters WHERE id=draft_id;
 IF n<>0 THEN RAISE EXCEPTION 'Partner read personal draft';END IF;
 SELECT count(*) INTO n FROM public.couple_letters WHERE id=sent_id;
 IF n<>1 THEN RAISE EXCEPTION 'Partner cannot read sent current-pair letter';END IF;
 INSERT INTO public.couple_letter_reads(letter_id,reader_id) VALUES(sent_id,peer_id);
 SELECT count(*) INTO n FROM public.couple_letter_reads WHERE letter_id=sent_id;
 IF n<>1 THEN RAISE EXCEPTION 'Partner receipt not recorded';END IF;
 PERFORM set_config('request.jwt.claim.sub',other_id::text,true);
 SELECT count(*) INTO n FROM public.couple_letters WHERE id IN(draft_id,sent_id);
 IF n<>0 THEN RAISE EXCEPTION 'Outsider accessed pair/private letters';END IF;
 PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
 BEGIN
  UPDATE public.couple_letters SET status='sent' WHERE id=draft_id;
  RAISE EXCEPTION 'BUG: private draft sent without a current-pair copy';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private draft sent without a current-pair copy' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.couple_letters SET space_id=pair_id,private_space_id=NULL WHERE id=draft_id;
  RAISE EXCEPTION 'BUG: private draft moved to couple';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private draft moved to couple' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.couple_letters(space_id,author_id,title,body,status)
    VALUES(pair_id,owner_id,'QA stale couple private draft','Legacy','draft');
  -- A current-pair draft is permitted but remains tied to the current couple.
  -- The account-owned draft above remains independent.
 END;
END $qa$;
ROLLBACK;
SELECT 'PASS account letter draft isolation, current-pair sent/read, blocked status transfer; rolled back' result;