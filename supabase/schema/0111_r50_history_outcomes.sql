-- OneSpace R50 - Global patterns: change log records outcomes.
-- Spec 2.4/2.6: every outcome and removal is a row in the change log.
-- The two R40/R44 audit triggers now name outcomes instead of "edited":
-- status -> completed / celebrated / enjoyed / booked  => 'completed'
-- status -> cancelled                                 => 'cancelled'
-- Non-destructive: only the action label of future rows changes.
-- The action list must allow the new labels (applied as r50_history_allow_completed).
alter table public.record_action_history drop constraint if exists record_action_history_action_check,
 add constraint record_action_history_action_check check (action = any (array['created','edited','archived','restored','cancelled','reopened','completed','missed']));

do $m$
declare f text; d text;
 o text:=$o$ else 'edited' end;$o$;
 n text:=$n$ when (before->>'status') is distinct from (after->>'status') and (after->>'status') in ('completed','celebrated','enjoyed','booked') then 'completed' when (before->>'status') is distinct from (after->>'status') and (after->>'status')='cancelled' then 'cancelled' else 'edited' end;$n$;
begin
 foreach f in array array['private.capture_record_action()','private.audit_additional_record_action()'] loop
   d:=pg_get_functiondef(f::regprocedure);
   if position(o in d)=0 then raise exception 'pattern not found in %',f; end if;
   if position('''booked'') then ''completed''' in d)>0 then continue; end if;
   execute replace(d,o,n);
 end loop;
end $m$;
