-- QA lifecycle prerequisite: retired archive progress may not prevent the
-- explicit irreversible deletion of the relationship it formerly referred to.
-- Replaces the old RESTRICT / NO ACTION FK; no rows are deleted by migration.
-- Old archival/restore workflows remain disabled and are not lifecycle options.
ALTER TABLE public.qa_archive_job_progress
 DROP CONSTRAINT IF EXISTS qa_archive_job_progress_original_space_id_fkey;
ALTER TABLE public.qa_archive_job_progress
 ADD CONSTRAINT qa_archive_job_progress_original_space_id_fkey
 FOREIGN KEY (original_space_id) REFERENCES public.spaces(id)
 ON DELETE CASCADE NOT VALID;
