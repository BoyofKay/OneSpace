import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/partner_time_zones.dart';

void main() {
  test('IANA zones validate explicitly without guessing a location', () {
    expect(PartnerTimeZones.valid('Asia/Riyadh'), isTrue);
    expect(PartnerTimeZones.valid('America/New_York'), isTrue);
    expect(PartnerTimeZones.valid('Africa/Cairo'), isTrue);
    expect(PartnerTimeZones.valid(null), isFalse);
    expect(PartnerTimeZones.valid('NYC'), isFalse);
    expect(PartnerTimeZones.valid('../invalid'), isFalse);
  });

  test('Riyadh and New York reflect US daylight-saving changes', () {
    final winter = DateTime.utc(2026, 1, 15, 12);
    final summer = DateTime.utc(2026, 7, 15, 12);
    expect(PartnerTimeZones.differenceHoursMinutes(
      'Asia/Riyadh', 'America/New_York', winter), -480);
    expect(PartnerTimeZones.differenceHoursMinutes(
      'Asia/Riyadh', 'America/New_York', summer), -420);
    expect(PartnerTimeZones.inZone('America/New_York',winter)?.hour,7);
    expect(PartnerTimeZones.inZone('America/New_York',summer)?.hour,8);
  });

  test('calendar dates differ safely around midnight', () {
    final utc = DateTime.utc(2026,11,13,23,30);
    final riyadh = PartnerTimeZones.inZone('Asia/Riyadh', utc)!;
    final newYork = PartnerTimeZones.inZone('America/New_York',utc)!;
    expect(PartnerTimeZones.dateLabel(riyadh),'Sat, Nov 14');
    expect(PartnerTimeZones.dateLabel(newYork),'Fri, Nov 13');
    expect(PartnerTimeZones.timeLabel(riyadh),'2:30 AM');
    expect(PartnerTimeZones.timeLabel(newYork),'6:30 PM');
  });

  test('time difference labels show both directions and same-zone case', () {
    expect(PartnerTimeZones.differenceLabel(0),'Same local time');
    expect(PartnerTimeZones.differenceLabel(180),
      'Partner is 3 hours ahead');
    expect(PartnerTimeZones.differenceLabel(-450),
      'Partner is 7 hours 30 min behind');
    expect(PartnerTimeZones.differenceHoursMinutes(
      'America/New_York','America/New_York', DateTime.utc(2026,5,1)),
      0);
  });

  test('non configured zone does not invent clock information', () {
    expect(PartnerTimeZones.inZone(null,DateTime.utc(2026)),isNull);
    expect(PartnerTimeZones.differenceHoursMinutes(
      null,'Asia/Riyadh',DateTime.utc(2026)),isNull);
    expect(PartnerTimeZones.offsetLabel(const Duration(hours:-5)),
      'UTC-05:00');
    expect(PartnerTimeZones.offsetLabel(
      const Duration(hours:5,minutes:30)),'UTC+05:30');
  });
}
