-- Deployed 20261113110121 onespace_r9_activity_and_component_soft_removal_audit
-- R9: audit soft removal and restoration alongside ordinary edits.
alter table public.activity_revisions
 add column if not exists change_kind text not null default 'edited'
 check (change_kind in ('edited','archived','restored'));
alter table public.activity_component_revisions
 add column if not exists change_kind text not null default 'edited'
 check (change_kind in ('edited','removed','restored'));

create or replace function private.audit_activity_update()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_kind text;
begin
 v_kind:=case
   when old.archived_at is null and new.archived_at is not null then 'archived'
   when old.archived_at is not null and new.archived_at is null then 'restored'
   else 'edited'
 end;
 if (old.title,old.body,old.stage,old.priority,old.due_on,old.archived_at)
   is distinct from
    (new.title,new.body,new.stage,new.priority,new.due_on,new.archived_at)
 then
   insert into public.activity_revisions
   (activity_id,changed_by,old_title,new_title,old_body,new_body,
    old_stage,new_stage,old_priority,new_priority,old_due_on,new_due_on,change_kind)
   values(new.id,auth.uid(),old.title,new.title,old.body,new.body,
     old.stage,new.stage,old.priority,new.priority,old.due_on,new.due_on,v_kind);
 end if;
 return new;
end;
$$;

create or replace function private.audit_component_update()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_kind text;
begin
 v_kind:=case
   when old.archived_at is null and new.archived_at is not null then 'removed'
   when old.archived_at is not null and new.archived_at is null then 'restored'
   else 'edited'
 end;
 if (old.label,old.payload,old.archived_at) is distinct from
    (new.label,new.payload,new.archived_at) then
   insert into public.activity_component_revisions
   (activity_id,component_id,changed_by,old_label,new_label,
    old_payload,new_payload,change_kind)
   values(new.activity_id,new.id,auth.uid(),old.label,new.label,
    old.payload,new.payload,v_kind);
 end if;
 return new;
end;
$$;
