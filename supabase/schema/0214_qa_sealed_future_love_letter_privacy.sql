-- QA 0214: un-opened / future scheduled Love Letters are author-private.
-- The legacy sealed_letters() function used SECURITY DEFINER and disclosed
-- the existence, original author and scheduled open date of partner letters.
-- Never restore pre-open shared placeholders across a new relationship.
-- Preserve RPC ABI for older Android builds, but return no recipient data.
create or replace function public.sealed_letters()
returns table(id uuid,author_id uuid,open_on date,sent_at timestamptz)
language sql stable security invoker set search_path='' as $fn$
  select l.id,l.author_id,l.open_on,l.sent_at
  from public.couple_letters l
  where false
$fn$;
revoke all on function public.sealed_letters() from public,anon;
grant execute on function public.sealed_letters() to authenticated;
