import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/family_sync.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'transactions_service.dart';

/// Starts a family-wide sync (`POST /api/v1/sync`) and reads sync status
/// (`GET /api/v1/syncs/:id`, `GET /api/v1/syncs/latest`).
///
/// Named apart from `SyncService`, which replays offline transactions.
class FamilySyncService {
  static const Duration defaultTimeout = Duration(minutes: 2);
  static const Duration defaultInterval = Duration(seconds: 3);

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  FamilySyncService({
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Queues a sync. The server reuses a sync that is already running.
  Future<Map<String, dynamic>> startSync({required String accessToken}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/sync');
    try {
      final response = await _client
          .post(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 202 || response.statusCode == 200) {
        return {
          'success': true,
          'sync': FamilySync.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      return _failure(response, 'Failed to start sync');
    } catch (e) {
      _log('startSync', e);
      return {'success': false, 'error': 'Unable to start sync.'};
    }
  }

  /// One sync by id, or the newest sync visible to the user when [id] is
  /// null. `sync` is null when the family has never synced.
  Future<Map<String, dynamic>> getSync({
    required String accessToken,
    String? id,
  }) async {
    final path = id == null ? 'latest' : Uri.encodeComponent(id);
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/syncs/$path');
    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = (jsonDecode(response.body) as Map<String, dynamic>)['data'];
        return {
          'success': true,
          'sync': data is Map<String, dynamic> ? FamilySync.fromJson(data) : null,
        };
      }
      return _failure(response, 'Failed to load sync status');
    } catch (e) {
      _log('getSync', e);
      return {'success': false, 'error': 'Unable to load sync status.'};
    }
  }

  /// Starts a sync and polls it by id until it reaches a terminal status or
  /// [timeout] passes. [onUpdate] gets every status read.
  ///
  /// Returns `success: true` with `sync` when it completed. Otherwise
  /// `success: false` with `error` set to `unauthorized`, `timeout`, `failed`
  /// (with `sync` and its `message`) or a request error message.
  Future<Map<String, dynamic>> syncAndWait({
    required String accessToken,
    Duration timeout = defaultTimeout,
    Duration interval = defaultInterval,
    void Function(FamilySync sync)? onUpdate,
  }) async {
    final started = await startSync(accessToken: accessToken);
    if (started['success'] != true) return started;

    var sync = started['sync'] as FamilySync;
    onUpdate?.call(sync);
    final deadline = _now().add(timeout);

    while (sync.inProgress) {
      if (!_now().isBefore(deadline)) {
        return {'success': false, 'error': 'timeout', 'sync': sync};
      }
      await _delay(interval);

      final polled = await getSync(accessToken: accessToken, id: sync.id);
      if (polled['error'] == 'unauthorized') return polled;
      // A dropped poll is retried until the deadline rather than reported.
      if (polled['success'] == true && polled['sync'] is FamilySync) {
        sync = polled['sync'] as FamilySync;
        onUpdate?.call(sync);
      }
    }

    if (sync.completed) return {'success': true, 'sync': sync};
    return {
      'success': false,
      'error': 'failed',
      'message': sync.errorMessage,
      'sync': sync,
    };
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    return {
      'success': false,
      'error': TransactionsService.errorMessageFromResponseBody(
        response.body,
        fallback: fallback,
      ),
    };
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'FamilySyncService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
