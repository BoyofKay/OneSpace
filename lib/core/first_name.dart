/// Greeting-only name formatting. Never changes profile or legal names.
class FirstName {
 const FirstName._();
 static String of(Object? name,{String fallback='there'}){
  final input=(name??'').toString().trim();
  if(input.isEmpty)return fallback;
  final words=input.split(RegExp(r'\\s+')).where((x)=>x.isNotEmpty);
  return words.isEmpty?fallback:words.first;
 }
}
