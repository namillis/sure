import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/models/user.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';

class _Auth extends AuthProvider {
  _Auth(this._u);
  final User? _u;
  @override
  User? get user => _u;
  @override
  bool get isAuthenticated => _u != null;
  @override
  Future<String?> getValidAccessToken() async => 'token';
}

User _user(String id) => User.fromJson({
      'id': id,
      'email': 'a@b.c',
      'first_name': 'A',
      'last_name': 'B',
      'role': 'admin',
    });

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads the features list from /api/v1/version and caches it', () async {
    final requests = <Uri>[];
    final provider = ServerFeaturesProvider(
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response(
            jsonEncode({
              'version': '1',
              'features': ['goals', 'rules.write'],
            }),
            200);
      }),
    );
    provider.updateAuth(_Auth(_user('u1')));
    await _settle();

    expect(requests.single.path, '/api/v1/version');
    expect(provider.has(ServerFeaturesProvider.goals), isTrue);
    expect(provider.has(ServerFeaturesProvider.rulesWrite), isTrue);
    expect(provider.has(ServerFeaturesProvider.budgetsWrite), isFalse);

    // A new provider (next launch) has the list before the network answers.
    final offline = ServerFeaturesProvider(
      client: MockClient((_) async => throw Exception('offline')),
    );
    offline.updateAuth(_Auth(_user('u1')));
    await _settle();
    expect(offline.has(ServerFeaturesProvider.goals), isTrue);
  });

  test('stock Sure (no features key) offers nothing', () async {
    final provider = ServerFeaturesProvider(
      client: MockClient(
          (_) async => http.Response(jsonEncode({'version': '1'}), 200)),
    );
    provider.updateAuth(_Auth(_user('u1')));
    await _settle();
    expect(provider.features, isEmpty);
  });

  test('signing out or switching user drops the other user\'s list', () async {
    final provider = ServerFeaturesProvider(
      client: MockClient((r) async => http.Response(
          jsonEncode({
            'features': ['goals']
          }),
          200)),
    );
    provider.updateAuth(_Auth(_user('u1')));
    await _settle();
    expect(provider.has('goals'), isTrue);

    provider.updateAuth(_Auth(null));
    expect(provider.features, isEmpty);
  });

  test('a failed refresh keeps the cached list', () async {
    SharedPreferences.setMockInitialValues({});
    var fail = false;
    final provider = ServerFeaturesProvider(
      client: MockClient((_) async => fail
          ? http.Response('oops', 500)
          : http.Response(
              jsonEncode({
                'features': ['goals']
              }),
              200)),
    );
    final auth = _Auth(_user('u1'));
    provider.updateAuth(auth);
    await _settle();
    fail = true;
    await provider.refresh(auth);
    expect(provider.has('goals'), isTrue);
  });
}
