-- QA 0173: explicit policy for task checklist descendants.
-- Child content inherits task visibility, but its actor must be validated.
-- Shared checklist completions remain part of the original couple's archived
-- history only. A private task must not absorb partner-authored descendants.
do $guard$
begin
  if (select count(*) from private.qa_archive_table_policy
      where source_table in ('task_checklist_items','task_checklist_checks')
      and relation_kind='dependent' and canonical_parent='tasks'
      and disposition='review_required' and not approved)<>2 then
    raise exception 'Checklist archive classification requires fresh review';
  end if;
end $guard$;
update private.qa_archive_table_policy
set disposition='private_shared',approved=true,reviewed_at=now(),
    policy_note='Inherit task privacy. Private items created_by, checks user_id and actual task_id must equal owner/parent. Any partner-authored descendant fails closed; shared historical pair data remains reference only. Mirroring verified, portable encryption/restore not yet implemented.'
where source_table in ('task_checklist_items','task_checklist_checks')
  and relation_kind='dependent' and canonical_parent='tasks'
  and disposition='review_required' and not approved;
-- Global safe_to_archive and safe_to_separate remain FALSE.
