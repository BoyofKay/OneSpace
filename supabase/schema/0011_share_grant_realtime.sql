-- Publish changes to grant metadata so clients refresh RLS-filtered
-- content when the owner grants or revokes view-only access.
alter publication supabase_realtime add table public.object_shares;
