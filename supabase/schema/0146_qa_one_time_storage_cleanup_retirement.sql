-- One-time QA Storage API cleanup completed and independently verified: 59 deleted, 0 remain.
-- Close access to the privileged file manifest; no runnable cleanup endpoint remains.
drop function if exists public.qa_storage_cleanup_manifest_service();
