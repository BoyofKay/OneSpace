-- QA 0213: explicit deny-all policies for clients on the PRIVATE
-- encrypted subset staging registry. Service-only SECURITY DEFINER RPCs
-- remain the only path; no Data API table grants are introduced.
create policy qa_subset_staging_deny_all_clients
 on private.qa_vault_subset_staging
 for all to anon,authenticated
 using (false) with check (false);
