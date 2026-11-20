import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/space_lifecycle_progress_card.dart';

Map<String, dynamic> makeStatus({
  String action = 'owner_removes_partner',
  bool mine = true,
  int verified = 0,
}) => {
  'archives_expected': 4,
  'archives_verified': verified,
  'safe_to_finalize': false,
  'active_job': {
    'id': '00000000-0000-4000-8000-000000000001',
    'action': action,
    'status': 'awaiting_verified_export',
    'requested_by_me': mine,
    'requested_at': '2026-11-20T01:44:23Z',
  },
};

Future<void> show(WidgetTester tester, Map<String, dynamic> status,
  {VoidCallback? refresh, void Function(String)? cancel}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(
      child: SpaceLifecycleProgressCard(
        lifecycle: status, refreshing: false,
        onRefresh: refresh ?? () {},
        onCancel: cancel ?? (_) {},
      ),
    )),
  ));
}

void main() {
  test('action labels distinguish initiator and affected partner', () {
    expect(SpaceLifecycleProgressCard.actionLabel('owner_removes_partner', true),
      contains('You requested'));
    expect(SpaceLifecycleProgressCard.actionLabel('owner_removes_partner', false),
      contains('requested to remove you'));
    expect(SpaceLifecycleProgressCard.actionLabel('partner_leaves', false),
      contains('requested to leave'));
  });

  testWidgets('owner removal is honestly blocked, count is verified archives',
      (tester) async {
    var refreshed = false;
    String? cancelledId;
    await show(tester, makeStatus(),
      refresh: () => refreshed = true,
      cancel: (id) => cancelledId = id);
    expect(find.textContaining('blocked before separation'), findsOneWidget);
    expect(find.textContaining('You requested to remove your partner'),
      findsOneWidget);
    expect(find.textContaining('0 / 4'), findsOneWidget);
    expect(find.textContaining('no running background separation job',
      findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('lifecycleCancelRequest')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lifecycleRefreshStatus')));
    await tester.tap(find.byKey(const Key('lifecycleRefreshStatus')));
    expect(refreshed, isTrue);
    await tester.ensureVisible(find.byKey(const Key('lifecycleCancelRequest')));
    await tester.tap(find.byKey(const Key('lifecycleCancelRequest')));
    expect(cancelledId, '00000000-0000-4000-8000-000000000001');
  });

  testWidgets('affected partner sees request but cannot cancel initiator job',
      (tester) async {
    await show(tester, makeStatus(mine: false));
    expect(find.textContaining('requested to remove you'), findsOneWidget);
    expect(find.byKey(const Key('lifecycleCancelRequest')), findsNothing);
    expect(find.byKey(const Key('lifecycleRefreshStatus')), findsOneWidget);
  });

  testWidgets('leaving partner sees correct action and never fake percentage',
      (tester) async {
    await show(tester, makeStatus(action: 'partner_leaves', verified: 1));
    expect(find.textContaining('You requested to leave this space'),
      findsOneWidget);
    expect(find.textContaining('1 / 4'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('no active request does not render a progress card',
      (tester) async {
    await show(tester, {'active_job': null});
    expect(find.byKey(const Key('lifecycleRequestProgressCard')), findsNothing);
  });
}
