import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../world/trips_screen.dart';
import 'coordinate_screen.dart';

/// R61: the Coordinate tab holds everything we plan together:
/// Activities and Trips.
class CoordinateHub extends StatefulWidget {
  const CoordinateHub({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<CoordinateHub> createState() => CoordinateHubState();
}

class CoordinateHubState extends State<CoordinateHub> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  void show(int index) => tabs.animateTo(index);

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    TabBar(controller: tabs, tabs: [
      Tab(icon: const Icon(Icons.hub_outlined), text: tt('Activities')),
      Tab(icon: const Icon(Icons.flight_takeoff_outlined), text: tt('Trips')),
    ]),
    Expanded(child: TabBarView(controller: tabs, children: const [
      CoordinateScreen(),
      TripsScreen(embedded: true),
    ])),
  ]);
}
