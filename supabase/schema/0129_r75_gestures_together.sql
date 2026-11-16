-- R75 (Ahmed): automatic love messages must never say "from miles away" to a
-- couple who lives together. Mirrors GesturePoolRules.distance in the app.
-- Applied 16 Nov 2026; verified the patch and the word filter.
create or replace function private.gesture_mentions_distance(p_text text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_text,'') ~* '\mmiles\M|distance|from afar|far away|time zones?\M|see you again|wish you were here|will be home|until I can see';
$$;

do $m$
declare d text; before text;
begin
  d := pg_get_functiondef('private.send_due_gestures(timestamptz)'::regprocedure);
  before := d;
  d := replace(d,
    '  if coalesce(array_length(phrases,1),0)=0 then continue; end if;',
    E'  -- R75: living together -> drop built-in lines about distance.\n'
    '  if exists(select 1 from public.spaces sp where sp.id=cfg.space_id\n'
    '      and sp.relationship_mode=''living_together'') then\n'
    '    select array_agg(u.x order by u.o) into phrases\n'
    '      from unnest(phrases) with ordinality as u(x,o)\n'
    '     where not private.gesture_mentions_distance(u.x);\n'
    '  end if;\n'
    '  if coalesce(array_length(phrases,1),0)=0 then continue; end if;');
  if d = before then raise exception 'send_due_gestures was not patched'; end if;
  execute d;
end $m$;
