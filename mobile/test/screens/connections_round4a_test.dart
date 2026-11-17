import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/connection_setup_sheets.dart';
import 'package:sure_mobile/screens/connections_screen.dart';
import 'package:sure_mobile/screens/settings_links.dart';
import 'package:sure_mobile/services/connection_setup_service.dart';
import 'package:sure_mobile/services/log_service.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';
import 'package:sure_mobile/services/web_auth_session.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixtures.dart';

/// Records the URLs it was asked to open and answers with [status].
class FakeWebAuth extends WebAuthSession {
  FakeWebAuth([this.status = WebHandoffStatus.ok]);

  WebHandoffStatus status;
  final opened = <Uri>[];

  @override
  Future<WebHandoffStatus> open(Uri url) async {
    opened.add(url);
    return status;
  }
}

typedef Handler = http.Response Function(http.Request request);

const handoffUrl =
    'https://money.example.test/web_handoffs/redeem?token=SECRET123';

const allFeatures = {
  ServerFeaturesProvider.connectionsAvailable,
  ServerFeaturesProvider.connectionsWebHandoff,
  ServerFeaturesProvider.connectionsTokenCreate,
};

Map<String, dynamic> available(String provider, String key, String name,
        String path, String kind) =>
    {
      'provider': provider,
      'key': key,
      'name': name,
      'connect_path': path,
      'kind': kind,
    };

final defaultAvailable = [
  available('lunchflow', 'lunchflow', 'Lunch Flow',
      '/settings/providers/lunchflow/connect_form', 'token'),
  available('plaid', 'plaid_eu', 'Plaid', '/plaid_items/new?region=eu', 'web'),
  available('plaid', 'plaid_us', 'Plaid', '/plaid_items/new?region=us', 'web'),
  available('simplefin', 'simplefin', 'SimpleFIN',
      '/settings/providers/simplefin/connect_form', 'token'),
  available('wise', 'wise', 'Wise', '/settings/providers/wise/connect_form',
      'web'),
];

Map<String, dynamic> pendingAccount(String id, String name,
        {String? type = 'Depository', String? subtype = 'checking'}) =>
    {
      'id': id,
      'name': name,
      'institution': 'Credit Union',
      'balance': r'$1,234.56',
      'balance_cents': 123456,
      'currency': 'USD',
      'suggested_accountable_type': type,
      'suggested_subtype': subtype,
      'allowed_types': [
        {
          'accountable_type': 'Depository',
          'label': 'Checking or Savings Account',
          'subtypes': [
            {'value': 'checking', 'label': 'Checking'},
            {'value': 'savings', 'label': 'Savings'},
          ],
        },
        {
          'accountable_type': 'CreditCard',
          'label': 'Credit Card',
          'subtypes': <Map<String, dynamic>>[],
        },
      ],
    };

Map<String, dynamic> withReconnect(Map<String, dynamic> row, String? path) =>
    {...row, 'reconnect_path': path};

void main() {
  final now = DateTime(2026, 11, 11, 12);
  late List<http.Request> requests;
  late Map<String, Handler> routes;
  late FakeWebAuth webAuth;
  late List<Map<String, dynamic>> rows;

  setUp(() {
    requests = [];
    webAuth = FakeWebAuth();
    rows = [connectionJson()];
    routes = {
      'GET /api/v1/provider_connections': (_) =>
          http.Response(jsonEncode({'data': rows}), 200),
      'GET /api/v1/provider_connections/available': (_) =>
          http.Response(jsonEncode({'data': defaultAvailable}), 200),
      'POST /api/v1/web_handoffs': (_) => http.Response(
          jsonEncode({'url': handoffUrl, 'expires_at': '2026-11-11T12:01:00Z'}),
          201),
    };
  });

  int listCalls() => requests
      .where((r) =>
          r.method == 'GET' && r.url.path == '/api/v1/provider_connections')
      .length;

  List<http.Request> calls(String method, String path) => requests
      .where((r) => r.method == method && r.url.path == path)
      .toList();

  Future<void> pump(
    WidgetTester tester, {
    Set<String> features = allFeatures,
    Brightness brightness = Brightness.light,
    double width = 390,
    double height = 844,
    bool privacyHidden = false,
    List<Account>? accounts,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      requests.add(request);
      final handler = routes['${request.method} ${request.url.path}'];
      return handler?.call(request) ??
          http.Response(jsonEncode({'error': 'not_found'}), 404);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: privacyHidden)),
          ChangeNotifierProvider<ServerFeaturesProvider>(
              create: (_) => ServerFeaturesProvider()..debugSet(features)),
          if (accounts != null)
            ChangeNotifierProvider<AccountsProvider>(
                create: (_) => FakeAccountsProvider(accounts: accounts)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ConnectionsScreen(
            service: ProviderConnectionsService(client: client),
            setupService: ConnectionSetupService(client: client),
            webAuth: webAuth,
            accessTokenLoader: () async => 'token',
            onUnauthorized: () async {},
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addButton() => find.bySemanticsLabel('Add connection');

  Future<void> openAdd(WidgetTester tester) async {
    await tester.tap(addButton());
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('s4cAvailable-$key')));
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester, String key) => tester.widget<TextField>(
      find.descendant(
          of: find.byKey(ValueKey('s4cField-$key')),
          matching: find.byType(TextField)));

  group('without the round 4a features', () {
    testWidgets('the screen stays as it was', (tester) async {
      rows = [
        withReconnect(
            connectionJson(provider: 'plaid', requiresUpdate: true),
            '/plaid_items/c1/edit'),
        connectionJson(id: 'c2', provider: 'simplefin', pendingSetup: true,
            institution: 'Pending Bank', unlinked: 2),
      ];
      await pump(tester, features: const {
        ServerFeaturesProvider.connectionsManage,
      });

      expect(addButton(), findsNothing);
      expect(find.byKey(const ValueKey('s4cReconnectBanner')), findsNothing);
      expect(find.text('Finish setup'), findsNothing);
      expect(find.text('Manage connections on the web'), findsOneWidget);
      expect(find.text('Fix on the web'), findsNWidgets(2));

      await tester.drag(find.text('Example Bank'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect'), findsNothing);
      expect(find.text('Sync now'), findsWidgets);
      expect(calls('GET', '/api/v1/provider_connections/available'), isEmpty);
    });

    testWidgets('a token provider without token_create uses the handoff',
        (tester) async {
      await pump(tester, features: const {
        ServerFeaturesProvider.connectionsAvailable,
        ServerFeaturesProvider.connectionsWebHandoff,
      });
      await openAdd(tester);
      await pick(tester, 'simplefin');

      expect(find.text('Setup token'), findsNothing);
      final post = calls('POST', '/api/v1/web_handoffs').single;
      expect(jsonDecode(post.body), {
        'web_handoff': {'path': '/settings/providers/simplefin/connect_form'},
      });
      expect(webAuth.opened.single.toString(), handoffUrl);
    });
  });

  group('Add connection sheet', () {
    testWidgets('lists providers with subtitles and trailing marks',
        (tester) async {
      await pump(tester);
      await openAdd(tester);

      expect(find.text('Add connection'), findsWidgets);
      expect(find.text('Most US banks'), findsOneWidget);
      expect(find.text('Most EU banks'), findsOneWidget);
      expect(find.text('Paste a setup token'), findsOneWidget);
      expect(find.text('API key'), findsOneWidget);
      expect(find.text('Wise'), findsOneWidget);

      bool hasWebMark(String key) => tester.any(find.descendant(
          of: find.byKey(ValueKey('s4cAvailable-$key')),
          matching: find.byType(SettingsWebMark)));
      expect(hasWebMark('plaid_us'), isTrue);
      expect(hasWebMark('wise'), isTrue);
      expect(hasWebMark('simplefin'), isFalse);
      expect(hasWebMark('lunchflow'), isFalse);
    });

    testWidgets('an empty list asks for an admin', (tester) async {
      routes['GET /api/v1/provider_connections/available'] =
          (_) => http.Response('{"data":[]}', 200);
      await pump(tester);
      await openAdd(tester);
      expect(find.text('Ask an admin to add connections'), findsOneWidget);
    });
  });

  group('web handoff', () {
    testWidgets('ok refreshes and says Connected · syncing; no URL leaks',
        (tester) async {
      LogService.instance.clear();
      await pump(tester);
      final before = listCalls();
      await openAdd(tester);
      await pick(tester, 'plaid_us');

      final post = calls('POST', '/api/v1/web_handoffs').single;
      expect(jsonDecode(post.body), {
        'web_handoff': {'path': '/plaid_items/new?region=us'},
      });
      expect(webAuth.opened.single.toString(), handoffUrl);
      expect(listCalls(), before + 1);
      expect(find.text('Connected · syncing'), findsOneWidget);
      expect(find.textContaining('SECRET123'), findsNothing);
      expect(
          LogService.instance.logs.any((e) => e.message.contains('SECRET123')),
          isFalse);
    });

    testWidgets('cancelled does nothing', (tester) async {
      webAuth.status = WebHandoffStatus.cancelled;
      await pump(tester);
      final before = listCalls();
      await openAdd(tester);
      await pick(tester, 'wise');

      expect(webAuth.opened, hasLength(1));
      expect(listCalls(), before);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('closing the sheet only refreshes quietly', (tester) async {
      webAuth.status = WebHandoffStatus.closed;
      await pump(tester);
      final before = listCalls();
      await openAdd(tester);
      await pick(tester, 'wise');

      expect(listCalls(), before + 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('error offers Open on web', (tester) async {
      webAuth.status = WebHandoffStatus.error;
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'wise');

      expect(
          find.text("Couldn't finish connecting. Try again, or open "
              'Connections on the web.'),
          findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Open on web'), findsOneWidget);
    });

    for (final (status, code, message, webAction) in [
      (429, 'rate_limit_exceeded', 'Too many attempts. Try again in a minute.',
          false),
      (422, 'path_not_allowed',
          "Couldn't finish connecting. Try again, or open Connections on the web.",
          true),
      (403, 'forbidden', "Guests can't manage connections", false),
      (403, 'insufficient_scope', 'This key can only read', false),
    ]) {
      testWidgets('handoff $status $code', (tester) async {
        routes['POST /api/v1/web_handoffs'] = (_) => http.Response(
            jsonEncode({'error': code, 'message': message}), status);
        await pump(tester);
        await openAdd(tester);
        await pick(tester, 'plaid_eu');

        expect(webAuth.opened, isEmpty);
        expect(find.text(message), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Open on web'),
            webAction ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('reconnect banner and swipe use reconnect_path',
        (tester) async {
      rows = [
        connectionJson(id: 'ok', institution: 'Healthy Bank'),
        withReconnect(
            connectionJson(
                id: 'p1', provider: 'plaid', requiresUpdate: true,
                institution: 'Capital One'),
            '/plaid_items/p1/edit'),
        withReconnect(
            connectionJson(
                id: 's1', provider: 'simplefin', requiresUpdate: true,
                institution: 'Second Bank'),
            '/simplefin_items/s1/edit'),
      ];
      await pump(tester);

      // The banner names the first connection that needs a sign-in.
      expect(find.text('Capital One needs you to sign in again'),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('s4cReconnectBanner')),
          matching: find.text('Reconnect')));
      await tester.pumpAndSettle();
      expect(jsonDecode(calls('POST', '/api/v1/web_handoffs').last.body), {
        'web_handoff': {'path': '/plaid_items/p1/edit'},
      });

      await tester.drag(find.text('Second Bank'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text('Second Bank'),
              matching: find.byType(SureSwipeActions)),
          matching: find.text('Reconnect')));
      await tester.pumpAndSettle();
      expect(jsonDecode(calls('POST', '/api/v1/web_handoffs').last.body), {
        'web_handoff': {'path': '/simplefin_items/s1/edit'},
      });
      expect(webAuth.opened, hasLength(2));
    });
  });

  group('token providers', () {
    Map<String, dynamic> created({
      String provider = 'simplefin',
      bool setupRequired = false,
      bool awaiting = false,
    }) =>
        {
          ...withReconnect(
              connectionJson(id: 'new1', provider: provider), null),
          'setup_required': setupRequired,
          'awaiting_accounts': awaiting,
          'pending_accounts': <dynamic>[],
        };

    testWidgets('SimpleFIN form: obscured token, helper, no date',
        (tester) async {
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'simplefin');

      final token = field(tester, 'setup_token');
      expect(token.obscureText, isTrue);
      expect(token.autocorrect, isFalse);
      expect(token.enableSuggestions, isFalse);
      expect(find.text('Get a setup token at bridge.simplefin.org.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('s4cSyncFrom')), findsNothing);
      expect(find.text('More'), findsNothing);
    });

    testWidgets('Connect requires the token', (tester) async {
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'simplefin');
      await tester.tap(find.byKey(const ValueKey('s4cConnect')));
      await tester.pumpAndSettle();
      expect(calls('POST', '/api/v1/provider_connections'), isEmpty);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('201 without setup refreshes and says Connected · syncing',
        (tester) async {
      routes['POST /api/v1/provider_connections'] =
          (_) => http.Response(jsonEncode(created()), 201);
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'simplefin');
      await tester.enterText(
          find.byKey(const ValueKey('s4cField-setup_token')), 'aGVsbG8=');
      await tester.tap(find.byKey(const ValueKey('s4cConnect')));
      await tester.pumpAndSettle();

      final post = calls('POST', '/api/v1/provider_connections').single;
      expect(jsonDecode(post.body), {
        'provider': 'simplefin',
        'connection': {'setup_token': 'aGVsbG8='},
      });
      expect(find.text('Connected · syncing'), findsOneWidget);
      expect(find.byType(TokenConnectionSheet), findsNothing);
      expect(find.text('aGVsbG8='), findsNothing);
    });

    testWidgets('Lunch Flow: More section, date row, sync_start_date sent',
        (tester) async {
      routes['POST /api/v1/provider_connections'] =
          (_) => http.Response(jsonEncode(created(provider: 'lunchflow')), 201);
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'lunchflow');

      expect(find.text('More'), findsOneWidget);
      expect(find.text('Base URL'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Sync history from'), findsOneWidget);
      expect(find.text('Nov 11, 2025'), findsOneWidget);
      expect(field(tester, 'api_key').obscureText, isTrue);
      expect(field(tester, 'base_url').obscureText, isFalse);

      await tester.enterText(
          find.byKey(const ValueKey('s4cField-api_key')), 'lf-key');
      await tester.enterText(
          find.byKey(const ValueKey('s4cField-name')), 'Family');
      await tester.tap(find.byKey(const ValueKey('s4cConnect')));
      await tester.pumpAndSettle();

      expect(
          jsonDecode(calls('POST', '/api/v1/provider_connections').single.body),
          {
            'provider': 'lunchflow',
            'connection': {
              'api_key': 'lf-key',
              'name': 'Family',
              'sync_start_date': '2025-11-11',
            },
          });
    });

    for (final (status, code, message) in [
      (422, 'blank_token', 'Paste your setup token first.'),
      (422, 'invalid_token',
          "That setup token isn't valid. Copy it again from SimpleFIN."),
      (422, 'token_compromised',
          'That setup token was already used or has expired. Get a new one '
              'from SimpleFIN.'),
      (422, 'create_failed',
          "SimpleFIN couldn't set up the connection. Try again."),
      (422, 'unexpected', 'Something went wrong while connecting. Try again.'),
      (422, 'validation_failed', 'Setup token is invalid'),
      (403, 'forbidden', 'Only a family admin can connect providers'),
    ]) {
      testWidgets('create $status $code shows a message and clears the secret',
          (tester) async {
        routes['POST /api/v1/provider_connections'] = (_) => http.Response(
            jsonEncode({
              'error': code,
              // Coded errors get the app's text; the rest show the server's.
              'message': code == 'forbidden' || code == 'validation_failed'
                  ? message
                  : 'server text',
            }),
            status);
        await pump(tester);
        await openAdd(tester);
        await pick(tester, 'simplefin');
        await tester.enterText(
            find.byKey(const ValueKey('s4cField-setup_token')), 'tok');
        await tester.tap(find.byKey(const ValueKey('s4cConnect')));
        await tester.pumpAndSettle();

        expect(find.byType(TokenConnectionSheet), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(field(tester, 'setup_token').controller!.text, isEmpty);
      });
    }

    testWidgets('provider_not_supported falls back to the handoff',
        (tester) async {
      routes['POST /api/v1/provider_connections'] = (_) => http.Response(
          jsonEncode({
            'error': 'provider_not_supported',
            'message': 'Connect it on the web',
          }),
          422);
      await pump(tester);
      await openAdd(tester);
      await pick(tester, 'lunchflow');
      await tester.enterText(
          find.byKey(const ValueKey('s4cField-api_key')), 'k');
      await tester.tap(find.byKey(const ValueKey('s4cConnect')));
      await tester.pumpAndSettle();

      expect(find.byType(TokenConnectionSheet), findsNothing);
      expect(jsonDecode(calls('POST', '/api/v1/web_handoffs').single.body), {
        'web_handoff': {'path': '/settings/providers/lunchflow/connect_form'},
      });
      expect(webAuth.opened, hasLength(1));
    });

    group('account setup', () {
      /// [poll] gets the 1-based request number and returns the accounts and
      /// awaiting_accounts.
      void pendingRoute(
          (List<Map<String, dynamic>>, bool) Function(int request) poll) {
        var n = 0;
        routes['GET /api/v1/provider_connections/new1/pending_accounts'] =
            (_) {
          final (accounts, awaiting) = poll(++n);
          return http.Response(
              jsonEncode({'data': accounts, 'awaiting_accounts': awaiting}),
              200);
        };
      }

      void pendingNow(List<Map<String, dynamic>> accounts) =>
          pendingRoute((_) => (accounts, false));

      Future<void> connectSimplefin(WidgetTester tester) async {
        await openAdd(tester);
        await pick(tester, 'simplefin');
        await tester.enterText(
            find.byKey(const ValueKey('s4cField-setup_token')), 'tok');
        await tester.tap(find.byKey(const ValueKey('s4cConnect')));
      }

      testWidgets('waits, polls every 4 s, then imports', (tester) async {
        routes['POST /api/v1/provider_connections'] = (_) => http.Response(
            jsonEncode(created(setupRequired: true, awaiting: true)), 201);
        pendingRoute((n) => n <= 2
            ? (<Map<String, dynamic>>[], true)
            : (
                [pendingAccount('a1', 'Everyday'), pendingAccount('a2', 'Card')],
                false
              ));
        routes['POST /api/v1/provider_connections/new1/complete_setup'] =
            (_) => http.Response(
                jsonEncode({
                  ...created(),
                  'created_account_ids': ['x1', 'x2'],
                }),
                200);
        await pump(tester);
        await connectSimplefin(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Waiting for SimpleFIN… (first sync)'), findsOneWidget);
        const pendingPath =
            '/api/v1/provider_connections/new1/pending_accounts';
        expect(calls('GET', pendingPath), hasLength(1));
        expect(calls('GET', pendingPath).single.url.queryParameters['provider'],
            'simplefin');

        await tester.pump(const Duration(seconds: 4));
        expect(calls('GET', pendingPath), hasLength(2));
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(calls('GET', pendingPath), hasLength(3));

        expect(find.text('Everyday'), findsOneWidget);
        expect(find.text('Card'), findsOneWidget);
        expect(find.text('Checking'), findsNWidgets(2));
        expect(find.text(r'$1,234.56'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('s4cSetupSyncFrom')), findsOneWidget);
        expect(find.text('Link to an existing account instead?'), findsNothing);

        // Skip the card; change Everyday's type.
        await tester.tap(find.bySemanticsLabel('Import Card'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Checking').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Checking or Savings Account · Savings'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('s4cImport')));
        await tester.pumpAndSettle();

        final post = calls(
                'POST', '/api/v1/provider_connections/new1/complete_setup')
            .single;
        expect(post.url.queryParameters['provider'], 'simplefin');
        expect(jsonDecode(post.body), {
          'sync_start_date': '2025-11-11',
          'accounts': [
            {
              'id': 'a1',
              'import': true,
              'accountable_type': 'Depository',
              'subtype': 'savings',
            },
            {'id': 'a2', 'import': false},
          ],
        });
        expect(find.byType(AccountSetupSheet), findsNothing);
        expect(find.text('Imported 2 accounts · syncing'), findsOneWidget);
      });

      testWidgets('gives up after 3 minutes', (tester) async {
        routes['POST /api/v1/provider_connections'] = (_) => http.Response(
            jsonEncode(created(setupRequired: true, awaiting: true)), 201);
        pendingRoute((_) => (<Map<String, dynamic>>[], true));
        await pump(tester);
        await connectSimplefin(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(AccountSetupSheet), findsOneWidget);

        for (var i = 0; i < 44; i++) {
          await tester.pump(const Duration(seconds: 4));
        }
        expect(find.byType(AccountSetupSheet), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        expect(
            calls('GET', '/api/v1/provider_connections/new1/pending_accounts'),
            hasLength(46));
        expect(find.byType(AccountSetupSheet), findsNothing);
        expect(
            find.text(
                'Still syncing. You can finish setup later from Connections.'),
            findsOneWidget);
      });

      for (final (code, message) in [
        ('invalid_account_type',
            "One of the account types isn't allowed. Pick another type."),
        ('invalid_subtype', "One of the subtypes isn't allowed. Pick another."),
        ('unknown_account',
            'An account is no longer waiting for setup. Close and try again.'),
        ('link_not_supported',
            'Linking to an existing account happens on the web.'),
        ('invalid_sync_start_date', 'Pick a start date no later than today.'),
        ('setup_failed', "The accounts couldn't be created. Try again."),
        ('validation_failed', 'accounts must be an array'),
      ]) {
        testWidgets('complete_setup 422 $code', (tester) async {
          routes['POST /api/v1/provider_connections'] = (_) => http.Response(
              jsonEncode(created(setupRequired: true)), 201);
          pendingNow([pendingAccount('a1', 'Everyday')]);
          routes['POST /api/v1/provider_connections/new1/complete_setup'] =
              (_) => http.Response(
                  jsonEncode({
                    'error': code,
                    'message': 'accounts must be an array',
                  }),
                  422);
          await pump(tester);
          await connectSimplefin(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('s4cImport')));
          await tester.pumpAndSettle();

          expect(find.byType(AccountSetupSheet), findsOneWidget);
          expect(find.text(message), findsOneWidget);
          expect(find.text('Everyday'), findsOneWidget);
        });
      }

      testWidgets('Later closes and leaves the accounts pending',
          (tester) async {
        routes['POST /api/v1/provider_connections'] =
            (_) => http.Response(jsonEncode(created(setupRequired: true)), 201);
        pendingNow([pendingAccount('a1', 'Everyday')]);
        await pump(tester);
        await connectSimplefin(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountSetupSheet), findsNothing);
        expect(
            calls('POST', '/api/v1/provider_connections/new1/complete_setup'),
            isEmpty);
      });

      testWidgets('Link to an existing account hands off to its page',
          (tester) async {
        routes['POST /api/v1/provider_connections'] =
            (_) => http.Response(jsonEncode(created(setupRequired: true)), 201);
        pendingNow([pendingAccount('a1', 'Everyday')]);
        await pump(tester, accounts: [
          homeAccount('acc-9', name: 'Old checking', balance: r'$10.00'),
        ]);
        await connectSimplefin(tester);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Link to an existing account instead?'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Old checking'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountSetupSheet), findsNothing);
        expect(jsonDecode(calls('POST', '/api/v1/web_handoffs').single.body), {
          'web_handoff': {
            'path': '/simplefin_items/select_existing_account?account_id=acc-9',
          },
        });
        expect(webAuth.opened, hasLength(1));
        expect(find.text('Connected · syncing'), findsOneWidget);
      });

      testWidgets('balances follow privacy masking', (tester) async {
        routes['POST /api/v1/provider_connections'] =
            (_) => http.Response(jsonEncode(created(setupRequired: true)), 201);
        pendingNow([pendingAccount('a1', 'Everyday')]);
        await pump(tester, privacyHidden: true);
        await connectSimplefin(tester);
        await tester.pumpAndSettle();

        expect(find.text(r'$1,234.56'), findsNothing);
        expect(find.text(r'$••••'), findsOneWidget);
      });

      testWidgets('Finish setup on a pending row opens account setup',
          (tester) async {
        rows = [
          connectionJson(
              id: 'new1', provider: 'simplefin', pendingSetup: true,
              unlinked: 1, institution: 'Pending Bank'),
          connectionJson(
              id: 'p2', provider: 'plaid', pendingSetup: true,
              institution: 'Plaid Bank'),
        ];
        pendingNow([pendingAccount('a1', 'Everyday')]);
        await pump(tester);

        // Only token providers can finish setup in the app.
        expect(find.text('Finish setup'), findsOneWidget);
        expect(find.text('Fix on the web'), findsOneWidget);
        await tester.tap(find.text('Finish setup'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountSetupSheet), findsOneWidget);
        expect(find.text('Everyday'), findsOneWidget);
      });

      testWidgets('pending_accounts error shows the message and retries',
          (tester) async {
        rows = [
          connectionJson(
              id: 'new1', provider: 'mercury', pendingSetup: true,
              unlinked: 1),
        ];
        var calls = 0;
        routes['GET /api/v1/provider_connections/new1/pending_accounts'] =
            (_) => ++calls == 1
                ? http.Response(
                    jsonEncode({
                      'error': 'provider_error',
                      'message': 'Mercury rejected the token',
                    }),
                    422)
                : http.Response(
                    jsonEncode({
                      'data': [pendingAccount('a1', 'Ops')],
                      'awaiting_accounts': false,
                    }),
                    200);
        await pump(tester);
        await tester.tap(find.text('Finish setup'));
        await tester.pumpAndSettle();

        expect(find.text("Couldn't load the accounts."), findsOneWidget);
        expect(find.text('Mercury rejected the token'), findsOneWidget);
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(find.text('Ops'), findsOneWidget);
        // Mercury takes its start date at create, not here.
        expect(find.byKey(const ValueKey('s4cSetupSyncFrom')), findsNothing);
      });
    });
  });

  group('320 px', () {
    for (final brightness in brightnesses) {
      testWidgets('screen, add sheet, form and setup fit ($brightness)',
          (tester) async {
        rows = [
          withReconnect(
              connectionJson(
                  provider: 'simplefin', requiresUpdate: true,
                  institution: 'A credit union with a very long name',
                  pendingSetup: true, unlinked: 2),
              '/simplefin_items/c1/edit'),
        ];
        routes['GET /api/v1/provider_connections/c1/pending_accounts'] =
            (_) => http.Response(
                jsonEncode({
                  'data': [
                    pendingAccount('a1',
                        'An everyday checking account with a long name'),
                  ],
                  'awaiting_accounts': false,
                }),
                200);
        await pump(tester,
            width: 320, height: 640, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('s4cReconnectBanner')), findsOneWidget);

        await tester.drag(find.text('A credit union with a very long name'),
            const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Reconnect'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(160, 600));
        await tester.pumpAndSettle();

        await openAdd(tester);
        expect(tester.takeException(), isNull);
        await pick(tester, 'lunchflow');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Finish setup'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountSetupSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('parseCallback', () {
    WebHandoffStatus parse(String? s) =>
        WebAuthSession.parseCallback(s == null ? null : Uri.parse(s));
    expect(parse('sureplus://connections/done?status=ok'), WebHandoffStatus.ok);
    expect(parse('sureplus://connections/done?status=cancelled'),
        WebHandoffStatus.cancelled);
    expect(parse('sureplus://connections/done?status=error'),
        WebHandoffStatus.error);
    expect(parse('sureplus://connections/done'), WebHandoffStatus.error);
    expect(parse('sureplus://other/done?status=ok'), WebHandoffStatus.error);
    expect(parse(null), WebHandoffStatus.closed);
  });
}

const brightnesses = [Brightness.light, Brightness.dark];
