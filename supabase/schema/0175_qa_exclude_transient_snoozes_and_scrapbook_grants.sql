-- QA 0175: exclude transient per-recipient snoozes and scrapbook access grants.
-- Content remains in activities, memories and other authorized structured tables.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
     where source_table in ('activity_attention_snoozes','scrapbook_invites')
       and relation_kind='dependent' and disposition='review_required'
       and not approved)<>2 then
   raise exception 'Operational archive exclusions require new scope review';
 end if;
end $guard$;
update private.qa_archive_table_policy
set disposition='system_excluded',approved=true,reviewed_at=now(),
    policy_note=case source_table
      when 'activity_attention_snoozes' then
        'Recipient-specific transient attention delay; source activity remains archived but an obsolete snooze must not resurrect'
      else
        'Revocable scrapbook collaboration invitation/access state; source memory/page content is separate and authorization must not restore into a new partnership'
    end
where source_table in ('activity_attention_snoozes','scrapbook_invites')
  and relation_kind='dependent' and disposition='review_required'
  and not approved;
-- No lifecycle safety switch is changed.
