-- Permit reusable research blocks to sit under a particular option/step.
-- Every parent belongs to the same activity; existing records remain unchanged.
alter table public.activity_components
  add column parent_component_id uuid,
  add constraint component_not_own_parent check (
    parent_component_id is null or parent_component_id <> id
  ),
  add constraint component_parent_same_activity
    foreign key(activity_id,parent_component_id)
    references public.activity_components(activity_id,id);
create index activity_components_nested
  on public.activity_components(activity_id,parent_component_id,created_at);
grant insert(parent_component_id) on public.activity_components to authenticated;