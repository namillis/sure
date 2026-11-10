import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/family_sync.dart';
import 'package:sure_mobile/services/family_sync_service.dart';

String _created(String status) =>
    '{"id":"sync_1","status":"$status","syncable_type":"Family",'
    '"syncable_id":"fam_1","syncing_at":null,"completed_at":null,'
    '"window_start_date":null,"window_end_date":null,'
    '"message":"Sync has been queued and will apply all active rules"}';

String _show(String status, {String error = 'null'}) =>
    '{"data":{"id":"sync_1","status":"$status",'
    '"in_progress":${status == 'pending' || status == 'syncing'},'
    '"terminal":${status != 'pending' && status != 'syncing'},'
    '"syncable":{"type":"Family","id":"fam_1","name":null},"parent_id":null,'
    '"children_count":2,"window_start_date":null,"window_end_date":null,'
    '"pending_at":"2026-11-10T12:00:00Z","syncing_at":"2026-11-10T12:00:01Z",'
    '"completed_at":${status == 'completed' ? '"2026-11-10T12:00:09Z"' : 'null'},'
    '"failed_at":null,"error":$error,'
    '"created_at":"2026-11-10T12:00:00Z","updated_at":"2026-11-10T12:00:09Z"}}';

/// A clock that only moves when the service "sleeps".
class _FakeClock {
  DateTime now = DateTime(2026, 11, 10, 12);
  final List<Duration> sleeps = [];

  Future<void> delay(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
  }
}

void main() {
  group('FamilySyncService', () {
    test('startSync posts to /api/v1/sync', () async {
      final service = FamilySyncService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/sync');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(_created('pending'), 202);
        }),
      );

      final result = await service.startSync(accessToken: 'token');
      expect(result['success'], true);
      expect((result['sync'] as FamilySync).id, 'sync_1');
      expect((result['sync'] as FamilySync).inProgress, true);
    });

    test('getSync reads latest, or null data when never synced', () async {
      final service = FamilySyncService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/syncs/latest');
          return http.Response('{"data":null}', 200);
        }),
      );

      final result = await service.getSync(accessToken: 'token');
      expect(result, {'success': true, 'sync': null});
    });

    test('syncAndWait polls the started sync by id until it completes',
        () async {
      final clock = _FakeClock();
      final statuses = ['syncing', 'syncing', 'completed'];
      final paths = <String>[];
      final service = FamilySyncService(
        now: () => clock.now,
        delay: clock.delay,
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            return http.Response(_created('pending'), 202);
          }
          return http.Response(_show(statuses.removeAt(0)), 200);
        }),
      );

      final seen = <String>[];
      final result = await service.syncAndWait(
        accessToken: 'token',
        onUpdate: (s) => seen.add(s.status),
      );

      expect(result['success'], true);
      expect((result['sync'] as FamilySync).completed, true);
      expect(paths, [
        'POST /api/v1/sync',
        'GET /api/v1/syncs/sync_1',
        'GET /api/v1/syncs/sync_1',
        'GET /api/v1/syncs/sync_1',
      ]);
      expect(seen, ['pending', 'syncing', 'syncing', 'completed']);
      expect(clock.sleeps, List.filled(3, FamilySyncService.defaultInterval));
    });

    test('syncAndWait reports a failed sync with its message', () async {
      final clock = _FakeClock();
      final service = FamilySyncService(
        now: () => clock.now,
        delay: clock.delay,
        client: MockClient((request) async => request.method == 'POST'
            ? http.Response(_created('pending'), 202)
            : http.Response(
                _show('failed', error: '{"message":"Sync failed"}'), 200)),
      );

      final result = await service.syncAndWait(accessToken: 'token');
      expect(result['success'], false);
      expect(result['error'], 'failed');
      expect(result['message'], 'Sync failed');
    });

    test('syncAndWait gives up after the timeout', () async {
      final clock = _FakeClock();
      var polls = 0;
      final service = FamilySyncService(
        now: () => clock.now,
        delay: clock.delay,
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(_created('pending'), 202);
          }
          polls++;
          return http.Response(_show('syncing'), 200);
        }),
      );

      final result = await service.syncAndWait(
        accessToken: 'token',
        timeout: const Duration(seconds: 10),
        interval: const Duration(seconds: 3),
      );

      expect(result['success'], false);
      expect(result['error'], 'timeout');
      // Polls at 3s, 6s, 9s and 12s, then the 12s check passes the deadline.
      expect(polls, 4);
    });

    test('syncAndWait keeps polling through a dropped status read', () async {
      final clock = _FakeClock();
      final responses = [
        http.Response('oops', 500),
        http.Response(_show('completed'), 200),
      ];
      final service = FamilySyncService(
        now: () => clock.now,
        delay: clock.delay,
        client: MockClient((request) async => request.method == 'POST'
            ? http.Response(_created('pending'), 202)
            : responses.removeAt(0)),
      );

      final result = await service.syncAndWait(accessToken: 'token');
      expect(result['success'], true);
    });

    test('returns unauthorized on 401 from start and from polling', () async {
      final startRefused = FamilySyncService(
        client: MockClient(
            (_) async => http.Response('{"error":"unauthorized"}', 401)),
      );
      expect(await startRefused.syncAndWait(accessToken: 'token'),
          {'success': false, 'error': 'unauthorized'});

      final clock = _FakeClock();
      final pollRefused = FamilySyncService(
        now: () => clock.now,
        delay: clock.delay,
        client: MockClient((request) async => request.method == 'POST'
            ? http.Response(_created('pending'), 202)
            : http.Response('{"error":"unauthorized"}', 401)),
      );
      expect(await pollRefused.syncAndWait(accessToken: 'token'),
          {'success': false, 'error': 'unauthorized'});
    });
  });
}
