#!/usr/bin/env python3
"""Builds the OneSpace website (static HTML, English with an Arabic switch).

Edit the content below, then run:  python3 build.py
Pages: index, privacy, terms, support, delete-account, 404.
"""
import json
from html import escape

UPDATED = '16 November 2026'
UPDATED_AR = '16 نوفمبر 2026'
AR = {}


def t(key, en, ar, tag='span', cls=''):
    """An element whose text switches to Arabic."""
    AR[key] = ar
    c = f' class="{cls}"' if cls else ''
    return f'<{tag}{c} data-i18n="{key}">{en}</{tag}>'


def head(title, title_ar, desc, path):
    return f'''<!doctype html>
<html lang="en" dir="ltr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title data-ar="{escape(title_ar)}">{escape(title)}</title>
<meta name="description" content="{escape(desc)}">
<link rel="canonical" href="https://boyofkay.github.io/onespace-app/{'' if path == 'index' else path + '.html'}">
<meta name="robots" content="index,follow">
<meta property="og:title" content="{escape(title)}">
<meta property="og:description" content="{escape(desc)}">
<meta property="og:image" content="https://boyofkay.github.io/onespace-app/assets/icon-512.png">
<meta property="og:type" content="website">
<meta name="theme-color" content="#1F6670">
<link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png">
<link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=Noto+Kufi+Arabic:wght@400;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/style.css">
</head>
<body>
<header class="top"><div class="wrap">
  <a class="brand" href="./"><img src="assets/mark.svg" alt="">OneSpace</a>
  <nav class="nav">
    <a class="hide-sm" href="./#features">{t('nav.features', 'Features', 'المزايا')}</a>
    <a class="hide-sm" href="./#privacy">{t('nav.privacy', 'Privacy', 'الخصوصية')}</a>
    <a href="getting-started.html">{t('nav.guides', 'Guides', 'الدليل')}</a>
    <a href="support.html">{t('nav.support', 'Support', 'الدعم')}</a>
    <button class="lang" type="button">العربية</button>
  </nav>
</div></header>
'''


def foot():
    return f'''<footer><div class="wrap">
  <span>© <span id="year">2026</span> OneSpace</span>
  <nav>
    <a href="privacy.html">{t('foot.privacy', 'Privacy policy', 'سياسة الخصوصية')}</a>
    <a href="terms.html">{t('foot.terms', 'Terms of use', 'شروط الاستخدام')}</a>
    <a href="delete-account.html">{t('foot.delete', 'Delete your account', 'حذف حسابك')}</a>
    <a href="support.html">{t('foot.support', 'Support', 'الدعم')}</a>
  </nav>
</div></footer>
<script src="assets/ar.js"></script>
<script src="assets/site.js"></script>
</body>
</html>
'''


def feature(key, icon, color, en_t, en_p, ar_t, ar_p):
    return f'''<div class="card"><div class="ico {color}">{icon}</div>
  {t(key + '.t', en_t, ar_t, 'h3')}
  {t(key + '.p', en_p, ar_p, 'p')}</div>'''


# ---------------------------------------------------------------- Home
def index():
    plan = [
        ('f.cal', '📅', 'c2', 'One calendar for two', 'Shared events in both your time zones, birthdays and holidays for your countries — and, if you like, in your phone\'s own calendar.',
         'تقويم واحد لكما', 'مواعيد مشتركة بتوقيت كل منكما، وأعياد الميلاد والعطلات الرسمية لبلديكما — وفي تقويم هاتفك إن أردت.'),
        ('f.todo', '✅', 'c1', 'To-dos and reminders', 'Lists you both tick off, due dates, "remind my partner", and gentle nudges that never wake anyone up.',
         'المهام والتذكيرات', 'قوائم تنجزانها معًا، ومواعيد استحقاق، و«ذكّر شريكي»، وتنبيهات لطيفة لا توقظ أحدًا.'),
        ('f.act', '🧭', 'c3', 'Decide together', 'Activities with options side by side, notes, voice messages and a clear decision at the end — from a new sofa to a weekend away.',
         'قررا معًا', 'أنشطة تعرض الخيارات جنبًا إلى جنب مع الملاحظات والرسائل الصوتية وقرار واضح في النهاية — من أريكة جديدة إلى عطلة نهاية أسبوع.'),
        ('f.trip', '✈️', 'c2', 'Trips', 'Flights to compare, places to stay, documents, packing checklists and a countdown to the day you fly.',
         'الرحلات', 'رحلات طيران للمقارنة، وأماكن إقامة، ومستندات، وقوائم تجهيز، وعدّ تنازلي ليوم السفر.'),
        ('f.occ', '🎁', 'c4', 'Occasions and gifts', 'Gift ideas, budgets and early preparation for every birthday, anniversary and holiday.',
         'المناسبات والهدايا', 'أفكار هدايا وميزانيات وتحضير مبكر لكل عيد ميلاد وذكرى سنوية ومناسبة.'),
        ('f.notes', '📝', 'c1', 'Notes', 'Rich notes with photos and checklists, shared or just for you.',
         'الملاحظات', 'ملاحظات منسقة مع صور وقوائم، مشتركة أو لك وحدك.'),
    ]
    close = [
        ('f.letters', '💌', 'c1', 'Letters', 'Write a real letter — and seal it until a date you choose.',
         'الرسائل', 'اكتب رسالة حقيقية — وأغلقها حتى تاريخ تختاره.'),
        ('f.love', '🤍', 'c3', 'A little love', 'A hug, a good morning, "proud of you" — one tap, or sent for you at the right moment in your partner\'s day.',
         'لمسة حب', 'حضن، صباح الخير، «فخور بك» — بلمسة واحدة، أو تُرسل نيابة عنك في الوقت المناسب من يوم شريكك.'),
        ('f.check', '🌤️', 'c2', 'Daily check-in', 'Share how you feel today and keep a gentle journal of your moods together.',
         'التواصل اليومي', 'شارك شعورك اليوم واحتفظا بيوميات لطيفة لمشاعركما.'),
        ('f.exp', '🎬', 'c4', 'Shared experiences', 'Movies, shows, books and games you want to enjoy together — with ratings and a conversation for each.',
         'التجارب المشتركة', 'أفلام ومسلسلات وكتب وألعاب تريدان الاستمتاع بها معًا — مع التقييمات ومحادثة لكل منها.'),
        ('f.mem', '📸', 'c1', 'Memories', 'Stories, a two-way daily selfie and scrapbooks you can save as a PDF.',
         'الذكريات', 'قصص، وسيلفي يومي من الطرفين، وألبومات قصاصات تحفظانها كملف PDF.'),
        ('f.places', '📍', 'c2', 'Our places and counters', 'A map of where you have been and a bucket list to plan from — plus counters for the days since and until what matters.',
         'أماكننا والعدّادات', 'خريطة للأماكن التي زرتماها وقائمة أحلام تخططان منها — وعدّادات للأيام منذ ما يهمكما وحتى القادم منه.'),
    ]
    html = head('OneSpace — one private space for the two of you', 'OneSpace — مساحة خاصة واحدة لكما',
                'OneSpace is a private app for couples: plan together, stay close and remember what matters — in Arabic and English.', 'index')
    html += f'''<main>
<section class="hero"><div class="wrap">
  <div>
    {t('hero.eyebrow', 'For couples · Arabic and English', 'للأزواج · بالعربية والإنجليزية', 'span', 'eyebrow')}
    {t('hero.title', 'One private space<br>for <em>the two of you</em>', 'مساحة خاصة واحدة<br><em>لكما أنتما</em>', 'h1')}
    {t('hero.lead', 'OneSpace brings your plans, your little gestures and your memories into one place that only you and your partner can see — whether you share a home or live time zones apart.',
       'يجمع OneSpace خططكما ولفتاتكما الصغيرة وذكرياتكما في مكان واحد لا يراه سواكما — سواء كنتما في بيت واحد أو تفصلكما المناطق الزمنية.', 'p', 'lead')}
    <div class="cta">
      <a class="btn btn-primary" href="support.html?topic=beta">{t('hero.join', 'Ask to join the test', 'اطلب الانضمام للتجربة')}</a>
      <a class="btn btn-ghost" href="feature-tour.html">{t('hero.tour', 'Explore the feature tour', 'اكتشف جولة المزايا')}</a>
      <a class="btn btn-ghost" href="#features">{t('hero.more', 'See what is inside', 'اكتشف المزايا')}</a>
    </div>
    {t('hero.note', 'Now in a private test with a few couples · Android now, iPhone soon.', 'في تجربة خاصة مع عدد قليل من الأزواج · أندرويد الآن، وiPhone قريبًا.', 'p', 'note')}
  </div>
  <div class="phone" aria-hidden="true"><div class="screen">
    <div class="hello" data-i18n="m.hello">Good evening, Omar</div>
    <div class="sub" data-i18n="m.sub">Your space with Lina</div>
    <div class="mini"><div class="ico c1">🤍</div><div><b data-i18n="m.g">Lina sent you a hug</b><span data-i18n="m.gs">“Sending you a big, warm hug.”</span></div></div>
    <div class="mini"><div class="ico c2">✈️</div><div style="flex:1"><b data-i18n="m.t">Trip to Istanbul</b><span data-i18n="m.ts">Flights booked · 2 of 9 packed</span><div class="bar"><i></i></div></div><div class="big" data-i18n="m.tb">24 days</div></div>
    <div class="mini"><div class="ico c3">💍</div><div><b data-i18n="m.a">Our 6th anniversary</b><span data-i18n="m.as">1 May · gift ideas ready</span></div><div class="big" data-i18n="m.ab">5 months</div></div>
    <div class="mini"><div class="ico c4">✅</div><div><b data-i18n="m.d">Book the dinner</b><span data-i18n="m.ds">Assigned to you · today</span></div></div>
    <div class="tiles">
      <div><i>📅</i><span data-i18n="m.1">Calendar</span></div><div><i>💌</i><span data-i18n="m.2">Letters</span></div><div><i>📸</i><span data-i18n="m.3">Memories</span></div>
      <div><i>🎁</i><span data-i18n="m.4">Occasions</span></div><div><i>📍</i><span data-i18n="m.5">Places</span></div><div><i>⏳</i><span data-i18n="m.6">Counters</span></div>
    </div>
  </div></div>
</div></section>

<section id="features"><div class="wrap">
  <div class="center">
    {t('feat.title', 'Everything a couple shares, in one calm place', 'كل ما يتشاركه الزوجان في مكان واحد هادئ', 'h2')}
    {t('feat.lead', 'No more plans lost in chats, birthdays remembered at the last minute or photos scattered across two phones.',
       'لا مزيد من الخطط الضائعة في المحادثات، ولا أعياد ميلاد نتذكرها في اللحظة الأخيرة، ولا صور مبعثرة بين هاتفين.', 'p', 'section-lead')}
  </div>
  {t('feat.plan', 'Plan together', 'خططا معًا', 'div', 'group-title')}
  <div class="grid">{''.join(feature(*f) for f in plan)}</div>
  {t('feat.close', 'Stay close', 'ابقيا قريبين', 'div', 'group-title')}
  <div class="grid">{''.join(feature(*f) for f in close)}</div>
</div></section>

<section><div class="wrap split">
  <div>
    {t('life.title', 'Made for real couples\' lives', 'مصمم لحياة الأزواج الحقيقية', 'h2')}
    {t('life.lead', 'OneSpace adapts to how you live — and stays out of the way.', 'يتكيف OneSpace مع طريقة عيشكما — ولا يزعجكما.', 'p', 'section-lead" style="margin:0')}
    <ul class="check">
      {t('life.1', '<b>Apart or together.</b> Both clocks and weathers on Today, a countdown to when you meet — or none of that when you share a home.', '<b>معًا أو متباعدين.</b> ساعتا كل منكما وطقسه في «اليوم»، وعدّ تنازلي للقاء — أو لا شيء من ذلك إن كنتما في بيت واحد.', 'li')}
      {t('life.2', '<b>Arabic and English.</b> Each of you chooses your language; the whole app, notifications included, follows.', '<b>العربية والإنجليزية.</b> يختار كل منكما لغته، ويتبعها التطبيق كله بما في ذلك الإشعارات.', 'li')}
      {t('life.3', '<b>Respects your sleep.</b> Nothing arrives during your night; it waits for a gentle morning summary.', '<b>يحترم نومك.</b> لا يصلك شيء أثناء ليلك؛ ينتظر ملخصًا لطيفًا في الصباح.', 'li')}
      {t('life.4', '<b>Share from any app.</b> A product, a place on Google Maps, a flight or a film goes straight into the right list.', '<b>شارك من أي تطبيق.</b> منتج أو مكان من خرائط Google أو رحلة طيران أو فيلم يذهب مباشرة إلى القائمة المناسبة.', 'li')}
    </ul>
  </div>
  <div class="card" style="padding:30px">
    <div class="mini"><div class="ico c2">🕰️</div><div><b data-i18n="l.c1">Riyadh 8:14 PM · 31°</b><span data-i18n="l.c1s">You</span></div></div>
    <div class="mini"><div class="ico c1">🌙</div><div><b data-i18n="l.c2">London 6:14 PM · 9°</b><span data-i18n="l.c2s">Lina · good time to talk</span></div></div>
    <div class="mini"><div class="ico c3">🤍</div><div style="flex:1"><b data-i18n="l.c3">Until we meet again</b><div class="bar"><i style="width:78%"></i></div></div><div class="big" data-i18n="l.c3b">12 days</div></div>
  </div>
</div></section>

<section><div class="wrap"><h2>Explore OneSpace for your relationship</h2><p>Discover how OneSpace helps couples organize life together, wherever they live.</p><div class="grid"><div class="card"><h3>Couples app</h3><p>Shared planning, decisions and connection.</p><a href="couples-app.html">Explore OneSpace for couples</a></div><div class="card"><h3>Long-distance relationships</h3><p>Two schedules, one shared space.</p><a href="long-distance-relationship-app.html">Explore long-distance planning</a></div><div class="card"><h3>Shared calendar</h3><p>Important dates and plans in one place.</p><a href="shared-calendar-for-couples.html">Explore the calendar</a></div></div></div></section>

<section id="privacy"><div class="wrap"><div class="band">
  {t('priv.title', 'Private by design', 'الخصوصية في التصميم', 'h2')}
  {t('priv.lead', 'Your space belongs to the two of you. Nobody else — not other couples, not advertisers — can see inside it.', 'مساحتكما ملك لكما. لا يمكن لأحد غيركما — لا أزواج آخرون ولا معلنون — أن يرى ما بداخلها.', 'p')}
  <div class="grid" style="margin-top:26px">
    {feature('p1', '🔒', '', 'Only you two', 'Every item is either Shared with your partner or Only me. Access rules are enforced on our servers, item by item.', 'أنتما فقط', 'كل عنصر إما «مشترك» مع شريكك أو «أنا فقط». تُطبَّق قواعد الوصول على خوادمنا لكل عنصر.')}
    {feature('p2', '🚫', '', 'No ads, no selling', 'We don\'t show ads, sell data, track your location or read your content to profile you.', 'بلا إعلانات ولا بيع', 'لا نعرض إعلانات ولا نبيع البيانات ولا نتتبع موقعك ولا نقرأ محتواك لبناء ملف عنك.')}
    {feature('p3', '📦', '', 'Yours to keep or delete', 'Download everything you created at any time, or delete your account — right from the app.', 'لك أن تحتفظ أو تحذف', 'نزّل كل ما أنشأته في أي وقت، أو احذف حسابك — من داخل التطبيق مباشرة.')}
  </div>
  <p style="margin-top:22px"><a style="color:#fff" href="privacy.html">{t('priv.link', 'Read the privacy policy →', 'اقرأ سياسة الخصوصية ←')}</a></p>
</div></div></section>

<section><div class="wrap" style="max-width:820px">
  <div class="center">{t('faq.title', 'Questions', 'أسئلة', 'h2')}</div>
  <details><summary>{t('faq.q1', 'Does my partner need the app too?', 'هل يحتاج شريكي إلى التطبيق أيضًا؟')}</summary>{t('faq.a1', 'Yes — OneSpace connects exactly two people. One of you creates the space and invites the other with a link or a QR code.', 'نعم — يربط OneSpace شخصين فقط. ينشئ أحدكما المساحة ويدعو الآخر برابط أو رمز QR.', 'p')}</details>
  <details><summary>{t('faq.q2', 'How much does it cost?', 'كم يكلف؟')}</summary>{t('faq.a2', 'It is free during the test.', 'مجاني خلال فترة التجربة.', 'p')}</details>
  <details><summary>{t('faq.q3', 'Is there an iPhone version?', 'هل يوجد إصدار لـ iPhone؟')}</summary>{t('faq.a3', 'Coming soon. The test starts on Android; iPhone testers will join through Apple\'s TestFlight.', 'قريبًا. تبدأ التجربة على أندرويد، وسينضم مختبرو iPhone عبر TestFlight من Apple.', 'p')}</details>
  <details><summary>{t('faq.q4', 'Can I use it in Arabic?', 'هل يمكنني استخدامه بالعربية؟')}</summary>{t('faq.a4', 'Yes. Each partner picks Arabic or English, and the layout follows (right to left in Arabic).', 'نعم. يختار كل شريك العربية أو الإنجليزية، ويتبعها التصميم (من اليمين إلى اليسار بالعربية).', 'p')}</details>
  <details><summary>{t('faq.q5', 'What happens to our things if one of us leaves?', 'ماذا يحدث لأشيائنا إذا غادر أحدنا؟')}</summary>{t('faq.a5', 'Shared items stay with the other person; private items are deleted. See <a href="delete-account.html">Delete your account</a>.', 'تبقى العناصر المشتركة مع الشخص الآخر، وتُحذف العناصر الخاصة. راجع <a href="delete-account.html">حذف حسابك</a>.', 'p')}</details>
  <div class="center" style="margin-top:30px"><a class="btn btn-primary" href="support.html?topic=beta">{t('faq.join', 'Ask to join the test', 'اطلب الانضمام للتجربة')}</a></div>
</div></section>
</main>
'''
    AR.update({'m.hello': 'مساء الخير، عمر', 'm.sub': 'مساحتك مع لينا', 'm.g': 'أرسلت لك لينا حضنًا', 'm.gs': '«أرسل لك حضنًا كبيرًا ودافئًا.»',
               'm.t': 'رحلة إلى إسطنبول', 'm.ts': 'تم حجز الطيران · جُهّز 2 من 9', 'm.tb': '24 يومًا', 'm.a': 'ذكرانا السادسة',
               'm.as': '1 مايو · أفكار الهدايا جاهزة', 'm.ab': '5 أشهر', 'm.d': 'احجز العشاء', 'm.ds': 'مُسند إليك · اليوم',
               'm.1': 'التقويم', 'm.2': 'الرسائل', 'm.3': 'الذكريات', 'm.4': 'المناسبات', 'm.5': 'الأماكن', 'm.6': 'العدّادات',
               'l.c1': 'الرياض 8:14 م · 31°', 'l.c1s': 'أنت', 'l.c2': 'لندن 6:14 م · 9°', 'l.c2s': 'لينا · وقت مناسب للحديث',
               'l.c3': 'حتى نلتقي مجددًا', 'l.c3b': '12 يومًا'})
    return html + foot()


def legal_page(slug, title, title_ar, intro_en, intro_ar, sections):
    html = head(f'{title} — OneSpace', f'{title_ar} — OneSpace', f'OneSpace {title.lower()}.', slug)
    body = ''.join(f'{t(f"{slug}.h{i}", h_en, h_ar, "h2")}{t(f"{slug}.p{i}", p_en, p_ar, "div")}'
                   for i, (h_en, p_en, h_ar, p_ar) in enumerate(sections))
    html += f'''<main class="page"><div class="wrap">
  {t(slug + '.title', title, title_ar, 'h1')}
  {t(slug + '.updated', 'Last updated: ' + UPDATED, 'آخر تحديث: ' + UPDATED_AR, 'p', 'meta')}
  {t(slug + '.intro', intro_en, intro_ar, 'p')}
  {body}
</div></main>
'''
    return html + foot()


def privacy():
    s = [
        ('Who we are', '<p>OneSpace is an app for couples. In this policy “we” means the OneSpace team. You can reach us any time from <a href="support.html">Support</a>, from the sign-in screen of the app, or from Me → Help in the app.</p>',
         'من نحن', '<p>OneSpace تطبيق للأزواج. في هذه السياسة تعني «نحن» فريق OneSpace. يمكنك التواصل معنا في أي وقت من <a href="support.html">الدعم</a>، أو من شاشة الدخول في التطبيق، أو من «أنا» ← «المساعدة».</p>'),
        ('What we collect', '<ul><li><b>Your account:</b> name, email address, language, time zone and the settings you choose (for example sleep hours, preferred currency, how you live).</li><li><b>What you create:</b> notes, lists, reminders, events, activities, trips and travel documents, occasions, memories and photos, letters, check-ins, gestures, places and counters.</li><li><b>Your device for notifications:</b> a push token so we can deliver notifications to your phone.</li><li><b>Messages to support:</b> what you write to us, your email for the reply, and technical details only when you allow it.</li><li><b>Error reports:</b> when the app hits an error it sends the error message, app version and platform — never your content. They are deleted after 60 days.</li></ul><p>We do <b>not</b> collect your location, contacts, call logs, browsing or advertising identifiers. If you choose a contact or a calendar on your phone, that happens on your phone; only what you save in OneSpace is stored.</p>',
         'ما الذي نجمعه', '<ul><li><b>حسابك:</b> الاسم والبريد الإلكتروني واللغة والمنطقة الزمنية والإعدادات التي تختارها (مثل ساعات النوم والعملة المفضلة وطريقة عيشكما).</li><li><b>ما تنشئه:</b> الملاحظات والقوائم والتذكيرات والمواعيد والأنشطة والرحلات ومستندات السفر والمناسبات والذكريات والصور والرسائل والتواصل اليومي واللفتات والأماكن والعدّادات.</li><li><b>جهازك للإشعارات:</b> رمز إشعارات لإيصال الإشعارات إلى هاتفك.</li><li><b>رسائل الدعم:</b> ما تكتبه لنا وبريدك للرد، والتفاصيل التقنية فقط عند سماحك بذلك.</li><li><b>تقارير الأخطاء:</b> عند حدوث خطأ يرسل التطبيق رسالة الخطأ وإصدار التطبيق والمنصة — ولا يرسل محتواك أبدًا. وتُحذف بعد 60 يومًا.</li></ul><p><b>لا</b> نجمع موقعك أو جهات اتصالك أو سجل مكالماتك أو تصفحك أو معرّفات الإعلانات. إذا اخترت جهة اتصال أو تقويمًا على هاتفك فذلك يتم على هاتفك، ولا يُحفظ إلا ما تحفظه في OneSpace.</p>'),
        ('Who can see it', '<p>Everything in your space is visible only to you and your partner. Each item is either <b>Shared</b> (both of you) or <b>Only me</b> (just you). These rules are enforced by our database for every item, not only by the app. We do not access your content except to keep the service running, to answer a request you make, or when the law requires it.</p>',
         'من يمكنه رؤيته', '<p>كل ما في مساحتكما لا يراه سواكما. كل عنصر إما <b>مشترك</b> (لكما) أو <b>أنا فقط</b> (لك وحدك). وتُطبّق قاعدة البيانات هذه القواعد على كل عنصر، وليس التطبيق وحده. لا نطّلع على محتواكما إلا لتشغيل الخدمة أو للرد على طلب منك أو عندما يلزم القانون بذلك.</p>'),
        ('Services we use', '<ul><li><b>Supabase</b> — our database, sign-in and file storage (hosted in the Asia-Pacific region).</li><li><b>Firebase Cloud Messaging (Google)</b> — to deliver notifications to your phone.</li><li><b>OpenStreetMap</b> — map tiles for “Our map”, and place search: when you look up a place, its name, city and country are sent to OpenStreetMap’s search service.</li><li><b>Google or Apple sign-in</b> — only if you choose to sign in that way.</li><li><b>Weather and public-holiday services</b> — receive only a city or a country, never who you are.</li></ul><p>We never sell your data or share it for advertising.</p>',
         'الخدمات التي نستخدمها', '<ul><li><b>Supabase</b> — قاعدة البيانات وتسجيل الدخول وتخزين الملفات (مستضافة في منطقة آسيا والمحيط الهادئ).</li><li><b>Firebase Cloud Messaging (Google)</b> — لإيصال الإشعارات إلى هاتفك.</li><li><b>OpenStreetMap</b> — بلاطات الخريطة في «خريطتنا» والبحث عن الأماكن: عند البحث عن مكان يُرسل اسمه ومدينته ودولته إلى خدمة البحث في OpenStreetMap.</li><li><b>تسجيل الدخول عبر Google أو Apple</b> — فقط إذا اخترت ذلك.</li><li><b>خدمات الطقس والعطلات الرسمية</b> — تستقبل مدينة أو دولة فقط، ولا تعرف من أنت.</li></ul><p>لا نبيع بياناتك ولا نشاركها لأغراض إعلانية أبدًا.</p>'),
        ('How long we keep it', '<p>We keep your data while your account exists. When you delete your account there is a 7-day period to change your mind; after that, your private items, files, devices and settings are deleted, and shared items stay with your partner with you shown as “Former partner”. Error reports are deleted after 60 days.</p>',
         'مدة الاحتفاظ', '<p>نحتفظ ببياناتك ما دام حسابك موجودًا. عند حذف حسابك لديك 7 أيام للتراجع، وبعدها تُحذف عناصرك الخاصة وملفاتك وأجهزتك وإعداداتك، وتبقى العناصر المشتركة مع شريكك ويظهر اسمك «شريك سابق». وتُحذف تقارير الأخطاء بعد 60 يومًا.</p>'),
        ('Your rights and choices', '<ul><li><b>Download</b> everything you created: Me → Your data and account → Download my data.</li><li><b>Correct</b> your details in Me → Profile.</li><li><b>Delete</b> your account in the app, or ask us on the <a href="delete-account.html">Delete your account</a> page.</li><li><b>Notifications</b> can be turned off at any time in the app or in your phone settings.</li></ul>',
         'حقوقك وخياراتك', '<ul><li><b>نزّل</b> كل ما أنشأته: «أنا» ← «بياناتك وحسابك» ← «تنزيل بياناتي».</li><li><b>صحّح</b> بياناتك من «أنا» ← «الملف الشخصي».</li><li><b>احذف</b> حسابك من التطبيق، أو اطلب ذلك من صفحة <a href="delete-account.html">حذف حسابك</a>.</li><li>يمكنك إيقاف <b>الإشعارات</b> في أي وقت من التطبيق أو من إعدادات هاتفك.</li></ul>'),
        ('Security', '<p>Data travels encrypted (HTTPS). Access is checked on the server for every item. On your phone you can lock the app with your fingerprint or phone PIN. No system is perfect; if something goes wrong that affects you, we will tell you.</p>',
         'الأمان', '<p>تنتقل البيانات مشفّرة (HTTPS). ويُتحقق من صلاحية الوصول على الخادم لكل عنصر. ويمكنك قفل التطبيق على هاتفك ببصمتك أو رمز هاتفك. لا يوجد نظام مثالي؛ وإذا حدث ما يمسّك فسنخبرك.</p>'),
        ('Children', '<p>OneSpace is for adults aged 18 and over. We do not knowingly collect data from children.</p>',
         'الأطفال', '<p>OneSpace للبالغين من عمر 18 عامًا فأكثر. ولا نجمع بيانات الأطفال عن علم.</p>'),
        ('Changes', '<p>If we change this policy in a way that matters, we will tell you in the app before it applies.</p>',
         'التغييرات', '<p>إذا غيّرنا هذه السياسة تغييرًا مهمًا فسنخبرك في التطبيق قبل تطبيقه.</p>'),
    ]
    return legal_page('privacy', 'Privacy policy', 'سياسة الخصوصية',
                      'In short: your space is private to you and your partner, we don’t sell data or show ads, and you can download or delete everything at any time.',
                      'باختصار: مساحتكما خاصة بكما، ولا نبيع البيانات ولا نعرض إعلانات، ويمكنك تنزيل كل شيء أو حذفه في أي وقت.', s)


def terms():
    s = [
        ('Your account', '<p>You need to be at least 18. Give a real email address and keep your sign-in private. You are responsible for what happens under your account. One shared space connects exactly two people.</p>',
         'حسابك', '<p>يجب أن يكون عمرك 18 عامًا على الأقل. استخدم بريدًا حقيقيًا وحافظ على سرية تسجيل دخولك. أنت مسؤول عمّا يحدث في حسابك. المساحة المشتركة تجمع شخصين فقط.</p>'),
        ('Your content', '<p>What you write and upload stays yours. You give OneSpace only the permission needed to store it, show it to you and your partner, and send you notifications about it. We do not sell it, show ads or use it to profile you.</p>',
         'محتواك', '<p>ما تكتبه وترفعه يبقى ملكك. تمنح OneSpace فقط الإذن اللازم لحفظه وعرضه لك ولشريكك وإرسال إشعارات عنه. لا نبيعه ولا نعرض إعلانات ولا نستخدمه لبناء ملف عنك.</p>'),
        ('Sharing with your partner', '<p>Items marked “Shared” are visible to your partner and may notify them. “Only me” items are visible only to you. If one of you leaves or deletes the account, shared items stay with the other person.</p>',
         'المشاركة مع شريكك', '<p>العناصر «المشتركة» يراها شريكك وقد تصله إشعارات عنها. عناصر «أنا فقط» تراها وحدك. إذا غادر أحدكما أو حذف حسابه، تبقى العناصر المشتركة مع الآخر.</p>'),
        ('Acceptable use', '<p>Do not use OneSpace to harass, threaten or spy on anyone, to store illegal material, or to break into other accounts or the service. We may suspend accounts that do.</p>',
         'الاستخدام المقبول', '<p>لا تستخدم OneSpace للمضايقة أو التهديد أو التجسس على أحد، أو لحفظ مواد غير قانونية، أو لاختراق حسابات أخرى أو الخدمة. قد نوقف الحسابات المخالفة.</p>'),
        ('Test version', '<p>OneSpace is in an early test with a small group of people. Features may change and something may break. Please keep your own copy of anything important and tell us about problems.</p>',
         'نسخة تجريبية', '<p>OneSpace في تجربة مبكرة مع مجموعة صغيرة. قد تتغير الميزات وقد يتعطل شيء. احتفظ بنسخة من كل ما هو مهم، وأخبرنا بأي مشكلة.</p>'),
        ('Ending', '<p>You can download your data and delete your account at any time (Me → Your data and account). We may end the test or the service with notice by email.</p>',
         'الإنهاء', '<p>يمكنك تنزيل بياناتك وحذف حسابك في أي وقت («أنا» ← «بياناتك وحسابك»). قد ننهي التجربة أو الخدمة بإشعار عبر البريد.</p>'),
        ('Liability', '<p>OneSpace is provided “as is”. To the extent the law allows, we are not liable for indirect losses or for missed reminders or notifications.</p>',
         'المسؤولية', '<p>يُقدَّم OneSpace «كما هو». وبالقدر الذي يسمح به القانون، لسنا مسؤولين عن الخسائر غير المباشرة أو عن تذكيرات أو إشعارات لم تصل.</p>'),
        ('Privacy', '<p>How we handle data is explained in the <a href="privacy.html">privacy policy</a>.</p>',
         'الخصوصية', '<p>طريقة تعاملنا مع البيانات موضحة في <a href="privacy.html">سياسة الخصوصية</a>.</p>'),
    ]
    return legal_page('terms', 'Terms of use', 'شروط الاستخدام',
                      'The short version: OneSpace is a private space for you and your partner. Use it kindly and lawfully, keep your password safe, and remember that what you mark “Shared” is seen by your partner.',
                      'باختصار: OneSpace مساحة خاصة لك ولشريكك. استخدمه بلطف وبما يوافق القانون، واحفظ كلمة مرورك، وتذكّر أن ما تجعله «مشتركًا» يراه شريكك.', s)


def form(kind, topics=True):
    topic = ''
    if topics:
        topic = f'''<label for="topic">{t('form.topic', 'What is it about?', 'بخصوص ماذا؟')}</label>
    <select id="topic" name="topic">
      <option value="question" data-i18n="form.t1">A question</option>
      <option value="beta" data-i18n="form.t2">I'd like to join the test</option>
      <option value="signin" data-i18n="form.t3">I can't sign in</option>
      <option value="issue" data-i18n="form.t4">Something isn't working</option>
      <option value="idea" data-i18n="form.t5">An idea</option>
    </select>
    <label for="subject">{t('form.subject', 'Subject', 'الموضوع')}</label>
    <input id="subject" name="subject" maxlength="140">'''
    msg_en = 'Your message' if topics else 'Anything we should know (optional)'
    msg_ar = 'رسالتك' if topics else 'أي شيء يجب أن نعرفه (اختياري)'
    return f'''<form class="panel" data-support="{kind}" novalidate>
    <div class="form-row"><div>
      <label for="email">{t('form.email', 'Your email', 'بريدك الإلكتروني')}</label>
      <input id="email" name="email" type="email" required autocomplete="email" maxlength="254">
    </div><div>
      <label for="name">{t('form.name', 'Your name (optional)', 'اسمك (اختياري)')}</label>
      <input id="name" name="name" maxlength="80">
    </div></div>
    {topic}
    <label for="message">{t('form.message.' + kind, msg_en, msg_ar)}</label>
    <textarea id="message" name="message" maxlength="4000" required></textarea>
    <div class="hp" aria-hidden="true"><input name="website" tabindex="-1" autocomplete="off"></div>
    <p style="margin-top:16px"><button class="btn btn-primary" type="submit">{t('form.send.' + kind, 'Send' if topics else 'Request deletion', 'إرسال' if topics else 'طلب الحذف')}</button></p>
    <p class="status" role="status"></p>
    {t('form.privacy', 'We only use your email to reply. See the <a href="privacy.html">privacy policy</a>.', 'نستخدم بريدك للرد فقط. راجع <a href="privacy.html">سياسة الخصوصية</a>.', 'p', 'meta')}
  </form>'''


def support():
    html = head('Support — OneSpace', 'الدعم — OneSpace', 'Help, contact and joining the OneSpace test.', 'support')
    html += f'''<main class="page"><div class="wrap">
  {t('sup.title', 'How can we help?', 'كيف نساعدك؟', 'h1')}
  {t('sup.lead', 'Ask a question, report a problem, share an idea or ask to join the test. You don\'t need to be signed in. We reply by email.', 'اسأل سؤالًا أو أبلغ عن مشكلة أو شارك فكرة أو اطلب الانضمام للتجربة. لا تحتاج إلى تسجيل الدخول. نرد عليك بالبريد.', 'p', 'lead')}
  {form('contact')}
  {t('sup.faq', 'Quick answers', 'إجابات سريعة', 'h2')}
  <details><summary>{t('sup.q1', 'I can\'t sign in', 'لا أستطيع تسجيل الدخول')}</summary>{t('sup.a1', 'Use “Forgot your password?” on the sign-in screen and open the email on the same phone. If you signed up with Google or Apple, use the same button again. Still stuck? Send the form above with “I can\'t sign in”.', 'استخدم «نسيت كلمة المرور؟» في شاشة الدخول وافتح الرسالة على الهاتف نفسه. إذا سجلت بحساب Google أو Apple فاستخدم الزر نفسه. ما زلت عالقًا؟ أرسل النموذج أعلاه واختر «لا أستطيع تسجيل الدخول».', 'p')}</details>
  <details><summary>{t('sup.q2', 'I didn\'t get the confirmation email', 'لم تصلني رسالة التأكيد')}</summary>{t('sup.a2', 'Look in Spam or Promotions, then tap “Resend confirmation” on the sign-in screen.', 'ابحث في البريد غير المرغوب أو العروض، ثم اضغط «إعادة إرسال التأكيد» في شاشة الدخول.', 'p')}</details>
  <details><summary>{t('sup.q3', 'How do I invite my partner?', 'كيف أدعو شريكي؟')}</summary>{t('sup.a3', 'In the app, create your space and tap Invite. Send the link by WhatsApp, SMS or email — or let your partner scan the QR code from your screen.', 'في التطبيق أنشئ مساحتكما واضغط «دعوة». أرسل الرابط عبر واتساب أو رسالة نصية أو البريد — أو دع شريكك يمسح رمز QR من شاشتك.', 'p')}</details>
  <details><summary>{t('sup.q4', 'How do I install the Android test version?', 'كيف أثبّت نسخة أندرويد التجريبية؟')}</summary>{t('sup.a4', 'Open the file we send you and allow “install unknown apps” when your phone asks. For updates, install the new file over the old one — never uninstall first, so nothing is lost.', 'افتح الملف الذي نرسله لك واسمح بـ «تثبيت تطبيقات غير معروفة» عندما يطلب هاتفك ذلك. للتحديث ثبّت الملف الجديد فوق القديم — ولا تحذف التطبيق أولًا حتى لا يضيع شيء.', 'p')}</details>
  <details><summary>{t('sup.q5', 'How do I delete my account?', 'كيف أحذف حسابي؟')}</summary>{t('sup.a5', 'See <a href="delete-account.html">Delete your account</a>.', 'راجع <a href="delete-account.html">حذف حسابك</a>.', 'p')}</details>
</div></main>
<script>
  (function () {{
    var p = new URLSearchParams(location.search).get('topic');
    var s = document.getElementById('topic');
    if (p && s) s.value = p;
  }})();
</script>
'''
    AR.update({'form.t1': 'سؤال', 'form.t2': 'أود الانضمام للتجربة', 'form.t3': 'لا أستطيع تسجيل الدخول',
               'form.t4': 'شيء لا يعمل', 'form.t5': 'فكرة',
               'form.sending': 'جارٍ الإرسال…', 'form.sent': 'شكرًا — وصلتنا رسالتك وسنرد عليك بالبريد.',
               'form.missing': 'يرجى كتابة بريدك ورسالتك.', 'form.email': 'يرجى التحقق من البريد الإلكتروني.',
               'form.busy': 'رسائل كثيرة من هذا البريد. حاول مرة أخرى بعد ساعة.',
               'form.failed': 'تعذّر الإرسال. تحقق من اتصالك وحاول مرة أخرى.'})
    return html + foot()


def delete_account():
    html = head('Delete your account — OneSpace', 'حذف حسابك — OneSpace', 'How to delete your OneSpace account and what happens to your data.', 'delete')
    html += f'''<main class="page"><div class="wrap">
  {t('del.title', 'Delete your OneSpace account', 'حذف حسابك في OneSpace', 'h1')}
  {t('del.lead', 'You can delete your account at any time, from the app or from this page.', 'يمكنك حذف حسابك في أي وقت، من التطبيق أو من هذه الصفحة.', 'p', 'lead')}
  {t('del.h1', 'In the app (fastest)', 'من التطبيق (الأسرع)', 'h2')}
  {t('del.steps', '<ol><li>Open OneSpace and go to <b>Me</b>.</li><li>Tap <b>Your data and account</b>.</li><li>Optional: tap <b>Download my data</b> to keep a copy.</li><li>Tap <b>Delete my account</b> and confirm.</li></ol>', '<ol><li>افتح OneSpace وانتقل إلى <b>أنا</b>.</li><li>اضغط <b>بياناتك وحسابك</b>.</li><li>اختياري: اضغط <b>تنزيل بياناتي</b> للاحتفاظ بنسخة.</li><li>اضغط <b>حذف حسابي</b> وأكّد.</li></ol>', 'div')}
  {t('del.h2', 'What is deleted and what is kept', 'ما الذي يُحذف وما الذي يبقى', 'h2')}
  {t('del.what', '<ul><li>You have <b>7 days</b> to change your mind: sign in again and choose “Keep my account”.</li><li>After 7 days we delete your <b>private items and their files</b>, your <b>devices and notification tokens</b>, your <b>personal settings</b> and your <b>membership of the shared space</b>. Your sign-in is removed (your email is anonymised).</li><li><b>Shared items stay with your partner</b>, shown as written by “Former partner”, because they belong to both of you.</li><li>Messages you sent to support are kept so we can answer you — ask us and we will delete them too. Error reports (no content) are deleted after 60 days.</li></ul>', '<ul><li>لديك <b>7 أيام</b> للتراجع: سجّل الدخول مرة أخرى واختر «الإبقاء على حسابي».</li><li>بعد 7 أيام نحذف <b>عناصرك الخاصة وملفاتها</b> و<b>أجهزتك ورموز الإشعارات</b> و<b>إعداداتك الشخصية</b> و<b>عضويتك في المساحة المشتركة</b>. ويُزال تسجيل دخولك (ويُخفى بريدك).</li><li><b>تبقى العناصر المشتركة مع شريكك</b> باسم «شريك سابق»، لأنها ملك لكما معًا.</li><li>نحتفظ برسائلك إلى الدعم لنرد عليك — اطلب منا ذلك ونحذفها أيضًا. وتُحذف تقارير الأخطاء (بلا محتوى) بعد 60 يومًا.</li></ul>', 'div')}
  {t('del.h3', 'Can\'t open the app?', 'لا تستطيع فتح التطبيق؟', 'h2')}
  {t('del.web', 'Send this form from the email address of your OneSpace account. We will confirm by email before deleting anything, then follow the same steps as above.', 'أرسل هذا النموذج من البريد الإلكتروني لحسابك في OneSpace. سنؤكد معك بالبريد قبل حذف أي شيء، ثم نتبع الخطوات نفسها أعلاه.', 'p')}
  {form('account', topics=False)}
</div></main>
'''
    return html + foot()


def not_found():
    html = head('Page not found — OneSpace', 'الصفحة غير موجودة — OneSpace', 'Page not found.', '404')
    html += f'''<main class="page"><div class="wrap center">
  {t('nf.title', 'This page wandered off', 'هذه الصفحة غير موجودة', 'h1')}
  <p><a class="btn btn-primary" href="./">{t('nf.home', 'Back to OneSpace', 'العودة إلى OneSpace')}</a></p>
</div></main>
'''
    return html + foot()


pages = {'index.html': index(), 'privacy.html': privacy(), 'terms.html': terms(),
         'support.html': support(), 'delete-account.html': delete_account(), '404.html': not_found()}
AR['nav.guides'] = 'الدليل'
for name, html in pages.items():
    open(name, 'w', encoding='utf-8').write(html)
open('assets/ar.js', 'w', encoding='utf-8').write('window.ONESPACE_AR = ' + json.dumps(AR, ensure_ascii=False, indent=0) + ';\n')
open('robots.txt', 'w').write('User-agent: *\nAllow: /\nSitemap: https://boyofkay.github.io/onespace-app/sitemap.xml\n')
base = 'https://boyofkay.github.io/onespace-app/'
open('sitemap.xml', 'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + ''.join(f'  <url><loc>{base}{"" if n == "index.html" else n}</loc></url>\n' for n in list(pages) + ['feature-tour.html', 'getting-started.html', 'couples-app.html', 'long-distance-relationship-app.html', 'shared-calendar-for-couples.html'] if n != '404.html') + '</urlset>\n')
print('built', ', '.join(pages), '·', len(AR), 'Arabic strings')
