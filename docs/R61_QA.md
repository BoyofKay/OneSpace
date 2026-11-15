# R61 QA — Logo, Me tab, Voice 2.0

Install 0.1.4xx as an in-place update. Phone language English first, then Arabic.

## Shell and logo
1. The launcher icon is sharp (no blur) on the home screen and in Recents; themed icons (Android 13+) show the mark in one colour.
2. Top bar: mark, "OneSpace" and the full tagline are readable on a small phone; mic, bell and ⋮ fit.
3. Bottom bar: Today · Remember · Coordinate · Connect · Me. Me shows profile, Settings, Language, Search, Items to sort, Your data.
4. Coordinate has two tabs: Activities and Trips. Links that used to open World/Trips land on Coordinate → Trips.
5. No "Read aloud" item in any ⋮ menu, letter or checklist.

## Voice (tap the mic)
The sheet opens and listens straight away; words appear as you speak; it answers aloud and listens again. Say "no" / "that's all" or stay quiet to close.
1. "What's on today?" → spoken summary. Then "and tomorrow?" (or "what's on tomorrow").
2. "Read the groceries list" → open items read out. "Check off milk on the groceries list" → confirmed; the list shows it ticked.
3. "Add bread and eggs to the groceries list" → both added.
4. "Remind me to call the clinic tomorrow at 5 pm" → sheet closes, reminder page opens pre-filled; nothing saved until Save.
5. "I took my vitamins" (with a Vitamins reminder) → marked done. "Snooze the rent reminder for an hour" → snoozed.
6. "I'm feeling great today" → Daily connection shows today's mood.
7. "Send Kay a hug" → partner gets the gesture notification.
8. "How many days until our anniversary?", "When's our next trip?", "When do we see each other?"
9. "Read Kay's last letter", "Read the Paris trip", "Read the <activity name> activity".
10. Something unclear ("milk") → chips Reminder · Note · Event · To-do list.
11. Long-press the app icon → "Voice command" opens the app straight into the sheet.
12. Mic permission denied → clear message in the sheet, no crash. Airplane mode → "network" message.

## Arabic (switch app language to العربية)
Sheet is right-to-left, replies are spoken in Arabic.
- «ماذا لدينا اليوم؟» · «اقرأ قائمة المشتريات» · «أضف حليب وبيض إلى قائمة المشتريات»
- «اشطب الحليب من قائمة المشتريات» · «ذكرني بالدواء بعد نص ساعة» · «ذكرني أن أتصل بالعيادة بكرة الساعة 5 المساء»
- «أنا مبسوط اليوم» · «أرسل لها حضن» · «كم يوم باقي على ذكرى زواجنا؟» · «متى رحلتنا القادمة؟» · «خلاص» (closes)
