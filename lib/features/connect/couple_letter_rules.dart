/// Pure presentation rules for couple correspondence.
/// Authorization is enforced by RLS, not by these UI helpers.
class CoupleLetterRules {
  const CoupleLetterRules._();

  static String? validate(String title,String body,{required bool sending}) {
    final name=title.trim();
    if(name.isEmpty || name.length>160) return 'Use a title of 1–160 characters.';
    if(body.length>16000)return 'Your message must be under 16,000 characters.';
    if(sending && body.trim().isEmpty)return 'Write a message before sending.';
    return null;
  }

  static List<Map<String,dynamic>> filter(
    List<Map<String,dynamic>> raw,String view,String userId,
  ) {
    return raw.where((letter) {
      final status=letter['status']?.toString();
      final mine=letter['author_id']==userId;
      if(view=='drafts')return mine && status=='draft';
      if(view=='sent')return mine && status=='sent';
      return !mine && status=='sent';
    }).toList()..sort((a,b){
      final left=(a['sent_at']??a['updated_at']??'').toString();
      final right=(b['sent_at']??b['updated_at']??'').toString();
      return right.compareTo(left);
    });
  }

  static String snippet(String text,{int max=130}) {
    final cleaned=text.replaceAll(RegExp(r'\s+'),' ').trim();
    if(cleaned.runes.length<=max)return cleaned;
    return '${String.fromCharCodes(cleaned.runes.take(max-1))}…';
  }

  static String replyTitle(String title){
    final s=title.trim();
    return s.toLowerCase().startsWith('re:')?s:'Re: $s';
  }
}
