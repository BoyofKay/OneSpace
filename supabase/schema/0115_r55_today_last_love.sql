-- OneSpace R55: the built-in "a little love" nudge on Today (replaces the
-- manual "Remind me to send a little love" button). onespace_today now also
-- returns last_love_sent_at: when I last sent my partner a gesture.
-- Applied live as r55_today_last_love_sent. Non-destructive.
do $m$
declare d text:=pg_get_functiondef('public.onespace_today(date)'::regprocedure);
 o text:=$o$   'on_this_day',$o$;
 n text:=$n$   'last_love_sent_at',(select max(g.created_at) from public.partner_gestures g
      where g.space_id=(snap->>'space_id')::uuid and g.sender_id=auth.uid()),
   'on_this_day',$n$;
begin
 if position('last_love_sent_at' in d)>0 then return; end if;
 if position(o in d)=0 then raise exception 'pattern not found'; end if;
 execute replace(d,o,n);
end $m$;

-- R55 (applied as r55_realtime_letters_and_revisions): two screens streamed
-- tables that were not in the realtime publication, so their live channel
-- failed shortly after opening ("Unable to load letters"). Row-level security
-- still applies to realtime.
do $m$
declare t text;
begin
 foreach t in array array['couple_letters','activity_revisions'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
     execute format('alter publication supabase_realtime add table public.%I', t);
   end if;
 end loop;
end $m$;
