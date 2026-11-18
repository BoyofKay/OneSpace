# OneSpace: concise Arabic mobile UI copy — PROPOSAL ONLY

**Review pending. Not applied to Flutter strings. Do not merge/release until approved.**

## Principles

- OneSpace is an app, not a legal contract: prefer short, natural Modern Standard Arabic labels.
- Trim **only** navigation labels, titles, field labels, dropdown headers/options, chips and buttons.
- Preserve explanatory hints, accessibility descriptions, confirmation details, warnings and instructions; clarity outranks brevity.
- Do not abbreviate Arabic words or silently remove the meaning of controls.
- Aim for 1–3 words for common controls, 4 maximum when it materially improves clarity.
- Keep mixed Latin identifiers (OneSpace, Android, iPhone) in Latin script.
- Use existing space and status context to avoid redundant words, but make buttons accessible via semantics.
- Verify RTL order, icon/chevron mirroring, 320px phone width, text scaling 130%, both light/dark modes.

## Proposed substitutions (not executed)

| English UI term | Existing/long Arabic | Compact recommendation | Where |
|---|---|---|---|
| Today | اليوم | اليوم | Bottom navigation — keep |
| Remember | تذكّر | تذكّر | Bottom navigation — keep |
| Coordinate | نسّق | نسّق | Bottom navigation — keep |
| Connect | تواصل | تواصل | Bottom navigation — keep |
| Me | أنا | أنا | Bottom navigation — keep |
| Our day at a glance | لمحة عن يومنا | يومنا باختصار | Today card title |
| Explore our space | اكتشف مساحتنا | مساحتنا | Section title |
| Active activities | الأنشطة النشطة | أنشطة جارية | KPI label |
| High-priority activities | الأنشطة عالية الأولوية | المهمّة | KPI label inside Activities section |
| Activities due within 7 days | أنشطة مستحقة خلال ٧ أيام | خلال ٧ أيام | KPI label |
| Completed activities | الأنشطة المكتملة | المكتملة | KPI label |
| Recent discussions | أحدث المناقشات | آخر النقاشات | Card title |
| Edit relationship settings | تعديل إعدادات العلاقة | إعدادات العلاقة | Header |
| Choose our living situation | حدد وضع المعيشة | وضع المعيشة | Dropdown label |
| Living apart · same time zone | نعيش منفصلين في نفس التوقيت | بعيدًا · توقيت واحد | Dropdown option |
| Long-distance · different time zones | علاقة عن بعد · مناطق زمنية مختلفة | عن بُعد · توقيتان | Dropdown option |
| Shared calendar | التقويم المشترك | تقويمنا | Remember tile |
| To-do and Checklists | مهام وقوائم التحقق | المهام والقوائم | Section title |
| Upcoming dues | الاستحقاقات القادمة | المستحقات | Card heading |
| Upcoming events | الفعاليات القادمة | المواعيد القادمة | Card heading |
| See all | عرض الكل | عرض الكل | Keep familiar wording |
| Appearance & themes | المظهر والسمات | المظهر | Settings title |
| Make OneSpace yours | اجعل OneSpace على ذوقك | خصّص المظهر | Appearance heading |
| Color collection | مجموعات الألوان | الألوان | Theme picker |
| Regional holidays | العطلات الإقليمية | العطلات | Settings heading |
| Join space | الانضمام للمساحة | انضم للمساحة | CTA |
| Add to counters | إضافة إلى العدادات | أضف للعدّادات | CTA |
| Custom repeat | تكرار مخصص | تكرار مخصّص | Keep; already concise |
| Remind us before | ذكّرنا قبلها | تذكير قبل | Dropdown heading |
| No reminder | بدون تذكير | بلا تذكير | Option |
| Add photos | إضافة صور | أضف صورًا | Button; prefer verb |
| Link an item | ربط عنصر | اربط عنصرًا | Button; prefer verb |
| Save changes | حفظ التغييرات | حفظ | Button, if changes are obvious |
| Create activity | إنشاء نشاط جديد | نشاط جديد | Add sheet action |
| View history | عرض السجل | السجل | Context button |
| Invite partner | دعوة الشريك | ادعُ شريكك | CTA |
| First name | اسمك الأول | الاسم الأول | Field label |
| Email address | البريد الإلكتروني | البريد الإلكتروني | Keep; clear |
| How did you hear about us? | كيف عرفت عنا؟ | كيف عرفتنا؟ | Dropdown title |

## Deliberate exceptions

- Keep descriptions below each card, field validation errors, consent wording, payment/privacy notices and confirmations fully descriptive.
- One-word options that become ambiguous in isolation retain their noun: e.g., «المواعيد القادمة», not just «القادم».
- Avoid «منفصلان» in living situation options, as it might imply relationship separation; «بعيدًا» or «في منزلين» is less ambiguous.
- Retain task-specific distinctions between `نشاط`, `مهمة`, `قائمة`, `مناسبة`, and `تذكير`.

## Adoption process

When approved, apply the accepted terms consistently in `lib/l10n/onespace_strings.dart`, `lib/l10n/phrases_ar.dart`, and other widget-level literals. Review buttons, popup titles, dropdown headers, lists and RTL responsive layouts. **Do not ship an app release just because text changes were reviewed.**
