/// Device-only checklist readout. The source is the already RLS-filtered,
/// visible active checklist plus *this user's* current-cycle checkmarks.
class ChecklistReadoutRules {
  const ChecklistReadoutRules._();

  static String clean(Object? raw) {
    final value=(raw??'').toString().replaceAll(
      RegExp(r'[\\x00-\\x1f\\x7f]+'), ' ').replaceAll(RegExp(r'\\s+'),' ').trim();
    return value.length>240?value.substring(0,240):value;
  }

  static List<String> lines(
    Iterable<Map<String,dynamic>> items,
    Map<String,Map<String,dynamic>> ownChecks, {
    bool remainingOnly=false,
  }) {
    final output=<String>[];
    for(final item in items){
      if(item['archived_at']!=null || item['id'] is! String)continue;
      final title=clean(item['title']);
      if(title.isEmpty)continue;
      if(remainingOnly&&ownChecks[item['id']]?['completed']==true)continue;
      output.add(title);
      if(output.length==200)break;
    }
    return output;
  }

  static String script({
    required String listTitle,
    required List<String> lines,
    required bool remainingOnly,
  }) {
    final heading=clean(listTitle).isEmpty?'Your checklist':clean(listTitle);
    if(lines.isEmpty)return remainingOnly?
      'All done. There are no unchecked items in $heading.':
      '$heading has no active items.';
    return [
      '$heading. '+(remainingOnly?'Items still to do.':'Checklist readout.'),
      for(var i=0;i<lines.length;i++)'Item ${i+1}. ${lines[i]}.',
      'End of checklist.',
    ].join(' ');
  }
}
