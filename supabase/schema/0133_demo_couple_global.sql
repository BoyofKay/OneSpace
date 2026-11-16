-- 0133: the fictional demo couple (Omar & Lina) moves to a global setting for the
-- public website: Omar lives in Toronto (America/Toronto), Lina in London; prices
-- in USD; Saudi/Egyptian places, carriers and phone numbers replaced.
-- Applied 2026-11-16 by rewriting private.demo_reset and private.demo_arabic in place.
do $do$
declare f text; def text; i int;
  r text[] := array[
  'Asia/Riyadh','America/Toronto',
  'city_name = ''Riyadh'', temperature_c = 31, weather_code = 0, weather_high_c = 33, weather_low_c = 21',
  'city_name = ''Toronto'', temperature_c = 18, weather_code = 0, weather_high_c = 20, weather_low_c = 11',
  'else ''Riyadh'' end','else ''Toronto'' end', 'else 31 end','else 18 end',
  'preferred_currency = ''SAR''','preferred_currency = ''USD''',
  'Riyadh Book Fair','Toronto Book Fair', 'معرض الرياض للكتاب','معرض تورونتو للكتاب',
  'cnt_met, ''Jeddah'')','cnt_met, ''Lisbon'')', '(''Jeddah'',''جدة'')','(''Lisbon'',''لشبونة'')',
  '''Nook Café'', ''Riyadh'', ''Saudi Arabia''','''Nook Café'', ''Toronto'', ''Canada''', '24.6995, 46.6852','43.6547, -79.4005',
  '''Jeddah Corniche'', ''Jeddah'', ''Saudi Arabia''','''Cascais beach'', ''Cascais'', ''Portugal''', '21.5433, 39.1035','38.6979, -9.4215',
  '(''Jeddah Corniche'',''كورنيش جدة'')','(''Cascais beach'',''شاطئ كاشكايش''),(''Cascais'',''كاشكايش''),(''Portugal'',''البرتغال'')',
  '''feature'', ''Jeddah Corniche''','''feature'', ''Cascais beach''',
  '''AlUla — Elephant Rock'', ''AlUla'', ''Saudi Arabia''','''Lake Louise'', ''Banff'', ''Canada''', '26.6497, 37.9346','51.4254, -116.1773',
  '(''AlUla — Elephant Rock'',''العُلا — جبل الفيل''),(''AlUla'',''العُلا'')','(''Lake Louise'',''بحيرة لويز''),(''Banff'',''بانف'')',
  '(''Riyadh'',''الرياض''),(''Saudi Arabia'',''السعودية'')','(''Toronto'',''تورونتو''),(''Canada'',''كندا'')',
  '''Istanbul reunion'', ''Riyadh''','''Istanbul reunion'', ''Toronto''',
  '''Saudia'', ''RUH'', ''IST'', d + 6, d + 11, 0, 2180, ''SAR''','''Turkish Airlines'', ''YYZ'', ''IST'', d + 6, d + 11, 0, 1180, ''USD''',
  '''Flynas'', ''RUH'', ''IST'', d + 6, d + 11, 1, 1640, ''SAR''','''Air Canada'', ''YYZ'', ''IST'', d + 6, d + 11, 1, 940, ''USD''',
  '3200, ''SAR''','860, ''USD''', '220, ''SAR''','60, ''USD''', '0, ''SAR'', false','0, ''USD'', false',
  'Smile Clinic, Olaya','Smile Clinic, Queen St W', 'عيادة الابتسامة، العليا','عيادة الابتسامة، كوين ستريت',
  'Budget around SAR 3,000','Budget around $800', 'الميزانية نحو 3,000 ريال','الميزانية نحو 800 دولار',
  '"AlUla, 2 nights","price":2800,"currency":"SAR","note":"Stargazing tour + desert camp","url":"https://www.experiencealula.com"',
  '"Banff, 2 nights","price":760,"currency":"USD","note":"Stargazing tour + mountain lodge","url":"https://www.banfflakelouise.com"',
  '"Jeddah, 2 nights","price":2100,"currency":"SAR","note":"Sea view, seafood on the Corniche"','"Muskoka, 2 nights","price":540,"currency":"USD","note":"Lake cabin, canoe at sunrise"',
  'AlUla — stars and the old town','Banff — stars and the mountains', 'Jeddah — the sea, seafood on the Corniche','Muskoka — a lake cabin, canoe at sunrise',
  'العُلا — النجوم والبلدة القديمة','بانف — النجوم والجبال', 'جدة — البحر والمأكولات البحرية على الكورنيش','موسكوكا — كوخ على البحيرة وتجديف عند الشروق',
  'Rose perfume she tried in Jeddah','Rose perfume she tried in Lisbon', 'عطر الورد الذي جرّبته في جدة','عطر الورد الذي جرّبته في لشبونة',
  'Stars and the old town','Stars and the mountains', 'النجوم والبلدة القديمة','النجوم والجبال',
  '3400,"currency":"SAR"','1400,"currency":"USD"', '2900,"currency":"SAR"','1150,"currency":"USD"', '21, 2000, ''SAR''','21, 600, ''USD''',
  '''Flowers and dinner at the Corniche'', 1, 520, 520, ''SAR'', ''purchased'', ''Corniche Grill''','''Flowers and dinner by the lake'', 1, 160, 160, ''USD'', ''purchased'', ''Harbourfront Grill''',
  '(''Flowers and dinner at the Corniche'',''ورد وعشاء على الكورنيش''),(''Corniche Grill'',''مشويات الكورنيش'')','(''Flowers and dinner by the lake'',''ورد وعشاء على البحيرة''),(''Harbourfront Grill'',''مطعم الواجهة البحرية'')',
  '1, 340, null, ''SAR''','1, 120, null, ''USD''', '1, 450, null, ''SAR''','1, 130, null, ''USD''',
  'Sunset on the Corniche','Sunset in Cascais', 'غروب على الكورنيش','غروب في كاشكايش',
  '+966 11 000 0000','+1 416 555 0100', '+966 50 000 0000','+1 416 555 0123', 'Olaya, Riyadh','Queen St W, Toronto', 'Sun–Thu 9–21','Mon–Fri 9–6',
  'city_name = ''الرياض''','city_name = ''تورونتو''', 'else ''الرياض'' end','else ''تورونتو'' end',
  '''Fresh dates''','''Fresh bread''', '''Laban''','''Yogurt''', '''Cardamom coffee''','''Coffee beans''',
  '''تمر طازج''','''خبز طازج''', '''لبن''','''زبادي''', '''قهوة بالهيل''','''حبوب القهوة''', '''تجديد استمارة السيارة''','''تجديد ترخيص السيارة''',
  'AlUla','Banff', 'العُلا','بانف', 'Jeddah','Muskoka', 'جدة','موسكوكا'];
begin
  foreach f in array array['demo_reset','demo_arabic'] loop
    select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and p.proname = f;
    for i in 1..array_length(r, 1) by 2 loop def := replace(def, r[i], r[i + 1]); end loop;
    execute def;
  end loop;
end $do$;
