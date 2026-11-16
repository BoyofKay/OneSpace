-- 0132: Demo couple for real-app screenshots and tutorial videos (website, stores).
-- Omar & Lina are fictional. Their space is an ordinary, isolated space (same RLS
-- as everyone). private.demo_reset() wipes and re-creates its content with dates
-- relative to today, so countdowns always look fresh. The two demo logins are
-- created once by hand (password kept as a GitHub secret, never in the repo) and
-- registered in private.demo_accounts.

create table if not exists private.demo_accounts (
  role text primary key check (role in ('omar','lina')),
  user_id uuid not null unique references auth.users(id) on delete cascade
);
revoke all on private.demo_accounts from public, anon, authenticated;

create or replace function private.demo_as(uid uuid) returns void
language sql set search_path = '' as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', uid::text, true);
$$;

create or replace function private.demo_reset(p_mode text default 'apart_different_tz') returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  o uuid; l uuid; sp uuid; d date := (now() at time zone 'Asia/Riyadh')::date;
  a_weekend uuid; c_alula uuid; c_jeddah uuid; c_note uuid; a_sofa uuid; c_grey uuid; c_velvet uuid;
  t_trip uuid; t_pack uuid; t_groc uuid; t_err uuid; occ uuid; n_ideas uuid; cnt_met uuid; cnt_wed uuid; m1 uuid; ev_week uuid;
  i int; item uuid;
begin
  select user_id into o from private.demo_accounts where role = 'omar';
  select user_id into l from private.demo_accounts where role = 'lina';
  if o is null or l is null then raise exception 'Demo accounts are not registered'; end if;
  if p_mode not in ('living_together','apart_same_tz','apart_different_tz') then raise exception 'bad mode'; end if;

  -- Wipe the old demo space (cascades to its content) and notifications.
  delete from public.space_notifications where recipient_id in (o, l) or actor_id in (o, l);
  delete from public.spaces where id in (select space_id from public.space_members where user_id in (o, l));
  delete from public.reminder_recipients where recipient_id in (o, l);

  update public.profiles set display_name = 'Omar', locale = 'en', time_zone = 'Asia/Riyadh',
    city_weather_shared = true, city_name = 'Riyadh', temperature_c = 31, weather_code = 0, weather_high_c = 33, weather_low_c = 21,
    weather_rain_pct = 0, weather_updated_at = now(), work_start_local = '08:00', work_end_local = '17:00',
    sleep_start_local = '23:30', sleep_end_local = '06:45', partner_label = 'Lina', preferred_currency = 'SAR',
    terms_version = '2026-11-16', terms_accepted_at = coalesce(terms_accepted_at, now())
  where id = o;
  update public.profiles set display_name = 'Lina', locale = 'en',
    time_zone = case when p_mode = 'apart_different_tz' then 'Europe/London' else 'Asia/Riyadh' end,
    city_weather_shared = true, city_name = case when p_mode = 'apart_different_tz' then 'London' else 'Riyadh' end,
    temperature_c = case when p_mode = 'apart_different_tz' then 9 else 31 end, weather_code = case when p_mode = 'apart_different_tz' then 61 else 0 end,
    weather_high_c = 11, weather_low_c = 6, weather_rain_pct = 70, weather_updated_at = now(),
    work_start_local = '09:00', work_end_local = '17:30', sleep_start_local = '23:00', sleep_end_local = '07:15',
    partner_label = 'Omar', preferred_currency = 'SAR', terms_version = '2026-11-16', terms_accepted_at = coalesce(terms_accepted_at, now())
  where id = l;

  perform private.demo_as(o);
  insert into public.spaces (name, created_by, relationship_mode, last_met_on, next_meet_on)
    values ('Omar & Lina', o, p_mode, d - 38, case when p_mode like 'apart%' then d + 6 end) returning id into sp;
  insert into public.space_members (space_id, user_id, joined_at) values (sp, o, now() - interval '400 days'), (sp, l, now() - interval '399 days')
    on conflict do nothing;

  -- Special dates and counters
  insert into public.space_special_dates (space_id, kind, person_id, title, month, day, year, created_by) values
    (sp, 'anniversary', null, 'Wedding anniversary', extract(month from d + 164)::int2, extract(day from d + 164)::int2, (extract(year from d + 164) - 6)::int2, o),
    (sp, 'birthday', l, '', extract(month from d + 19)::int2, extract(day from d + 19)::int2, 1996, o),
    (sp, 'birthday', o, '', extract(month from d + 121)::int2, extract(day from d + 121)::int2, 1994, l);
  insert into public.space_counters (space_id, created_by, title, on_date, emoji, category, description, yearly, pinned, place_text, people)
    values (sp, o, 'The day we met', (d - interval '8 years 62 days')::date, '💞', 'love', 'A rainy book fair. You reached for the same book.', true, false, 'Riyadh Book Fair', array['Omar','Lina'])
    returning id into cnt_met;
  insert into public.space_counters (space_id, created_by, title, on_date, emoji, category, description, yearly, pinned, linked_counter_id, place_text)
    values (sp, l, 'Wedding day', ((d + 164) - interval '6 years')::date, '💍', 'love', 'The best day. Then the best years.', true, true, cnt_met, 'Jeddah')
    returning id into cnt_wed;
  insert into public.space_counters (space_id, created_by, title, on_date, emoji, category, yearly, place_text) values
    (sp, o, 'Our first date', (d - interval '7 years 300 days')::date, '☕', 'love', true, 'Nook Café'),
    (sp, l, 'Moved into our flat', (d - interval '2 years 40 days')::date, '🏡', 'home', true, ''),
    (sp, l, 'Lina''s graduation', d + 45, '🎓', 'study', false, 'London');

  -- Places
  insert into public.places (space_id, created_by, name, city, country, category, status, notes, favorite, rating, latitude, longitude) values
    (sp, o, 'Nook Café', 'Riyadh', 'Saudi Arabia', 'cafe', 'visited', 'Our corner table. Cardamom latte for Lina, flat white for Omar.', true, 5, 24.6995, 46.6852),
    (sp, l, 'Jeddah Corniche', 'Jeddah', 'Saudi Arabia', 'beach', 'visited', 'Sunset walk the night before the wedding.', true, 5, 21.5433, 39.1035),
    (sp, l, 'Hampstead Heath', 'London', 'United Kingdom', 'nature', 'visited', 'Picnic on Parliament Hill.', false, 4, 51.5608, -0.1636),
    (sp, o, 'Galata Tower', 'Istanbul', 'Türkiye', 'landmark', 'wishlist', 'First evening of the reunion trip.', false, null, 41.0256, 28.9741),
    (sp, l, 'AlUla — Elephant Rock', 'AlUla', 'Saudi Arabia', 'nature', 'wishlist', 'Stargazing weekend.', true, null, 26.6497, 37.9346),
    (sp, l, 'Santorini', 'Oia', 'Greece', 'city', 'wishlist', 'One day. Blue domes, white walls.', false, null, 36.4618, 25.3753),
    (sp, o, 'Kyoto — Arashiyama', 'Kyoto', 'Japan', 'nature', 'wishlist', 'Bamboo grove at sunrise.', false, null, 35.0170, 135.6713);
  insert into public.place_visits (place_id, space_id, created_by, visited_on, caption)
    select id, sp, o, d - 12, 'Saturday breakfast' from public.places where space_id = sp and name = 'Nook Café';

  -- Trip with flights, items and packing list
  insert into public.shared_trips (space_id, created_by, title, origin, destination, start_on, end_on, notes, status, travel_mode, trip_type, adults)
    values (sp, o, 'Istanbul reunion', 'Riyadh', 'Istanbul', d + 6, d + 11, 'Meet at the hotel — Lina lands 2 hours earlier.', 'booked', 'flight', 'round', 2)
    returning id into t_trip;
  insert into public.trip_flight_options (trip_id, created_by, title, airline, origin, destination, departure_on, return_on, stops, price, currency, status, preference_score, cabin_bags, checked_bags, seat_included, seat_number) values
    (t_trip, o, 'Direct morning flight', 'Saudia', 'RUH', 'IST', d + 6, d + 11, 0, 2180, 'SAR', 'booked', 5, 1, 1, true, '14A'),
    (t_trip, o, 'Cheaper, one stop', 'Flynas', 'RUH', 'IST', d + 6, d + 11, 1, 1640, 'SAR', 'rejected', 2, 1, 0, false, null);
  insert into public.trip_items (trip_id, created_by, kind, title, location, local_date, end_date, provider, details, estimated_cost, currency, done) values
    (t_trip, l, 'stay', 'Hotel in Karaköy', 'Karaköy, Istanbul', d + 6, d + 11, 'Booking', 'Room with a view of the Bosphorus', 3200, 'SAR', true),
    (t_trip, l, 'activity', 'Bosphorus sunset cruise', 'Eminönü pier', d + 7, null, '', 'Book the 6 PM boat', 220, 'SAR', false),
    (t_trip, o, 'activity', 'Breakfast in Cihangir', 'Cihangir', d + 8, null, '', 'Lina''s pick', 0, 'SAR', false);
  insert into public.tasks (space_id, created_by, title, visibility, trip_id, trip_template_key) values (sp, o, 'Packing — Istanbul', 'shared', t_trip, 'travel_basics') returning id into t_pack;
  i := 0;
  foreach item in array (select array_agg(gen_random_uuid()) from generate_series(1,8)) loop
    i := i + 1;
    insert into public.task_checklist_items (id, task_id, created_by, title, position) values (item, t_pack, case when i % 2 = 0 then l else o end,
      (array['Passports','Hotel booking printout','Travel adapter','Warm jacket for the evening','Phone chargers','Lina''s birthday card','Camera','Comfortable shoes'])[i], i);
    if i in (1, 2, 4, 5, 7) then
      insert into public.task_checklist_checks (item_id, task_id, cycle_date, user_id, completed) values (item, t_pack, '2000-01-01', case when i % 2 = 0 then l else o end, true);
    end if;
  end loop;

  -- Lists
  insert into public.tasks (space_id, created_by, title, visibility, recurrence_rule) values (sp, l, 'Groceries', 'shared', '{"mode":"weekly","weekdays":[5]}') returning id into t_groc;
  i := 0;
  foreach item in array (select array_agg(gen_random_uuid()) from generate_series(1,7)) loop
    i := i + 1;
    insert into public.task_checklist_items (id, task_id, created_by, title, position) values (item, t_groc, l,
      (array['Milk','Eggs','Fresh dates','Cardamom coffee','Tomatoes','Laban','Flowers for the table'])[i], i);
  end loop;
  insert into public.tasks (space_id, created_by, title, visibility, assigned_to, target_date, priority) values
    (sp, o, 'Renew the car registration', 'shared', o, d + 4, 'high'),
    (sp, l, 'Send the photos to Mum', 'shared', l, d + 1, 'normal'),
    (sp, o, 'Fix the balcony light', 'shared', o, d + 9, 'low');

  -- Calendar
  insert into public.space_events (space_id, created_by, title, details, event_date, starts_at, ends_at, zone_id, location, kind, visibility) values
    (sp, l, 'Movie night (video call)', 'Your pick this time!', d + 3, ((d + 3) + time '21:00') at time zone 'Asia/Riyadh', ((d + 3) + time '23:00') at time zone 'Asia/Riyadh', 'Asia/Riyadh', null, 'event', 'shared'),
    (sp, l, 'Lina''s final presentation', 'Good luck messages welcome', d + 2, ((d + 2) + time '10:00') at time zone 'Europe/London', ((d + 2) + time '11:00') at time zone 'Europe/London', 'Europe/London', 'University, London', 'event', 'shared'),
    (sp, o, 'Dentist', '', d + 9, ((d + 9) + time '16:30') at time zone 'Asia/Riyadh', ((d + 9) + time '17:00') at time zone 'Asia/Riyadh', 'Asia/Riyadh', 'Smile Clinic, Olaya', 'event', 'shared');
  insert into public.space_events (space_id, created_by, title, event_date, kind, visibility, location) values
    (sp, o, 'Weekend away — AlUla', d + 26, 'event', 'shared', 'AlUla') returning id into ev_week;

  -- Activity: weekend away (comparing) with options, reactions and a conversation
  insert into public.activities (space_id, created_by, title, body, stage, priority, due_on, visibility)
    values (sp, o, 'Weekend away', 'Somewhere quiet for two nights. Budget around SAR 3,000.', 'comparing', 'normal', d + 26, 'shared') returning id into a_weekend;
  insert into public.activity_components (activity_id, created_by, kind, label, payload) values
    (a_weekend, o, 'option', 'AlUla, 2 nights', '{"value":"AlUla, 2 nights","price":2800,"currency":"SAR","note":"Stargazing tour + desert camp","url":"https://www.experiencealula.com"}') returning id into c_alula;
  insert into public.activity_components (activity_id, created_by, kind, label, payload) values
    (a_weekend, l, 'option', 'Jeddah, 2 nights', '{"value":"Jeddah, 2 nights","price":2100,"currency":"SAR","note":"Sea view, seafood on the Corniche"}') returning id into c_jeddah;
  insert into public.activity_components (activity_id, created_by, kind, label, payload) values
    (a_weekend, o, 'date', 'Dates', jsonb_build_object('value', (d + 26)::text, 'note', 'Thursday to Saturday'));
  insert into public.activity_component_reactions (activity_id, component_id, user_id, opinion) values
    (a_weekend, c_alula, o, 1), (a_weekend, c_jeddah, o, 0);
  insert into public.activity_comments (activity_id, author_id, body, created_at) values
    (a_weekend, o, 'AlUla looks magical — @Lina what do you think?', now() - interval '3 hours');
  perform private.demo_as(l);
  insert into public.activity_comments (activity_id, author_id, body, created_at) values
    (a_weekend, l, 'Yes! Stars and the old town 😍 Can we do Jeddah for your birthday instead?', now() - interval '2 hours');
  insert into public.activity_component_reactions (activity_id, component_id, user_id, opinion) values (a_weekend, c_alula, l, 1);
  perform private.demo_as(o);
  insert into public.activity_comments (activity_id, author_id, body, created_at) values
    (a_weekend, o, 'Deal 🤝 AlUla now, Jeddah in March.', now() - interval '90 minutes');

  -- Activity: sofa (decided)
  insert into public.activities (space_id, created_by, title, body, stage, visibility)
    values (sp, l, 'A new sofa', 'Something comfy for movie nights. Fits the 2.4 m wall.', 'decided', 'shared') returning id into a_sofa;
  insert into public.activity_components (activity_id, created_by, kind, label, payload) values
    (a_sofa, o, 'option', 'Grey corner sofa', '{"value":"Grey corner sofa","price":3400,"currency":"SAR","specs":"2.6 m · washable covers"}') returning id into c_grey;
  insert into public.activity_components (activity_id, created_by, kind, label, payload) values
    (a_sofa, l, 'option', 'Velvet 3-seater', '{"value":"Velvet 3-seater","price":2900,"currency":"SAR","specs":"2.3 m · deep green"}') returning id into c_velvet;
  insert into public.activity_decisions (activity_id, component_id, action, reason, created_by) values
    (a_sofa, c_velvet, 'chosen', 'It fits the wall and the window light. Both of us loved it.', l);

  -- Notes
  insert into public.notes (space_id, created_by, title, body, visibility, pinned) values
    (sp, o, 'Weekend away ideas', E'Somewhere quiet, 2 nights\n• AlUla — stars and the old town\n• Jeddah — the sea, seafood on the Corniche\n• Budget around SAR 3,000', 'shared', true)
    returning id into n_ideas;
  insert into public.notes (space_id, created_by, title, body, visibility, pinned) values
    (sp, l, 'Home info', E'Wi-Fi: OmarLina_5G\nBuilding guard: ext. 214\nWater meter: under the kitchen sink', 'shared', false),
    (sp, o, 'Gift ideas for Lina', E'• The film camera from the market\n• Rose perfume she tried in Jeddah\n• Weekend in AlUla?', 'private', false);
  insert into public.item_links (space_id, from_kind, from_id, to_kind, to_id, created_by) values (sp, 'note', n_ideas, 'activity', a_weekend, o);

  -- Reminders
  insert into public.reminders (space_id, created_by, title, details, due_at, visibility, audience, source_kind, source_id) values
    (sp, o, 'Book the AlUla stargazing tour', 'Only 12 seats', ((d + 1) + time '09:00') at time zone 'Asia/Riyadh', 'shared', 'me', 'activity', a_weekend);
  insert into public.reminders (space_id, created_by, title, due_at, visibility, audience, repeat_rule) values
    (sp, l, 'Pay the internet bill', ((d + 2) + time '13:00') at time zone 'Asia/Riyadh', 'shared', 'both', '{"freq":"monthly","interval":1,"times":["13:00"],"tz":"Asia/Riyadh"}'),
    (sp, o, 'Call Lina''s mum', ((d + 5) + time '19:00') at time zone 'Asia/Riyadh', 'shared', 'me', null);

  -- Occasion: Lina's birthday (Omar's surprise, private)
  insert into public.occasion_plans (space_id, created_by, title, occasion_on, annual, kind, visibility, status, prep_lead_days, budget, currency, honoree_name, notes)
    values (sp, o, 'Lina''s birthday', d + 19, true, 'birthday', 'private', 'preparing', 21, 2000, 'SAR', 'Lina', 'Keep it a surprise!') returning id into occ;
  insert into public.occasion_budget_items (plan_id, created_by, title, quantity, unit_price, actual_unit_price, currency, status, merchant, product_rating, preference_score, order_status) values
    (occ, o, 'Flowers and dinner at the Corniche', 1, 520, 520, 'SAR', 'purchased', 'Corniche Grill', 4.8, 5, 'not_ordered'),
    (occ, o, 'Instant film camera', 1, 340, null, 'SAR', 'shortlisted', 'Camera shop', 4.6, 4, 'not_ordered'),
    (occ, o, 'Rose perfume', 1, 450, null, 'SAR', 'wish', 'Perfume house', 4.4, 3, 'not_ordered');

  -- Experiences
  insert into public.shared_experiences (space_id, created_by, category, title, description, platform, status, enjoyed_on, planned_on) values
    (sp, l, 'movie', 'Before Sunrise', 'Our annual rewatch', 'Prime Video', 'enjoyed', d - 9, null),
    (sp, o, 'show', 'The Great British Bake Off', 'One episode every Friday', 'Netflix', 'planned', null, d + 3),
    (sp, l, 'book', 'The Little Prince', 'Read a chapter each, then talk', '', 'suggested', null, null);
  insert into public.shared_experience_reviews (experience_id, user_id, rating, review)
    select id, o, 4, 'Still the best walking-and-talking film.' from public.shared_experiences where space_id = sp and title = 'Before Sunrise';
  insert into public.shared_experience_reviews (experience_id, user_id, rating, review)
    select id, l, 5, 'Every single year ❤️' from public.shared_experiences where space_id = sp and title = 'Before Sunrise';

  -- Memories (photos are uploaded by the screenshot robot)
  insert into public.memories (space_id, created_by, title, body, memory_date, memory_type, photo_layout, place, pinned) values
    (sp, l, 'Sunset on the Corniche', 'The sky went pink and orange and we forgot to take more than three photos.', d - 160, 'story', 'feature', 'Jeddah Corniche', true)
    returning id into m1;
  insert into public.memories (space_id, created_by, title, body, memory_date, memory_type, photo_layout, place) values
    (sp, o, 'Picnic on Parliament Hill', 'Cold tea, warm scarves, London below us.', d - 38, 'story', 'polaroid', 'Hampstead Heath'),
    (sp, l, 'Our year in pages', 'Twelve months, one page each.', d - 20, 'scrapbook', 'grid', null);

  -- Contacts
  insert into public.saved_contacts (space_id, created_by, visibility, label, payload) values
    (sp, o, 'shared', 'Dr. Sara — dentist', '{"contact_name":"Smile Clinic","phone":"+966 11 000 0000","address":"Olaya, Riyadh","working_hours":"Sun–Thu 9–21"}'),
    (sp, l, 'shared', 'Building maintenance', '{"contact_name":"Faisal","phone":"+966 50 000 0000","note":"WhatsApp is fastest"}');

  -- Check-ins
  insert into public.daily_checkins (space_id, created_by, checkin_date, mood, message, gratitude, visibility) values
    (sp, o, d, 4, 'Long day, but the Istanbul tickets are booked!', 'Your voice note this morning', 'shared'),
    (sp, l, d, 5, 'Finished the big project!', 'Omar cheering me on', 'shared'),
    (sp, l, d - 1, 3, 'Rainy and tired.', 'Hot soup', 'shared'),
    (sp, o, d - 1, 4, 'Good run before work.', '', 'shared');

  -- Letters (Lina → Omar sealed until the trip; Omar → Lina read)
  perform private.demo_as(l);
  insert into public.couple_letters (space_id, author_id, title, body, status, sent_at, open_on) values
    (sp, l, 'For the day you land', 'Open this at the airport. I''ll be the one waving too much.', 'sent', now() - interval '2 days', d + 6),
    (sp, l, 'For our anniversary', 'Six years. Open it with coffee.', 'sent', now() - interval '1 day', d + 164);
  perform private.demo_as(o);
  insert into public.couple_letters (space_id, author_id, title, body, status, sent_at) values
    (sp, o, 'Just because', 'I was thinking about the book fair today. Thank you for reaching for the same book.', 'sent', now() - interval '13 days');

  -- Gestures (the most recent first in Today)
  insert into public.partner_gestures (space_id, sender_id, recipient_id, kind, message, created_at) values
    (sp, o, l, 'morning', 'Good morning, sunshine ☀️ Good luck today!', now() - interval '9 hours');
  perform private.demo_as(l);
  insert into public.partner_gestures (space_id, sender_id, recipient_id, kind, message, created_at) values
    (sp, l, o, 'proud', 'So proud of you for booking everything!', now() - interval '1 hour'),
    (sp, l, o, 'hug', 'Sending you a big, warm hug.', now() - interval '2 minutes');
  perform private.demo_as(o);

  -- Keep the bell readable: mark older notices read, keep the last few unread.
  update public.space_notifications set read_at = now(), push_due_at = null where space_id = sp and (kind in ('created','change') or created_at < now() - interval '30 minutes');
  return sp;
end $$;
revoke all on function private.demo_reset(text) from public, anon, authenticated;
revoke all on function private.demo_as(uuid) from public, anon, authenticated;

-- Arabic content for Arabic screenshots, and the robot's entry point.
create or replace function private.demo_arabic(sp uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare o uuid; l uuid;
begin
  select user_id into o from private.demo_accounts where role = 'omar';
  select user_id into l from private.demo_accounts where role = 'lina';
  update public.profiles set display_name = 'عمر', partner_label = 'لينا', locale = 'ar', city_name = 'الرياض' where id = o;
  update public.profiles set display_name = 'لينا', partner_label = 'عمر', locale = 'ar',
    city_name = case when city_name = 'London' then 'لندن' else 'الرياض' end where id = l;
  update public.spaces set name = 'عمر ولينا' where id = sp;
  create temporary table if not exists demo_tr (en text primary key, ar text) on commit drop;
  delete from demo_tr;
  insert into demo_tr values
   ('The day we met','يوم التقينا'),('A rainy book fair. You reached for the same book.','معرض كتاب ممطر. مددتِ يدكِ إلى الكتاب نفسه.'),('Riyadh Book Fair','معرض الرياض للكتاب'),
   ('Wedding day','يوم الزفاف'),('The best day. Then the best years.','أجمل يوم. ثم أجمل السنوات.'),('Jeddah','جدة'),('Our first date','موعدنا الأول'),('Nook Café','مقهى الزاوية'),
   ('Moved into our flat','انتقلنا إلى شقتنا'),('Lina''s graduation','تخرّج لينا'),('London','لندن'),('Together again in Istanbul','معًا من جديد في إسطنبول'),('Istanbul','إسطنبول'),
   ('Our corner table. Cardamom latte for Lina, flat white for Omar.','طاولتنا في الزاوية. لاتيه بالهيل للينا وفلات وايت لعمر.'),('Riyadh','الرياض'),('Saudi Arabia','السعودية'),
   ('Jeddah Corniche','كورنيش جدة'),('Sunset walk the night before the wedding.','نزهة الغروب ليلة الزفاف.'),('Hampstead Heath','هامبستيد هيث'),('United Kingdom','المملكة المتحدة'),
   ('Picnic on Parliament Hill.','نزهة على تل البرلمان.'),('Galata Tower','برج غلطة'),('Türkiye','تركيا'),('First evening of the reunion trip.','أول أمسية في رحلة اللقاء.'),
   ('AlUla — Elephant Rock','العُلا — جبل الفيل'),('AlUla','العُلا'),('Stargazing weekend.','عطلة لمراقبة النجوم.'),('Santorini','سانتوريني'),('Oia','أويا'),('Greece','اليونان'),
   ('One day. Blue domes, white walls.','يومًا ما. قباب زرقاء وجدران بيضاء.'),('Kyoto — Arashiyama','كيوتو — أراشيياما'),('Kyoto','كيوتو'),('Japan','اليابان'),('Bamboo grove at sunrise.','غابة الخيزران عند الشروق.'),
   ('Saturday breakfast','فطور السبت'),('Istanbul reunion','لقاء إسطنبول'),('Meet at the hotel — Lina lands 2 hours earlier.','نلتقي في الفندق — تصل لينا قبل ساعتين.'),
   ('Direct morning flight','رحلة صباحية مباشرة'),('Cheaper, one stop','أرخص، بتوقف واحد'),('Hotel in Karaköy','فندق في كاراكوي'),('Karaköy, Istanbul','كاراكوي، إسطنبول'),
   ('Room with a view of the Bosphorus','غرفة تطل على البوسفور'),('Bosphorus sunset cruise','رحلة الغروب في البوسفور'),('Eminönü pier','رصيف إمينونو'),('Book the 6 PM boat','احجز قارب السادسة مساءً'),
   ('Breakfast in Cihangir','فطور في جيهانغير'),('Cihangir','جيهانغير'),('Lina''s pick','اختيار لينا'),('Packing — Istanbul','تجهيز الحقيبة — إسطنبول'),
   ('Passports','جوازات السفر'),('Hotel booking printout','نسخة حجز الفندق'),('Travel adapter','محوّل الكهرباء'),('Warm jacket for the evening','سترة دافئة للمساء'),('Phone chargers','شواحن الهاتف'),
   ('Lina''s birthday card','بطاقة عيد ميلاد لينا'),('Camera','الكاميرا'),('Comfortable shoes','حذاء مريح'),('Groceries','المشتريات'),('Milk','حليب'),('Eggs','بيض'),('Fresh dates','تمر طازج'),
   ('Cardamom coffee','قهوة بالهيل'),('Tomatoes','طماطم'),('Laban','لبن'),('Flowers for the table','ورد للطاولة'),('Renew the car registration','تجديد استمارة السيارة'),
   ('Send the photos to Mum','إرسال الصور لماما'),('Fix the balcony light','إصلاح إضاءة الشرفة'),('Movie night (video call)','سهرة فيلم (مكالمة فيديو)'),('Your pick this time!','الاختيار لك هذه المرة!'),
   ('Lina''s final presentation','العرض النهائي للينا'),('Good luck messages welcome','رسائل التشجيع مرحّب بها'),('University, London','الجامعة، لندن'),('Dentist','طبيب الأسنان'),('Smile Clinic, Olaya','عيادة الابتسامة، العليا'),
   ('Weekend away — AlUla','عطلة نهاية الأسبوع — العُلا'),('Weekend away','عطلة نهاية الأسبوع'),('Somewhere quiet for two nights. Budget around SAR 3,000.','مكان هادئ لليلتين. الميزانية نحو 3,000 ريال.'),
   ('AlUla, 2 nights','العُلا، ليلتان'),('Jeddah, 2 nights','جدة، ليلتان'),('Dates','التواريخ'),
   ('AlUla looks magical — @Lina what do you think?','العُلا تبدو ساحرة — @لينا ما رأيك؟'),('Yes! Stars and the old town 😍 Can we do Jeddah for your birthday instead?','نعم! النجوم والبلدة القديمة 😍 هل نجعل جدة لعيد ميلادك؟'),
   ('Deal 🤝 AlUla now, Jeddah in March.','اتفقنا 🤝 العُلا الآن وجدة في مارس.'),('A new sofa','أريكة جديدة'),('Something comfy for movie nights. Fits the 2.4 m wall.','شيء مريح لسهرات الأفلام. يناسب جدار 2.4 م.'),
   ('Grey corner sofa','أريكة زاوية رمادية'),('Velvet 3-seater','أريكة مخمل لثلاثة'),('It fits the wall and the window light. Both of us loved it.','تناسب الجدار وضوء النافذة. أعجبتنا كلينا.'),
   ('Weekend away ideas','أفكار لعطلة نهاية الأسبوع'),('Home info','معلومات البيت'),('Gift ideas for Lina','أفكار هدايا للينا'),
   ('Book the AlUla stargazing tour','احجز جولة النجوم في العُلا'),('Only 12 seats','12 مقعدًا فقط'),('Pay the internet bill','ادفع فاتورة الإنترنت'),('Call Lina''s mum','اتصل بأم لينا'),
   ('Lina''s birthday','عيد ميلاد لينا'),('Lina','لينا'),('Keep it a surprise!','لتبقَ مفاجأة!'),('Flowers and dinner at the Corniche','ورد وعشاء على الكورنيش'),('Corniche Grill','مشويات الكورنيش'),
   ('Instant film camera','كاميرا فورية'),('Camera shop','متجر الكاميرات'),('Rose perfume','عطر الورد'),('Perfume house','دار العطور'),
   ('Our annual rewatch','نعيد مشاهدته كل عام'),('One episode every Friday','حلقة كل جمعة'),('The Little Prince','الأمير الصغير'),('Read a chapter each, then talk','نقرأ فصلًا ثم نتحدث'),
   ('Still the best walking-and-talking film.','ما زال أجمل فيلم عن المشي والحديث.'),('Every single year ❤️','كل عام بلا استثناء ❤️'),
   ('Sunset on the Corniche','غروب على الكورنيش'),('The sky went pink and orange and we forgot to take more than three photos.','صارت السماء وردية وبرتقالية ونسينا أن نلتقط أكثر من ثلاث صور.'),
   ('Picnic on Parliament Hill','نزهة على تل البرلمان'),('Cold tea, warm scarves, London below us.','شاي بارد ووشاحات دافئة ولندن تحتنا.'),('Our year in pages','سنتنا في صفحات'),('Twelve months, one page each.','اثنا عشر شهرًا، لكل شهر صفحة.'),
   ('Dr. Sara — dentist','د. سارة — طبيبة الأسنان'),('Building maintenance','صيانة المبنى'),
   ('Long day, but the Istanbul tickets are booked!','يوم طويل، لكن تذاكر إسطنبول محجوزة!'),('Your voice note this morning','رسالتك الصوتية هذا الصباح'),('Finished the big project!','أنهيت المشروع الكبير!'),
   ('Omar cheering me on','تشجيع عمر لي'),('Rainy and tired.','ممطر ومتعبة.'),('Hot soup','حساء ساخن'),('Good run before work.','جري جميل قبل العمل.'),
   ('For the day you land','ليوم وصولك'),('Open this at the airport. I''ll be the one waving too much.','افتحها في المطار. سأكون التي تلوّح كثيرًا.'),('For our anniversary','لذكرانا'),('Six years. Open it with coffee.','ست سنوات. افتحها مع القهوة.'),
   ('Just because','بلا مناسبة'),('I was thinking about the book fair today. Thank you for reaching for the same book.','كنت أفكر اليوم في معرض الكتاب. شكرًا لأنكِ مددتِ يدكِ إلى الكتاب نفسه.'),
   ('Good morning, sunshine ☀️ Good luck today!','صباح الخير يا شمسي ☀️ بالتوفيق اليوم!'),('So proud of you for booking everything!','فخورة بك لأنك حجزت كل شيء!'),('Sending you a big, warm hug.','أرسل لك حضنًا كبيرًا ودافئًا.'),
   ('Wedding anniversary','ذكرى الزواج');
  update public.space_counters c set title = coalesce((select ar from demo_tr where en = c.title), title), description = coalesce((select ar from demo_tr where en = c.description), description), place_text = coalesce((select ar from demo_tr where en = c.place_text), place_text), people = array['عمر','لينا'] where space_id = sp;
  update public.space_special_dates c set title = coalesce((select ar from demo_tr where en = c.title), title) where space_id = sp;
  update public.places c set name = coalesce((select ar from demo_tr where en = c.name), name), city = coalesce((select ar from demo_tr where en = c.city), city), country = coalesce((select ar from demo_tr where en = c.country), country), notes = coalesce((select ar from demo_tr where en = c.notes), notes) where space_id = sp;
  update public.place_visits c set caption = coalesce((select ar from demo_tr where en = c.caption), caption) where space_id = sp;
  update public.shared_trips c set title = coalesce((select ar from demo_tr where en = c.title), title), origin = coalesce((select ar from demo_tr where en = c.origin), origin), destination = coalesce((select ar from demo_tr where en = c.destination), destination), notes = coalesce((select ar from demo_tr where en = c.notes), notes) where space_id = sp;
  update public.trip_flight_options c set title = coalesce((select ar from demo_tr where en = c.title), title) where trip_id in (select id from public.shared_trips where space_id = sp);
  update public.trip_items c set title = coalesce((select ar from demo_tr where en = c.title), title), location = coalesce((select ar from demo_tr where en = c.location), location), details = coalesce((select ar from demo_tr where en = c.details), details) where trip_id in (select id from public.shared_trips where space_id = sp);
  update public.tasks c set title = coalesce((select ar from demo_tr where en = c.title), title) where space_id = sp;
  update public.task_checklist_items c set title = coalesce((select ar from demo_tr where en = c.title), title) where task_id in (select id from public.tasks where space_id = sp);
  update public.space_events c set title = coalesce((select ar from demo_tr where en = c.title), title), details = coalesce((select ar from demo_tr where en = c.details), details), location = coalesce((select ar from demo_tr where en = c.location), location) where space_id = sp;
  update public.activities c set title = coalesce((select ar from demo_tr where en = c.title), title), body = coalesce((select ar from demo_tr where en = c.body), body) where space_id = sp;
  update public.activity_components c set label = coalesce((select ar from demo_tr where en = c.label), label),
    payload = case when payload ? 'value' and exists (select 1 from demo_tr where en = c.payload->>'value') then jsonb_set(payload, '{value}', to_jsonb((select ar from demo_tr where en = c.payload->>'value'))) else payload end
    where activity_id in (select id from public.activities where space_id = sp);
  update public.activity_comments c set body = coalesce((select ar from demo_tr where en = c.body), body) where activity_id in (select id from public.activities where space_id = sp);
  update public.activity_decisions c set reason = coalesce((select ar from demo_tr where en = c.reason), reason) where activity_id in (select id from public.activities where space_id = sp);
  update public.notes c set title = coalesce((select ar from demo_tr where en = c.title), title) where space_id = sp;
  update public.notes set body = E'مكان هادئ، ليلتان\n• العُلا — النجوم والبلدة القديمة\n• جدة — البحر والمأكولات البحرية على الكورنيش\n• الميزانية نحو 3,000 ريال' where space_id = sp and title = 'أفكار لعطلة نهاية الأسبوع';
  update public.notes set body = E'الواي فاي: OmarLina_5G\nحارس المبنى: تحويلة 214\nعداد المياه: تحت مغسلة المطبخ' where space_id = sp and title = 'معلومات البيت';
  update public.notes set body = E'• الكاميرا من السوق\n• عطر الورد الذي جرّبته في جدة\n• عطلة في العُلا؟' where space_id = sp and title = 'أفكار هدايا للينا';
  update public.reminders c set title = coalesce((select ar from demo_tr where en = c.title), title), details = coalesce((select ar from demo_tr where en = c.details), details) where space_id = sp;
  update public.occasion_plans c set title = coalesce((select ar from demo_tr where en = c.title), title), honoree_name = coalesce((select ar from demo_tr where en = c.honoree_name), honoree_name), notes = coalesce((select ar from demo_tr where en = c.notes), notes) where space_id = sp;
  update public.occasion_budget_items c set title = coalesce((select ar from demo_tr where en = c.title), title), merchant = coalesce((select ar from demo_tr where en = c.merchant), merchant) where plan_id in (select id from public.occasion_plans where space_id = sp);
  update public.shared_experiences c set title = coalesce((select ar from demo_tr where en = c.title), title), description = coalesce((select ar from demo_tr where en = c.description), description) where space_id = sp;
  update public.shared_experience_reviews c set review = coalesce((select ar from demo_tr where en = c.review), review) where experience_id in (select id from public.shared_experiences where space_id = sp);
  update public.memories c set title = coalesce((select ar from demo_tr where en = c.title), title), body = coalesce((select ar from demo_tr where en = c.body), body), place = coalesce((select ar from demo_tr where en = c.place), place) where space_id = sp;
  update public.saved_contacts c set label = coalesce((select ar from demo_tr where en = c.label), label) where space_id = sp;
  update public.daily_checkins c set message = coalesce((select ar from demo_tr where en = c.message), message), gratitude = coalesce((select ar from demo_tr where en = c.gratitude), gratitude) where space_id = sp;
  alter table public.couple_letters disable trigger enforce_couple_letter_state;
  update public.couple_letters c set title = coalesce((select ar from demo_tr where en = c.title), title), body = coalesce((select ar from demo_tr where en = c.body), body) where space_id = sp;
  alter table public.couple_letters enable trigger enforce_couple_letter_state;
  update public.partner_gestures c set message = coalesce((select ar from demo_tr where en = c.message), message) where space_id = sp;
  update public.space_notifications c set headline = coalesce((select ar from demo_tr where en = c.headline), headline) where space_id = sp;
end $$;
revoke all on function private.demo_arabic(uuid) from public, anon, authenticated;

drop function if exists public.demo_reset_space(text);
create or replace function public.demo_reset_space(p_mode text default 'apart_different_tz', p_lang text default 'en') returns uuid
language plpgsql security definer set search_path = '' as $$
declare sp uuid;
begin
  if not exists (select 1 from private.demo_accounts where user_id = auth.uid()) then
    raise exception 'Only the demo account can reset the demo space';
  end if;
  sp := private.demo_reset(p_mode);
  if p_lang = 'ar' then perform private.demo_arabic(sp); end if;
  return sp;
end $$;
revoke all on function public.demo_reset_space(text, text) from public, anon;
grant execute on function public.demo_reset_space(text, text) to authenticated;
