CREATE OR REPLACE FUNCTION public.record_activity_decision(p_activity_id uuid, p_action text, p_component_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT ''::text)
 RETURNS activity_decisions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_activity public.activities%ROWTYPE;
  v_record public.activity_decisions%ROWTYPE;
  v_option uuid;
  v_stage text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required'
      USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN (
    'chosen','purchased','delivered','registered','postponed',
    'reopened','cancelled'
  ) OR p_action IS NULL THEN
    RAISE EXCEPTION 'Invalid Activity action'
      USING ERRCODE = '22023';
  END IF;
  IF char_length(coalesce(p_reason, '')) > 2000 THEN
    RAISE EXCEPTION 'Decision note is too long'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_activity
    FROM public.activities
    WHERE id = p_activity_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Activity not available'
      USING ERRCODE = '42501';
  END IF;
  IF NOT private.is_space_member(v_activity.space_id)
      OR (v_activity.visibility = 'private' AND
          v_activity.created_by IS DISTINCT FROM auth.uid())
      OR v_activity.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Activity not available'
      USING ERRCODE = '42501';
  END IF;

  IF p_component_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.activity_components c
       WHERE c.id = p_component_id
         AND c.activity_id = p_activity_id
         AND c.kind = 'option'
         AND c.archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'The selected option does not belong to this Activity'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_action = 'chosen' AND p_component_id IS NULL THEN
    RAISE EXCEPTION 'Choose an option first'
      USING ERRCODE = '22023';
  END IF;

  -- Preserve the latest candidate in subsequent purchase/delivery decisions,
  -- while leaving postponements or reopenings unbound.
  v_option := p_component_id;
  IF v_option IS NULL AND p_action IN ('purchased','delivered','registered') THEN
    SELECT d.component_id INTO v_option
      FROM public.activity_decisions d
     WHERE d.activity_id = p_activity_id AND d.component_id IS NOT NULL
     ORDER BY d.created_at DESC, d.id DESC LIMIT 1;
  END IF;

  v_stage := CASE p_action
    WHEN 'chosen' THEN 'decided'
    WHEN 'purchased' THEN 'purchased'
    WHEN 'delivered' THEN 'completed'
    WHEN 'registered' THEN 'completed'
    WHEN 'postponed' THEN 'on_hold'
    WHEN 'reopened' THEN 'exploring'
    WHEN 'cancelled' THEN 'cancelled'
  END;

  INSERT INTO public.activity_decisions(
    activity_id, component_id, action, reason, created_by
  )
  VALUES (p_activity_id, v_option, p_action, coalesce(p_reason,''), auth.uid())
  RETURNING * INTO v_record;
  UPDATE public.activities SET stage = v_stage WHERE id = p_activity_id;
  RETURN v_record;
END;
$function$
