import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/connections_screen.dart';
import 'package:sure_mobile/screens/sync_schedule_sheet.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/connection_fixtures.dart';
import '../support/l10n_harness.dart';

void main() {
  final now = DateTime(2026, 11, 11, 12);

  Future<void> pump(WidgetTester tester, MockClient client,
          {Set<String> features = const {
            ServerFeaturesProvider.settingsSyncSchedule
          }}) =>
      pumpLocalized(
        tester,
        ChangeNotifierProvider<ServerFeaturesProvider>(
          create: (_) => ServerFeaturesProvider()..debugSet(features),
          child: ConnectionsScreen(
            service: ProviderConnectionsService(client: client),
            accessTokenLoader: () async => 'token',
            onUnauthorized: () async {},
            now: () => now,
          ),
        ),
      );

  String list(List<Map<String, dynamic>> rows) => jsonEncode({'data': rows});

  String schedule(int? interval, {String? next}) => jsonEncode({
        'data': {
          'provider_connection_id': 'c1',
          'provider': 'simplefin',
          'interval_minutes': interval,
          'next_run_at': next,
          'allowed_intervals': [15, 30, 60, 120, 240, 360, 720],
        },
      });

  Future<void> swipe(WidgetTester tester) async {
    await tester.drag(find.text('Example Bank'), const Offset(-300, 0));
    await tester.pumpAndSettle();
  }

  test('interval labels', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(syncIntervalLabel(l, 15), 'Every 15 min');
    expect(syncIntervalLabel(l, 60), 'Every hour');
    expect(syncIntervalLabel(l, 720), 'Every 12 hours');
    expect(syncIntervalLabel(l, 90), 'Every 90 min');
  });

  testWidgets('without the feature there is no Schedule action',
      (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(list([connectionJson()]), 200)),
      features: const {ServerFeaturesProvider.connectionsManage},
    );
    await swipe(tester);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Schedule'), findsNothing);
  });

  testWidgets('FinanceKit connections get no Schedule action', (tester) async {
    await pump(
      tester,
      MockClient((_) async =>
          http.Response(list([connectionJson(provider: 'financekit')]), 200)),
    );
    expect(find.byType(SureSwipeActions), findsNothing);
  });

  testWidgets('Schedule lists the intervals and saves a tap', (tester) async {
    final requests = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/sync_schedule')) {
          requests.add(request);
          return request.method == 'GET'
              ? http.Response(schedule(null), 200)
              : http.Response(
                  schedule(60, next: '2026-11-11T13:00:00'), 200);
        }
        return http.Response(
            list([connectionJson(provider: 'simplefin')]), 200);
      }),
    );

    await swipe(tester);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path,
        '/api/v1/provider_connections/c1/sync_schedule');
    expect(requests.single.url.queryParameters['provider'], 'simplefin');
    expect(find.text('Sync schedule'), findsOneWidget);
    for (final label in [
      'Default',
      'Every 15 min',
      'Every 30 min',
      'Every hour',
      'Every 2 hours',
      'Every 12 hours',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // The check is on Default; no next sync without a schedule.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('syncScheduleOption-default')),
            matching: find.byType(SureIcon)),
        findsOneWidget);
    expect(find.textContaining('Next sync'), findsNothing);

    await tester.tap(find.text('Every hour'));
    await tester.pumpAndSettle();

    expect(requests.last.method, 'PATCH');
    expect(jsonDecode(requests.last.body), {
      'sync_schedule': {'interval_minutes': 60},
    });
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('syncScheduleOption-60')),
            matching: find.byType(SureIcon)),
        findsOneWidget);
    // intl puts a narrow no-break space before PM.
    expect(find.textContaining(RegExp(r'^Next sync 1:00\sPM$')),
        findsOneWidget);

    // Back to Default sends null.
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    expect(jsonDecode(requests.last.body), {
      'sync_schedule': {'interval_minutes': null},
    });
  });

  testWidgets('403 shows the server message', (tester) async {
    await pump(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/sync_schedule')) {
          return http.Response(
              jsonEncode({
                'error': 'forbidden',
                'message': "You cannot manage this connection's sync schedule",
              }),
              403);
        }
        return http.Response(list([connectionJson()]), 200);
      }),
    );
    await swipe(tester);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text("You cannot manage this connection's sync schedule"),
        findsOneWidget);
  });

  testWidgets('sync_schedule_not_supported hides the action afterwards',
      (tester) async {
    await pump(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/sync_schedule')) {
          return http.Response(
              jsonEncode({
                'error': 'sync_schedule_not_supported',
                'message': 'This connection does not support a sync schedule',
              }),
              422);
        }
        return http.Response(list([connectionJson()]), 200);
      }),
    );
    await swipe(tester);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('This connection does not support a sync schedule'),
        findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(SureSwipeActions), findsNothing);
  });
}
