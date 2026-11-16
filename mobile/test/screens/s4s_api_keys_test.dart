import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/screens/api_keys_screen.dart';
import 'package:sure_mobile/services/api_keys_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _key({
  String id = 'k1',
  String name = 'Phone',
  String scope = 'read_write',
  bool current = false,
  String? lastUsedAt = '2026-11-11T11:55:00Z',
}) =>
    {
      'id': id,
      'name': name,
      'scopes': [scope],
      'display_key': '********a1b2',
      'current': current,
      'created_at': '2026-10-01T00:00:00Z',
      'last_used_at': lastUsedAt,
      'expires_at': null,
    };

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);

  Future<void> pump(WidgetTester tester, MockClient client) => pumpLocalized(
        tester,
        ApiKeysScreen(
          service: ApiKeysService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          now: () => now,
        ),
      );

  String list(List<Map<String, dynamic>> rows) => jsonEncode({'data': rows});

  testWidgets('lists keys with mono key, scope, last use and this device',
      (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          list([
            _key(current: true),
            _key(
                id: 'k2',
                name: 'Script',
                scope: 'read',
                lastUsedAt: null),
          ]),
          200)),
    );

    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('********a1b2'), findsNWidgets(2));
    expect(find.text('Read & write · Used 5m ago'), findsOneWidget);
    expect(find.text('Read · Never used'), findsOneWidget);
    // Only the other key can be revoked.
    expect(find.byType(SureSwipeActions), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('apiKey-k1')),
            matching: find.text('Revoke')),
        findsNothing);
  });

  testWidgets('swipe revokes after a confirm', (tester) async {
    final writes = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(list([_key(), _key(id: 'k2', name: 'Old')]), 200);
        }
        writes.add(request);
        return http.Response('', 204);
      }),
    );

    await tester.drag(find.text('Old'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('apiKey-k2')),
        matching: find.text('Revoke')));
    await tester.pumpAndSettle();
    expect(find.text('Revoke “Old”?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Revoke')));
    await tester.pumpAndSettle();

    expect(writes.single.method, 'DELETE');
    expect(writes.single.url.path, '/api/v1/api_keys/k2');
    expect(find.text('Old'), findsNothing);
    expect(find.text('API key revoked'), findsOneWidget);
  });

  testWidgets('creating shows the full key once with Copy', (tester) async {
    final posts = <http.Request>[];
    var keys = <Map<String, dynamic>>[_key(current: true)];
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return http.Response(list(keys), 200);
        posts.add(request);
        final created = _key(id: 'k9', name: 'Budget script', scope: 'read');
        keys = [created, ...keys];
        return http.Response(
            jsonEncode({
              'data': {...created, 'plain_key': 'sk_live_secret123'},
            }),
            201);
      }),
    );

    await tester.tap(find.bySemanticsLabel('New API key'));
    await tester.pumpAndSettle();
    // Name is required.
    await tester.tap(find.byKey(const ValueKey('apiKeyFormCreate')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(posts, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('apiKeyName')), 'Budget script');
    await tester.tap(find.byKey(const ValueKey('apiKeyFormCreate')));
    await tester.pumpAndSettle();

    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body, {
      'api_key': {
        'name': 'Budget script',
        'scopes': ['read'],
      },
    });
    expect(find.text('“Budget script” created'), findsOneWidget);
    expect(find.text('sk_live_secret123'), findsOneWidget);
    expect(find.text('Shown once. Store it somewhere safe.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('apiKeyCopy')));
    await tester.pumpAndSettle();
    expect(clipboard, 'sk_live_secret123');
    expect(find.text('Key copied'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('sk_live_secret123'), findsNothing);
  });

  testWidgets('read & write is sent and 429 shows the rate limit message',
      (tester) async {
    final posts = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return http.Response(list([_key()]), 200);
        posts.add(request);
        return http.Response(
            jsonEncode({
              'error': 'rate_limit_exceeded',
              'message': 'Too many API keys created. Try again later.',
            }),
            429);
      }),
    );

    await tester.tap(find.bySemanticsLabel('New API key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('apiKeyName')), 'CI');
    await tester.tap(find.text('Read & write'));
    await tester.tap(find.byKey(const ValueKey('apiKeyFormCreate')));
    await tester.pumpAndSettle();

    expect(
        (jsonDecode(posts.single.body) as Map)['api_key']['scopes'],
        ['read_write']);
    expect(find.text('Too many keys created. Try again later.'), findsOneWidget);
    // The sheet stays open and no key is shown.
    expect(find.byKey(const ValueKey('apiKeyCreatedBanner')), findsNothing);
  });

  testWidgets('a read-only sign-in gets a clear message', (tester) async {
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return http.Response(list([_key()]), 200);
        return http.Response(
            jsonEncode({'error': 'insufficient_scope', 'message': 'nope'}),
            403);
      }),
    );
    await tester.tap(find.bySemanticsLabel('New API key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('apiKeyName')), 'CI');
    await tester.tap(find.byKey(const ValueKey('apiKeyFormCreate')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Creating or revoking a key needs a sign-in with read & write access.'),
        findsOneWidget);
  });

  testWidgets('fits a 320 px screen', (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          list([
            _key(current: true, name: 'A very long key name that keeps going'),
            _key(id: 'k2', name: 'Another long name for a script key'),
          ]),
          200)),
    );
    tester.view.physicalSize = const Size(960, 1920);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.bySemanticsLabel('New API key'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
