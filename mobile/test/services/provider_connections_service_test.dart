import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/provider_connection.dart';
import 'package:sure_mobile/services/provider_connections_service.dart';

import '../support/connection_fixtures.dart';

void main() {
  group('ProviderConnectionsService', () {
    test('list parses the data array', () async {
      final service = ProviderConnectionsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/provider_connections');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
              jsonEncode({
                'data': [
                  connectionJson(),
                  connectionJson(
                    id: 'c2',
                    latest: {
                      'status': 'failed',
                      'error': {'present': true, 'message': 'Sync failed'},
                    },
                  ),
                ],
              }),
              200);
        }),
      );

      final result = await service.list(accessToken: 'token');

      expect(result['success'], true);
      final list = (result['connections'] as List).cast<ProviderConnection>();
      expect(list, hasLength(2));
      expect(list.first.displayName, 'Example Bank');
      expect(list.first.providerLabel, 'Enable banking');
      expect(list.first.totalAccounts, 3);
      expect(list.first.lastSyncedAt, DateTime.utc(2026, 11, 11, 10));
      expect(list.first.needsAttention, isFalse);
      expect(list.last.syncErrorMessage, 'Sync failed');
      expect(list.last.latestSyncStatus, 'failed');
      expect(list.last.needsAttention, isTrue);
    });

    test('401 is unauthorized', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect((await service.list(accessToken: 't'))['error'], 'unauthorized');
    });

    test('500 uses the server message', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => http.Response(
              '{"error":"internal_server_error","message":"An unexpected error occurred"}',
              500)));
      expect(await service.list(accessToken: 't'), {
        'success': false,
        'error': 'An unexpected error occurred',
      });
    });

    test('network errors fail without throwing', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => throw http.ClientException('x')));
      expect((await service.list(accessToken: 't'))['success'], false);
    });
  });

  group('ProviderConnectionsService manage (connections.manage)', () {
    // Two providers can hold the same item id; the provider must go along.
    final plaid = ProviderConnection.fromJson(
        connectionJson(id: 'c1', provider: 'plaid'));

    test('sync POSTs with provider and returns the syncing row', () async {
      late http.Request sent;
      final service = ProviderConnectionsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
              jsonEncode(connectionJson(provider: 'plaid', syncing: true)),
              202);
        }),
      );

      final result =
          await service.sync(accessToken: 'token', connection: plaid);

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/provider_connections/c1/sync');
      expect(sent.url.queryParameters, {'provider': 'plaid'});
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(result['success'], true);
      expect((result['connection'] as ProviderConnection).syncing, isTrue);
    });

    test('disconnect DELETEs with provider and returns the scheduled row',
        () async {
      late http.Request sent;
      final service = ProviderConnectionsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
              jsonEncode(connectionJson(
                  provider: 'plaid', scheduledForDeletion: true)),
              202);
        }),
      );

      final result =
          await service.disconnect(accessToken: 'token', connection: plaid);

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/api/v1/provider_connections/c1');
      expect(sent.url.queryParameters, {'provider': 'plaid'});
      expect(result['success'], true);
      expect((result['connection'] as ProviderConnection).scheduledForDeletion,
          isTrue);
    });

    test('a 202 without a row still succeeds', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => http.Response('', 202)));
      final result = await service.sync(accessToken: 't', connection: plaid);
      expect(result['success'], true);
      expect(result['connection'], isNull);
    });

    const errors = {
      'sync_not_supported': 422,
      'disconnect_not_supported': 422,
      'manual_sync_required': 422,
      'not_connected': 422,
      'reconnect_required': 422,
      'unlink_failed': 422,
      'forbidden': 403,
      'insufficient_scope': 403,
    };
    for (final MapEntry(key: code, value: status) in errors.entries) {
      test('$status $code carries its code and the server message', () async {
        final service = ProviderConnectionsService(
          client: MockClient((_) async => http.Response(
              jsonEncode({'error': code, 'message': 'Server says $code'}),
              status)),
        );

        for (final call in [service.sync, service.disconnect]) {
          final result = await call(accessToken: 't', connection: plaid);
          expect(result['success'], false);
          expect(result['status'], status);
          expect(result['code'], code);
          expect(result['error'], 'Server says $code');
          expect(ProviderConnectionsService.webFixCodes, contains(code));
        }
      });
    }

    test('401 is unauthorized', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect(
          (await service.disconnect(
              accessToken: 't', connection: plaid))['error'],
          'unauthorized');
    });

    test('network errors fail without throwing', () async {
      final service = ProviderConnectionsService(
          client: MockClient((_) async => throw http.ClientException('x')));
      final result = await service.sync(accessToken: 't', connection: plaid);
      expect(result['success'], false);
      expect(result.containsKey('code'), isFalse);
    });
  });

  group('ProviderConnection.needsAttention', () {
    ProviderConnection parse(Map<String, dynamic> json) =>
        ProviderConnection.fromJson(json);

    test('requires_update flag or status', () {
      expect(parse(connectionJson(requiresUpdate: true)).needsAttention, true);
      expect(parse(connectionJson(status: 'requires_update')).needsReconnect,
          true);
    });

    test('pending account setup', () {
      expect(parse(connectionJson(pendingSetup: true)).needsAttention, true);
    });

    test('an error payload without present is ignored', () {
      final c = parse(connectionJson(latest: {
        'status': 'completed',
        'error': null,
      }));
      expect(c.hasSyncError, false);
      expect(c.needsAttention, false);
    });

    test('a connection being deleted never asks for a fix', () {
      expect(
          parse(connectionJson(
                  requiresUpdate: true, scheduledForDeletion: true))
              .needsAttention,
          false);
    });

    test('falls back to the item name without an institution', () {
      final c = parse(connectionJson(institution: null, lastSyncedAt: null));
      expect(c.displayName, 'Item name');
      expect(c.lastSyncedAt, isNull);
    });
  });
}
