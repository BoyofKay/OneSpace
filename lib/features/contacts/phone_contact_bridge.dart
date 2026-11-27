import 'package:flutter/services.dart';
import '../coordinate/activity_contact.dart';

/// Explicit, user-initiated Android Contacts operations. Phone data is never
/// imported in bulk or silently synchronized to the shared space.
class PhoneContactBridge {
  const PhoneContactBridge._();
  static const MethodChannel _channel=MethodChannel('onespace/device_contacts');

  static ActivityContact fromMap(Map<dynamic,dynamic> fields) =>
    ActivityContact(
      person:(fields['person']??'').toString(),
      phone:(fields['phone']??'').toString(),
      email:(fields['email']??'').toString(),
      address:(fields['address']??'').toString(),
      company:(fields['company']??'').toString(),
      role:(fields['role']??'').toString(),
      website:(fields['website']??'').toString(),
    );

  static Future<ActivityContact?> pickFromPhone()async{
    final fields=await _channel.invokeMapMethod<String,dynamic>('pickContact');
    if(fields==null)return null;
    return fromMap(fields);
  }

  /// The native Contacts app is opened with a prefilled, editable new-contact
  /// draft. User confirmation happens there; OneSpace cannot silently save.
  static Future<void> saveToPhone(ActivityContact contact)async{
    await _channel.invokeMethod<bool>('saveToPhone',{
      'person':contact.person,'phone':contact.phone,'email':contact.email,
      'address':contact.address,'company':contact.company,'role':contact.role,
      'website':contact.website,
    });
  }

  static Future<ActivityContact?> takeSharedVcard()async{
    final fields=await _channel.invokeMapMethod<String,dynamic>('takePendingVcard');
    return fields==null?null:fromMap(fields);
  }
}
