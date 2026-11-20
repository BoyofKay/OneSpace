-- QA 0231: grant only the DML required by Notes UI and owner-scoped RLS.
-- Existing QA has READ grants on all content tables but no INSERT/UPDATE
-- grants for authenticated; RLS policies cannot grant SQL privileges alone.
-- This deliberately does not grant DELETE, TRUNCATE or grant to anon.
grant insert,update on public.notes to authenticated;
-- Audit history remains internal trigger-owned: clients cannot forge audit rows.
revoke insert,update,delete on public.record_action_history from authenticated;
