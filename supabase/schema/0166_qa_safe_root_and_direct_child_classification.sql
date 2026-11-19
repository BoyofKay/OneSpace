-- QA-only milestone 2: classify independently reviewed scopes. NO data export or lifecycle execution.
-- The catalog remains FAIL CLOSED until all supported children have been serialized
-- with explicit authorship/space checks, verified encryption and real restoration.
do $guard$
begin
  if (select count(*) from private.qa_archive_table_policy
      where approved=false and disposition='review_required'
      and source_table=any(array[
        'calendar_partner_reminders','gesture_message_overrides','gesture_schedules',
        'gesture_templates','object_shares','partner_checkin_requests',
        'space_notifications','space_tags','memory_photo_revisions',
        'occasion_plan_steps','occasion_proposals','shared_experience_interests',
        'shared_experience_reviews','trip_flight_options','trip_items','trip_messages'
      ]))<>16 then
    raise exception 'Archive catalog changed; re-review QA 0166 before applying';
  end if;
end $guard$;

-- Category definitions:
-- owner_private: only the matching author/sender/owner, never their partner
-- shared_only: current pair's mutual content; old shared archives remain read-only
-- private_shared: inherit parent record scope; private follows original author
-- system_excluded: operational delivery/sharing grants, not portable content
-- media_excluded: image/photo revision pointers and snapshots, not documents/text
with policy(source_table,relation_kind,disposition,policy_note) as (values
 ('calendar_partner_reminders','root','system_excluded','Event notification delivery tracking, not the calendar event; original space_events is archived'),
 ('gesture_message_overrides','root','owner_private','Only owner_id may archive their customized gesture text; never partner-visible unless sent separately'),
 ('gesture_schedules','root','owner_private','Only sender_id owns scheduling preference; recipient cannot inherit sender schedule'),
 ('gesture_templates','root','owner_private','Only creator_id owns reusable draft template; sending separately creates shared content'),
 ('object_shares','root','system_excluded','Revocable cross-person access grants must NOT survive separation or restore'),
 ('partner_checkin_requests','root','shared_only','Recipient and sender are the two RLS-authorized space members; archive old exchange read-only'),
 ('space_notifications','root','system_excluded','Delivery/read/push metadata is temporary; source content separately archived where eligible'),
 ('space_tags','root','shared_only','Relationship tag labels are mutual space metadata, never copied into a future relationship'),
 ('memory_photo_revisions','dependent','media_excluded','Photo/image revision snapshots and media references excluded by approved no-media policy'),
 ('occasion_plan_steps','dependent','private_shared','Inherit occasion_plans privacy; created_by must match current space membership'),
 ('occasion_proposals','dependent','private_shared','Inherit occasion_plans privacy; proposal is not an independent shared grant'),
 ('shared_experience_interests','dependent','shared_only','Inherit shared_experiences scope; user_id must be a member when packaging'),
 ('shared_experience_reviews','dependent','shared_only','Inherit shared_experiences scope; reviewer must be a member when packaging'),
 ('trip_flight_options','dependent','private_shared','Inherit shared_trips visibility; parent and author must be validated at packaging'),
 ('trip_items','dependent','private_shared','Inherit shared_trips visibility; parent and author must be validated at packaging'),
 ('trip_messages','dependent','private_shared','Inherit shared_trips visibility; parent and author must be validated at packaging')
)
update private.qa_archive_table_policy t
set disposition=p.disposition, approved=true, reviewed_at=now(),
    policy_note=p.policy_note||'; scope approved ONLY, portable encrypted serializer and restore pending'
from policy p
where t.source_table=p.source_table and t.relation_kind=p.relation_kind
  and t.disposition='review_required' and t.approved=false;
-- DO NOT change the public readiness flag; safe_to_archive and safe_to_separate remain false.
