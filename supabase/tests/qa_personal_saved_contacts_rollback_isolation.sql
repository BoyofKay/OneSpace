-- QA-only, rollback-only standalone account-private saved-contact regression.
BEGIN;
SELECT set_config('request.jwt.claim.sub',
  (SELECT owner_id::text FROM public.user_private_spaces ORDER BY owner_id LIMIT 1), true);
SELECT set_config('qa.outsider',
  (SELECT owner_id::text FROM public.user_private_spaces ORDER BY owner_id OFFSET 1 LIMIT 1), true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE owner_id uuid := auth.uid();
  outsider_id uuid := current_setting('qa.outsider')::uuid;
  record_id uuid;
BEGIN
  IF owner_id IS NULL OR outsider_id IS NULL OR owner_id=outsider_id THEN
    RAISE EXCEPTION 'Two existing distinct QA accounts required';
  END IF;
  INSERT INTO public.saved_contacts
    (private_space_id, created_by, visibility, label, payload)
  VALUES (owner_id, owner_id, 'private',
    'QA rollback personal contact', '{"contact_name":"QA"}'::jsonb)
  RETURNING id INTO record_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.saved_contacts c WHERE c.id=record_id
    AND c.private_space_id=owner_id AND c.space_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Owner cannot see personal contact';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', outsider_id::text,true);
  IF EXISTS (SELECT 1 FROM public.saved_contacts WHERE id=record_id) THEN
    RAISE EXCEPTION 'Another user can see a personal contact';
  END IF;
END $qa$;
ROLLBACK;
