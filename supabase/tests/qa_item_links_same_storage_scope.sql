-- QA: account-only links stay with the same owner, pair links only with
-- a current shared space; mixed/private-in-couple links fail. Rollback.
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
 outsider uuid:=current_setting('qa.other')::uuid;
 pair uuid:=current_setting('qa.space')::uuid;
 a uuid;b uuid;c uuid;d uuid;mine uuid;both uuid;n int;
BEGIN
 IF own IS NULL OR peer IS NULL OR outsider IS NULL OR pair IS NULL THEN
 RAISE EXCEPTION 'QA needs owner, partner and outsider'; END IF;
 INSERT INTO public.notes(private_space_id,created_by,title,body,visibility)
 VALUES(own,own,'QA private A','note','private') RETURNING id INTO a;
 INSERT INTO public.notes(private_space_id,created_by,title,body,visibility)
 VALUES(own,own,'QA private B','note','private') RETURNING id INTO b;
 INSERT INTO public.notes(space_id,created_by,title,body,visibility)
 VALUES(pair,own,'QA shared A','note','shared') RETURNING id INTO c;
 INSERT INTO public.notes(space_id,created_by,title,body,visibility)
 VALUES(pair,own,'QA shared B','note','shared') RETURNING id INTO d;
 INSERT INTO public.item_links(private_space_id,from_kind,from_id,to_kind,to_id)
 VALUES(own,'note',a,'note',b) RETURNING id INTO mine;
 INSERT INTO public.item_links(space_id,from_kind,from_id,to_kind,to_id)
 VALUES(pair,'note',c,'note',d) RETURNING id INTO both;
 SELECT count(*) INTO n FROM public.item_links WHERE id=mine;
 IF n<>1 THEN RAISE EXCEPTION 'Owner cannot see account-owned item link';END IF;
 SELECT count(*) INTO n FROM public.item_links WHERE id=both;
 IF n<>1 THEN RAISE EXCEPTION 'Owner cannot see current shared item link';END IF;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO n FROM public.item_links WHERE id=mine;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees personal link';END IF;
 SELECT count(*) INTO n FROM public.item_links WHERE id=both;
 IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see shared link';END IF;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 SELECT count(*) INTO n FROM public.item_links WHERE id IN(mine,both);
 IF n<>0 THEN RAISE EXCEPTION 'Outsider sees personal or pair link';END IF;
 PERFORM set_config('request.jwt.claim.sub',own::text,true);
 BEGIN
  INSERT INTO public.item_links(space_id,from_kind,from_id,to_kind,to_id)
  VALUES(pair,'note',a,'note',d);
  RAISE EXCEPTION 'BUG: private endpoint carried into couple link';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private endpoint carried into couple link' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.item_links(private_space_id,from_kind,from_id,to_kind,to_id)
  VALUES(own,'note',a,'note',c);
  RAISE EXCEPTION 'BUG: shared endpoint carried into account link';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: shared endpoint carried into account link' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.item_links SET space_id=pair,private_space_id=NULL WHERE id=mine;
  RAISE EXCEPTION 'BUG: personal link transferred to couple';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: personal link transferred to couple' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.item_links SET to_id=c WHERE id=mine;
  RAISE EXCEPTION 'BUG: personal link destination changed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: personal link destination changed' THEN RAISE;END IF;END;
 UPDATE public.item_links SET unlinked_at=now() WHERE id=mine;
 SELECT count(*) INTO n FROM public.item_links WHERE id=mine AND unlinked_at IS NOT NULL;
 IF n<>1 THEN RAISE EXCEPTION 'Owner cannot unlink personal items';END IF;
 BEGIN
  UPDATE public.item_links SET unlinked_at=NULL WHERE id=mine;
  RAISE EXCEPTION 'BUG: old item link silently restored';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: old item link silently restored' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS personal and current-pair item links exact endpoint scope; outsider/partner isolation and immutability; rolled back' result;