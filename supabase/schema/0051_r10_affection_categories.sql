-- Deployed 20261113120153 onespace_r10_more_affection_categories
-- R10 six non-explicit affectionate gestures, available as personal templates.
alter table public.partner_gestures drop constraint partner_gestures_kind_check;
alter table public.partner_gestures add constraint partner_gestures_kind_check check(
 kind in ('hug','thinking','smile','morning','goodnight','proud','support',
   'thanks','lucky','miss_together','miss_home','miss_kids','miss_pets'));
alter table public.gesture_templates drop constraint gesture_templates_kind_check;
alter table public.gesture_templates add constraint gesture_templates_kind_check check(
 kind in ('hug','thinking','smile','morning','goodnight','proud','support',
   'thanks','lucky','miss_together','miss_home','miss_kids','miss_pets'));
