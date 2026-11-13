-- Deployed 20261113120714 onespace_r10_creator_owned_gesture_template_edits
-- Edit only personal love-gesture fields; identity and recipient stay immutable.
create policy "Creator may edit their own gesture templates"
 on public.gesture_templates for update to authenticated
 using(creator_id=(select auth.uid()) and private.is_space_member(space_id))
 with check(creator_id=(select auth.uid()) and private.is_space_member(space_id));
grant update(title,message,kind,scheduled_moment)
 on public.gesture_templates to authenticated;
