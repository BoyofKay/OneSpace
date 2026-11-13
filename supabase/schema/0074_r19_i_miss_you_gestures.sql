-- R19 add one new consensual affectionate gesture category. Preserve history.
alter table public.partner_gestures drop constraint if exists partner_gestures_kind_check;
alter table public.partner_gestures add constraint partner_gestures_kind_check
 check(kind in ('hug','thinking','smile','morning','goodnight','proud','support','thanks',
 'lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets'));
alter table public.gesture_templates drop constraint if exists gesture_templates_kind_check;
alter table public.gesture_templates add constraint gesture_templates_kind_check
 check(kind in ('hug','thinking','smile','morning','goodnight','proud','support','thanks',
 'lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets'));
alter table public.gesture_message_overrides drop constraint if exists gesture_message_overrides_kind_check;
alter table public.gesture_message_overrides add constraint gesture_message_overrides_kind_check
 check(kind in ('hug','thinking','smile','morning','goodnight','proud','support','thanks',
 'lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets'));
