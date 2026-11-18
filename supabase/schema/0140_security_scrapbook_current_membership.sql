-- OneSpace security hardening (2026-11-18)
-- Prevent a former space member from inviting a new member to a scrapbook
-- they originally created. Function intentionally remains SECURITY DEFINER:
-- only its authenticated creator, while a current space member, may invoke.
-- Applied to OneSpace QA and OneSpace Production on 2026-11-18.

CREATE OR REPLACE FUNCTION public.invite_scrapbook_partner(p_memory_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare m record; partner uuid; me uuid:=auth.uid();
begin
 select id,space_id,created_by,visibility,memory_type,archived_at
 into m from public.memories where id=p_memory_id;
 if me is null or not found or m.created_by<>me or m.memory_type<>'scrapbook'
 or m.visibility<>'shared' or m.archived_at is not null
 or not private.is_space_member(m.space_id) then
  raise exception 'Only a current member who owns an active shared scrapbook can invite';
 end if;
 select user_id into partner from public.space_members
 where space_id=m.space_id and user_id<>me order by joined_at limit 1;
 if partner is null then raise exception 'Partner not connected';end if;
 insert into public.scrapbook_invites(memory_id,invited_user_id,invited_by,status)
 values(p_memory_id,partner,me,'pending')
 on conflict(memory_id,invited_user_id)
 do update set status='pending',responded_at=null,created_at=now()
 where public.scrapbook_invites.status='declined';
 insert into public.space_notifications(
 space_id,recipient_id,actor_id,kind,object_kind,object_id,
 headline,generated_automatically)
 values(m.space_id,partner,me,'scrapbook_invite','scrapbook',
  p_memory_id,'Your partner invited you to a scrapbook',true)
 on conflict(recipient_id,kind,object_id)
 do update set headline=excluded.headline,created_at=now(),read_at=null;
end $function$;
