import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/places/places_map_screen.dart';

void main() {
  testWidgets('map pin uses place category icon and indicates partner visibility', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PlaceMapPin(place: const {
        'name': 'Our coffee spot', 'category': 'cafe',
        'status': 'visited', 'visibility': 'shared',
      }, meInitial: 'A', partnerInitial: 'K'))));
    expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(PlaceMapPin.visitedColor, isNot(PlaceMapPin.wishlistColor));
  });

  testWidgets('private map pin does not display the other partner badge', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PlaceMapPin(place: const {
        'category': 'restaurant', 'status': 'wishlist',
        'visibility': 'private',
      }, meInitial: 'A', partnerInitial: 'K'))));
    expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('K'), findsNothing);
  });
}
