-- R26: RLS policy evaluation requires EXECUTE privilege on private
-- helper. Function remains in non-exposed private schema and validates
-- membership and invitation status before granting page mutation.
grant execute on function private.may_edit_scrapbook(uuid,uuid) to authenticated;
