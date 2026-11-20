-- QA emergency safety gate: old app buttons being disabled does not
-- protect callable SECURITY DEFINER endpoints from direct REST invocations.
-- Do not re-grant until 69-family private-preservation/media-erase tests,
-- legacy private migration and the 7-day account finalizer all pass.
revoke all on function public.end_shared_space(text,text)
 from public,anon,authenticated;
revoke all on function public.request_account_deletion()
 from public,anon,authenticated;
-- public.cancel_account_deletion() remains callable to let any pre-existing
-- pending request be cancelled safely. Service/admin use is unaffected.
