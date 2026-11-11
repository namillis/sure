import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/connections_screen.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';

import '../support/connection_fixtures.dart';
import '../support/l10n_harness.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);

  Future<void> pump(WidgetTester tester, MockClient client) => pumpLocalized(
        tester,
        ConnectionsScreen(
          service: ProviderConnectionsService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          now: () => now,
        ),
      );

  testWidgets('shows status, last sync and errors; only broken rows get Fix',
      (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          jsonEncode({
            'data': [
              connectionJson(id: 'ok', institution: 'Healthy Bank'),
              connectionJson(
                id: 'broken',
                provider: 'simplefin',
                institution: 'Broken Bank',
                requiresUpdate: true,
                lastSyncedAt: '2026-11-09T12:00:00Z',
                latest: {
                  'status': 'failed',
                  'error': {'present': true, 'message': 'Sync failed'},
                },
                unlinked: 2,
              ),
            ],
          }),
          200)),
    );

    expect(find.text('Manage connections on the web'), findsOneWidget);
    expect(find.text('Healthy Bank'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Synced 2h ago'), findsOneWidget);
    expect(find.text('Enable banking · 3 accounts'), findsOneWidget);

    expect(find.text('Broken Bank'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Synced 2d ago'), findsOneWidget);
    expect(find.text('The bank needs you to sign in again.'), findsOneWidget);
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.text('2 accounts need setup'), findsOneWidget);
    expect(find.text('Fix on the web'), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await pump(tester,
        MockClient((_) async => http.Response('{"data":[]}', 200)));
    expect(find.text('No connections yet'), findsOneWidget);
    expect(find.text('Manage connections on the web'), findsOneWidget);
  });

  testWidgets('error state retries', (tester) async {
    var calls = 0;
    await pump(
      tester,
      MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{}', 500)
            : http.Response(jsonEncode({'data': [connectionJson()]}), 200);
      }),
    );
    expect(find.text("Couldn't load connections."), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Example Bank'), findsOneWidget);
  });

  test('lastSyncedLabel', () {
    final l = lookupAppLocalizations(const Locale('en'));
    String label(DateTime? at) =>
        ConnectionsScreen.lastSyncedLabel(l, at, now: now);
    expect(label(null), l.accountActionsNeverSynced);
    expect(label(now.subtract(const Duration(seconds: 20))),
        l.accountActionsSyncedJustNow);
    expect(label(now.subtract(const Duration(minutes: 5))), 'Synced 5m ago');
    expect(label(now.subtract(const Duration(hours: 3))), 'Synced 3h ago');
    expect(label(now.subtract(const Duration(days: 4))), 'Synced 4d ago');
  });
}
