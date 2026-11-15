/// R64: Questions and answers, in English and Arabic. Keep answers short and
/// true to how the app works today (update when features change).
class FaqEntry {
  const FaqEntry(this.topicEn, this.topicAr, this.qEn, this.qAr, this.aEn, this.aAr);
  final String topicEn, topicAr, qEn, qAr, aEn, aAr;
  String topic(bool ar) => ar ? topicAr : topicEn;
  String q(bool ar) => ar ? qAr : qEn;
  String a(bool ar) => ar ? aAr : aEn;
}

const _start = ('Getting started', 'البداية');
const _privacy = ('Privacy and safety', 'الخصوصية والأمان');
const _daily = ('Everyday use', 'الاستخدام اليومي');
const _alerts = ('Reminders and notifications', 'التذكيرات والإشعارات');
const _account = ('Account and data', 'الحساب والبيانات');

final faqEntries = <FaqEntry>[
  FaqEntry(_start.$1, _start.$2,
    'What is OneSpace?', 'ما هو OneSpace؟',
    'A private space for the two of you: your shared calendar, to-do lists, reminders, notes, trips, occasions, memories, letters and little gestures of love — in one place, whether you live together or far apart.',
    'مساحة خاصة لكما أنتما الاثنين: تقويم مشترك وقوائم مهام وتذكيرات وملاحظات ورحلات ومناسبات وذكريات ورسائل ولمسات حب صغيرة — كلها في مكان واحد، سواء كنتما تعيشان معًا أو بعيدين.'),
  FaqEntry(_start.$1, _start.$2,
    'How do I connect my partner?', 'كيف أربط شريكي؟',
    'Create your space, then send your partner the invitation from the welcome screen. When they sign up and accept it, everything you share appears for both of you.',
    'أنشئ مساحتك، ثم أرسل الدعوة لشريكك من شاشة الترحيب. عندما يسجّل ويقبلها، يظهر كل ما تشاركانه لكليكما.'),
  FaqEntry(_start.$1, _start.$2,
    'What are the five tabs?', 'ما هي التبويبات الخمسة؟',
    'Today shows what needs you now. Remember holds the calendar, to-do lists, reminders and notes. Coordinate has Activities (plans and decisions) and Trips. Connect is for letters, daily connection, gestures, memories and experiences. Me is your profile, settings and help.',
    '«اليوم» يعرض ما يحتاجك الآن. «تذكّر» فيه التقويم وقوائم المهام والتذكيرات والملاحظات. «تنسيق» فيه الأنشطة (الخطط والقرارات) والرحلات. «تواصل» للرسائل والتواصل اليومي واللفتات والذكريات والتجارب. «أنا» لملفك الشخصي وإعداداتك والمساعدة.'),
  FaqEntry(_privacy.$1, _privacy.$2,
    'Who can see what I add?', 'من يمكنه رؤية ما أضيفه؟',
    'Only you and your partner — never anyone else. Each item shows "Shared" or "Only me" at the bottom of its page. Private items, drafts and private reminders are visible only to you.',
    'أنت وشريكك فقط — ولا أحد غيركما. يظهر في أسفل صفحة كل عنصر «مشترك» أو «أنا فقط». العناصر الخاصة والمسودات والتذكيرات الخاصة تظهر لك وحدك.'),
  FaqEntry(_privacy.$1, _privacy.$2,
    'Can I plan a surprise?', 'هل يمكنني التخطيط لمفاجأة؟',
    'Yes. Make the occasion, gift idea or note "Only me". Your partner will not see it or get any notification about it until you choose to share.',
    'نعم. اجعل المناسبة أو فكرة الهدية أو الملاحظة «أنا فقط». لن يراها شريكك ولن يصله أي إشعار عنها حتى تقرر مشاركتها.'),
  FaqEntry(_privacy.$1, _privacy.$2,
    'Does OneSpace track my location or phone?', 'هل يتتبع OneSpace موقعي أو هاتفي؟',
    'No. There is no location tracking, no activity tracking and no "online" status. For weather you choose a city yourself. Photos and documents stay private to the two of you.',
    'لا. لا يوجد تتبع للموقع ولا للنشاط ولا حالة «متصل». للطقس تختار المدينة بنفسك. الصور والمستندات تبقى خاصة بكما.'),
  FaqEntry(_privacy.$1, _privacy.$2,
    'Can I lock the app?', 'هل يمكنني قفل التطبيق؟',
    'Yes. OneSpace can ask for your phone PIN, fingerprint or Face ID when it opens.',
    'نعم. يمكن أن يطلب OneSpace رمز الهاتف أو البصمة أو بصمة الوجه عند فتحه.'),
  FaqEntry(_daily.$1, _daily.$2,
    'Where did something I removed go?', 'أين ذهب شيء حذفته؟',
    'Removed items are kept. Open the filter on that screen and turn on "Removed", then open the item and choose Restore from its ⋮ menu.',
    'العناصر المحذوفة محفوظة. افتح عامل التصفية في تلك الشاشة وفعّل «المحذوفة»، ثم افتح العنصر واختر «استعادة» من قائمة ⋮.'),
  FaqEntry(_daily.$1, _daily.$2,
    'How do I save something from another app?', 'كيف أحفظ شيئًا من تطبيق آخر؟',
    'On Android, use Share in any app and choose OneSpace. It lands in "Items to sort" (⋮ at the top) where you turn it into a note, to-do, trip item or memory. Sharing into OneSpace on iPhone is coming.',
    'على أندرويد، استخدم «مشاركة» في أي تطبيق واختر OneSpace. يصل إلى «عناصر للفرز» (⋮ بالأعلى) حيث تحوّله إلى ملاحظة أو مهمة أو عنصر رحلة أو ذكرى. المشاركة إلى OneSpace على iPhone قادمة.'),
  FaqEntry(_daily.$1, _daily.$2,
    'How do I change the language?', 'كيف أغيّر اللغة؟',
    'Me → Language. You and your partner can each use a different language; what you share is shown to each of you in your own app language.',
    '«أنا» ← «اللغة». يمكن لكل منكما استخدام لغة مختلفة؛ ويظهر لكل منكما ما تشاركانه بلغة تطبيقه.'),
  FaqEntry(_daily.$1, _daily.$2,
    'Can I change the colors and background?', 'هل يمكنني تغيير الألوان والخلفية؟',
    'Yes. Me → Settings → Appearance & themes: choose a color theme, light or dark, and a seasonal background (or let it follow the date).',
    'نعم. «أنا» ← «الإعدادات» ← «المظهر»: اختر لون السمة والوضع الفاتح أو الداكن وخلفية موسمية (أو اجعلها تتبع التاريخ).'),
  FaqEntry(_alerts.$1, _alerts.$2,
    'I am not getting notifications.', 'لا تصلني الإشعارات.',
    'Check that notifications for OneSpace are allowed in your phone settings, and that battery saving is not restricting it. Alerts wait during your partner\'s sleep hours unless marked Urgent. If it still does not work, use Report a technical issue.',
    'تأكد أن إشعارات OneSpace مسموحة في إعدادات هاتفك، وأن توفير البطارية لا يقيّده. تنتظر التنبيهات أثناء ساعات نوم شريكك إلا إذا كانت «عاجلة». إن استمرت المشكلة استخدم «الإبلاغ عن مشكلة تقنية».'),
  FaqEntry(_alerts.$1, _alerts.$2,
    'How do quiet hours and time zones work?', 'كيف تعمل ساعات الهدوء والمناطق الزمنية؟',
    'Each of you sets work and sleep hours in Settings. Times are shown in each phone\'s own time zone, and non-urgent alerts are held until the other person wakes up.',
    'يحدد كل منكما ساعات العمل والنوم في الإعدادات. تظهر الأوقات بالمنطقة الزمنية لكل هاتف، وتنتظر التنبيهات غير العاجلة حتى يستيقظ الطرف الآخر.'),
  FaqEntry(_account.$1, _account.$2,
    'How do I download my data?', 'كيف أنزّل بياناتي؟',
    'Me → Your data and account → Download my data. You get one file with everything you created or received. Photos and documents stay in the app.',
    '«أنا» ← «بياناتك وحسابك» ← «تنزيل بياناتي». تحصل على ملف واحد بكل ما أنشأته أو استلمته. تبقى الصور والمستندات داخل التطبيق.'),
  FaqEntry(_account.$1, _account.$2,
    'What happens if I delete my account?', 'ماذا يحدث إذا حذفت حسابي؟',
    'You are signed out and have 7 days to change your mind. After that your private items, photos and settings are deleted and you leave your shared space. Items you shared stay for your partner.',
    'يتم تسجيل خروجك ولديك 7 أيام لتغيير رأيك. بعد ذلك تُحذف عناصرك الخاصة وصورك وإعداداتك وتغادر مساحتكما المشتركة. تبقى العناصر التي شاركتها لشريكك.'),
  FaqEntry(_account.$1, _account.$2,
    'I forgot my password.', 'نسيت كلمة المرور.',
    'On the sign-in screen tap "Forgot your password?" and follow the link sent to your email.',
    'في شاشة تسجيل الدخول اضغط «نسيت كلمة المرور؟» واتبع الرابط المرسل إلى بريدك.'),
  FaqEntry(_account.$1, _account.$2,
    'Is OneSpace available on iPhone?', 'هل OneSpace متاح على iPhone؟',
    'The iPhone version is being prepared and will first be shared through TestFlight. Your account and everything in your space will be the same on both phones.',
    'نسخة iPhone قيد التجهيز وستتاح أولًا عبر TestFlight. حسابك وكل ما في مساحتكما سيكون نفسه على الهاتفين.'),
];
