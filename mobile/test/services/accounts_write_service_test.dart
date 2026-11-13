import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/services/accounts_service.dart';

const _accountJson = {
  'id': 'a1',
  'name': 'Home',
  'balance': r'$450,000.00',
  'balance_cents': 45000000,
  'currency': 'USD',
  'classification': 'asset',
  'account_type': 'property',
  'subtype': 'single_family_home',
};

void main() {
  test('createAccount posts the account body and parses the 201', () async {
    late http.Request sent;
    final service = AccountsService(
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(_accountJson), 201);
      }),
    );

    final result = await service.createAccount(
      accessToken: 't',
      account: {'accountable_type': 'Property', 'name': 'Home'},
    );

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/accounts');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {
      'account': {'accountable_type': 'Property', 'name': 'Home'},
    });
    expect(result['success'], isTrue);
    expect((result['account'] as Account).id, 'a1');
  });

  test('updateAccount patches the account path', () async {
    late http.Request sent;
    final service = AccountsService(
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(_accountJson), 200);
      }),
    );

    final result = await service.updateAccount(
      accessToken: 't',
      id: 'a1',
      account: {'name': 'Cabin'},
    );

    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/accounts/a1');
    expect(jsonDecode(sent.body), {
      'account': {'name': 'Cabin'},
    });
    expect(result['success'], isTrue);
  });

  test('deleteAccount succeeds on 202', () async {
    late http.Request sent;
    final service = AccountsService(
      client: MockClient((request) async {
        sent = request;
        return http.Response(
            jsonEncode({'id': 'a1', 'message': 'Account scheduled for deletion'}),
            202);
      }),
    );

    final result = await service.deleteAccount(accessToken: 't', id: 'a1');

    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/api/v1/accounts/a1');
    expect(result['success'], isTrue);
    expect(result.containsKey('account'), isFalse);
  });

  test('a linked account 422 surfaces the server message', () async {
    final service = AccountsService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': 'validation_failed',
              'message':
                  'Linked accounts cannot be deleted; disconnect the account first',
            }),
            422,
          )),
    );

    final result = await service.deleteAccount(accessToken: 't', id: 'a1');

    expect(result['success'], isFalse);
    expect(result['status'], 422);
    expect(result['code'], 'validation_failed');
    expect(result['error'],
        'Linked accounts cannot be deleted; disconnect the account first');
  });

  test('401 is unauthorized and 403 keeps the scope code', () async {
    var status = 401;
    final service = AccountsService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': 'insufficient_scope',
              'message': 'This action requires the read_write scope',
            }),
            status,
          )),
    );

    final unauthorized = await service.createAccount(
        accessToken: 't', account: {'name': 'X'});
    expect(unauthorized['error'], 'unauthorized');

    status = 403;
    final forbidden = await service.createAccount(
        accessToken: 't', account: {'name': 'X'});
    expect(forbidden['code'], 'insufficient_scope');
  });
}
