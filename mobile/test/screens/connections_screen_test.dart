import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/connections_screen.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

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

  testWidgets('connections are hairline panels, back link says Settings',
      (tester) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ConnectionsScreen(
              service: ProviderConnectionsService(
                  client: MockClient((_) async => http.Response(
                      jsonEncode({'data': [connectionJson()]}), 200))),
              accessTokenLoader: () async => 'token',
              onUnauthorized: () async {},
              now: () => now,
            ),
          )),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SureBackButton, 'Settings'), findsOneWidget);
    expect(find.byType(SurePanel), findsNWidgets(2));
    expect(find.byType(Card), findsNothing);
    expect(find.text('Fix on the web'), findsNothing);
    expect(find.bySemanticsLabel('Sync now'), findsOneWidget);
  });

  testWidgets('empty state disables Sync now', (tester) async {
    await pump(tester,
        MockClient((_) async => http.Response('{"data":[]}', 200)));
    final sync = tester.widget<SureNavIconButton>(find.byType(SureNavIconButton));
    expect(sync.onPressed, isNull);
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

  group('connections.manage', () {
    Future<void> pumpManaged(WidgetTester tester, MockClient client,
            {Set<String> features = const {
              ServerFeaturesProvider.connectionsManage
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

    Future<void> swipe(WidgetTester tester, String name) async {
      await tester.drag(find.text(name), const Offset(-300, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('without the feature rows have no swipe actions',
        (tester) async {
      await pumpManaged(
        tester,
        MockClient((_) async => http.Response(list([connectionJson()]), 200)),
        features: const {},
      );
      expect(find.byType(SureSwipeActions), findsNothing);
      await swipe(tester, 'Example Bank');
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('Sync now posts with the provider and shows Syncing',
        (tester) async {
      final writes = <http.Request>[];
      await pumpManaged(
        tester,
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
                list([connectionJson(provider: 'simplefin')]), 200);
          }
          writes.add(request);
          return http.Response(
              jsonEncode(connectionJson(provider: 'simplefin', syncing: true)),
              202);
        }),
      );
      expect(find.text('Connected'), findsOneWidget);

      await swipe(tester, 'Example Bank');
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();

      expect(writes.single.method, 'POST');
      expect(writes.single.url.path, '/api/v1/provider_connections/c1/sync');
      expect(writes.single.url.queryParameters['provider'], 'simplefin');
      expect(find.text('Syncing'), findsOneWidget);
    });

    testWidgets('Disconnect confirms, deletes with provider, shows scheduled',
        (tester) async {
      final writes = <http.Request>[];
      await pumpManaged(
        tester,
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(list([connectionJson(provider: 'plaid')]), 200);
          }
          writes.add(request);
          return http.Response(
              jsonEncode(connectionJson(
                  provider: 'plaid', scheduledForDeletion: true)),
              202);
        }),
      );

      await swipe(tester, 'Example Bank');
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect Example Bank?'), findsOneWidget);
      expect(
          find.text(
              'Its accounts stop syncing. You can connect it again on the web.'),
          findsOneWidget);

      // Cancel sends nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);

      await swipe(tester, 'Example Bank');
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Disconnect')));
      await tester.pumpAndSettle();

      expect(writes.single.method, 'DELETE');
      expect(writes.single.url.path, '/api/v1/provider_connections/c1');
      expect(writes.single.url.queryParameters['provider'], 'plaid');
      expect(find.text('Scheduled for deletion'), findsOneWidget);
      // A row being deleted offers no more actions.
      expect(find.byType(SureSwipeActions), findsNothing);
    });

    for (final (status, code, message) in [
      (
        422,
        'manual_sync_required',
        'This connection needs a security code to sync. Sync it on the web.'
      ),
      (
        422,
        'reconnect_required',
        'This connection needs a new login. Log in again on the web.'
      ),
      (
        403,
        'forbidden',
        'Only a family admin, or for Plaid the person who connected it, '
            'can manage this connection.'
      ),
      (
        403,
        'insufficient_scope',
        'This sign-in can only read data. Manage the connection on the web.'
      ),
    ]) {
      testWidgets('$status $code shows a message and Fix on the web',
          (tester) async {
        await pumpManaged(
          tester,
          MockClient((request) async => request.method == 'GET'
              ? http.Response(list([connectionJson()]), 200)
              : http.Response(
                  jsonEncode({'error': code, 'message': 'server text'}),
                  status)),
        );

        await swipe(tester, 'Example Bank');
        await tester.tap(find.text('Sync now'));
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Fix on the web'),
            findsOneWidget);
        expect(find.text('Connected'), findsOneWidget);
      });
    }

    testWidgets('fits 320 px in Swedish with actions open', (tester) async {
      tester.view.physicalSize = const Size(960, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<ServerFeaturesProvider>(
          create: (_) => ServerFeaturesProvider()
            ..debugSet({ServerFeaturesProvider.connectionsManage}),
          child: MaterialApp(
            locale: const Locale('sv'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ConnectionsScreen(
              service: ProviderConnectionsService(
                  client: MockClient((_) async => http.Response(
                      list([connectionJson(scheduledForDeletion: false)]),
                      200))),
              accessTokenLoader: () async => 'token',
              onUnauthorized: () async {},
              now: () => now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await swipe(tester, 'Example Bank');
      expect(find.text('Koppla från'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
