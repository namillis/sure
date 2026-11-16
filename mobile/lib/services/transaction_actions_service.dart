import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/recurring_transaction.dart';
import '../models/transaction.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'transactions_service.dart';

/// One match the web's "match as transfer" dialog offers.
class TransferCandidate {
  const TransferCandidate({required this.transaction, this.accountName});

  final Transaction transaction;
  final String? accountName;
}

/// An account the other side of a new transfer can be created in.
class TransferTargetAccount {
  const TransferTargetAccount({required this.id, required this.name});

  final String id;
  final String name;
}

/// The Sure+ transaction actions (round 4b, section 1): transfer matching,
/// duplicate merging, sync unlock, reconcile and "Mark as recurring".
///
/// Every endpoint takes the transaction `id`. Results are
/// `{'success': bool, ...}` maps; a write that returns the transaction
/// carries `'transaction'`. A failure carries `'error'` (the server's
/// message, or `'unauthorized'` on 401), `'status'`, and the server's
/// `'code'` (`error`) and `'reason'` keys when it sent them.
class TransactionActionsService {
  TransactionActionsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Uri _url(String transactionId, String action, [Map<String, String>? query]) =>
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/transactions/'
        '${Uri.encodeComponent(transactionId)}/$action',
      ).replace(queryParameters: query);

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  void close() => _client.close();

  // transactions.transfers

  Future<Map<String, dynamic>> transferCandidates({
    required String accessToken,
    required String transactionId,
  }) {
    return _send(
      'transferCandidates',
      () => _client.get(_url(transactionId, 'transfer_candidates'),
          headers: _headers(accessToken)),
      fallback: 'Failed to load transfer matches',
      parse: (data) {
        final candidates = <TransferCandidate>[];
        final rawCandidates = data['candidates'];
        if (rawCandidates is List) {
          for (final item in rawCandidates) {
            if (item is! Map || item['transaction'] is! Map) continue;
            final account = item['account'];
            candidates.add(TransferCandidate(
              transaction: Transaction.fromJson(
                  Map<String, dynamic>.from(item['transaction'] as Map)),
              accountName: account is Map ? account['name']?.toString() : null,
            ));
          }
        }
        final accounts = <TransferTargetAccount>[];
        final rawAccounts = data['accounts'];
        if (rawAccounts is List) {
          for (final item in rawAccounts) {
            final id = item is Map ? item['id']?.toString() : null;
            if (id == null || id.isEmpty) continue;
            accounts.add(TransferTargetAccount(
              id: id,
              name: (item as Map)['name']?.toString() ?? '',
            ));
          }
        }
        return {'candidates': candidates, 'accounts': accounts};
      },
    );
  }

  /// Pairs the transaction with [matchedEntryId] (`method: existing`), or
  /// creates its other side in [targetAccountId] (`method: new`). Resolves
  /// with this transaction's side of the new transfer.
  Future<Map<String, dynamic>> createTransferMatch({
    required String accessToken,
    required String transactionId,
    String? matchedEntryId,
    String? targetAccountId,
  }) {
    final body = matchedEntryId != null
        ? {'method': 'existing', 'matched_entry_id': matchedEntryId}
        : {'method': 'new', 'target_account_id': targetAccountId};
    return _send(
      'createTransferMatch',
      () => _client.post(
        _url(transactionId, 'transfer_match'),
        headers: _headers(accessToken),
        body: jsonEncode({'transfer_match': body}),
      ),
      fallback: 'Failed to mark as transfer',
      parse: (data) {
        for (final side in ['outflow', 'inflow']) {
          final json = data[side];
          if (json is Map && json['id']?.toString() == transactionId) {
            return {
              'transaction':
                  Transaction.fromJson(Map<String, dynamic>.from(json)),
            };
          }
        }
        return const {};
      },
    );
  }

  /// "Not a transfer": unmatches a transfer, or dismisses a transfer hint.
  Future<Map<String, dynamic>> deleteTransferMatch({
    required String accessToken,
    required String transactionId,
  }) {
    return _send(
      'deleteTransferMatch',
      () => _client.delete(_url(transactionId, 'transfer_match'),
          headers: _headers(accessToken)),
      fallback: 'Failed to update transfer',
      parse: _transaction,
    );
  }

  // transactions.duplicates

  Future<Map<String, dynamic>> mergeDuplicate({
    required String accessToken,
    required String transactionId,
  }) =>
      _post(accessToken, transactionId, 'merge_duplicate',
          fallback: 'Failed to merge');

  Future<Map<String, dynamic>> dismissDuplicate({
    required String accessToken,
    required String transactionId,
  }) =>
      _post(accessToken, transactionId, 'dismiss_duplicate',
          fallback: 'Failed to dismiss');

  /// A page of posted transactions a pending one may have become:
  /// `'candidates'` (a list of [Transaction]), `'hasMore'` and `'nextOffset'`.
  Future<Map<String, dynamic>> pendingMergeCandidates({
    required String accessToken,
    required String transactionId,
    int offset = 0,
  }) {
    return _send(
      'pendingMergeCandidates',
      () => _client.get(
        _url(transactionId, 'pending_merge_candidates',
            {'offset': offset.toString()}),
        headers: _headers(accessToken),
      ),
      fallback: 'Failed to load posted transactions',
      parse: (data) {
        final candidates = <Transaction>[
          if (data['candidates'] is List)
            for (final item in data['candidates'] as List)
              if (item is Map)
                Transaction.fromJson(Map<String, dynamic>.from(item)),
        ];
        final pagination = data['pagination'];
        final hasMore = pagination is Map && pagination['has_more'] == true;
        return {
          'candidates': candidates,
          'hasMore': hasMore,
          'nextOffset': offset + candidates.length,
        };
      },
    );
  }

  Future<Map<String, dynamic>> pendingMerge({
    required String accessToken,
    required String transactionId,
    required String postedEntryId,
  }) {
    return _send(
      'pendingMerge',
      () => _client.post(
        _url(transactionId, 'pending_merge'),
        headers: _headers(accessToken),
        body: jsonEncode({
          'pending_merge': {'posted_entry_id': postedEntryId},
        }),
      ),
      fallback: 'Failed to merge',
      parse: _transaction,
    );
  }

  // transactions.locks

  Future<Map<String, dynamic>> unlock({
    required String accessToken,
    required String transactionId,
  }) =>
      _post(accessToken, transactionId, 'unlock', fallback: 'Failed to unlock');

  /// Moves the reconciled status one step. Not idempotent: never retry it.
  Future<Map<String, dynamic>> reconcile({
    required String accessToken,
    required String transactionId,
  }) {
    return _send(
      'reconcile',
      () => _client.patch(_url(transactionId, 'reconcile'),
          headers: _headers(accessToken)),
      fallback: 'Failed to update status',
      parse: _transaction,
    );
  }

  // transactions.mark_recurring

  /// 201: `'recurring'` is the new series. 409: `'conflict': true`, with
  /// `'recurring'` set when the user can see the existing series.
  Future<Map<String, dynamic>> markAsRecurring({
    required String accessToken,
    required String transactionId,
  }) async {
    final result = await _send(
      'markAsRecurring',
      () => _client.post(_url(transactionId, 'mark_as_recurring'),
          headers: _headers(accessToken)),
      fallback: 'Failed to mark as recurring',
      parse: (data) => {'recurring': RecurringTransaction.fromJson(data)},
      parseError: (data) {
        final series = data['recurring_transaction'];
        return {
          if (series is Map)
            'recurring': RecurringTransaction.fromJson(
                Map<String, dynamic>.from(series)),
        };
      },
    );
    if (result['status'] == 409) return {...result, 'conflict': true};
    return result;
  }

  static Map<String, dynamic> _transaction(Map<String, dynamic> data) =>
      {'transaction': Transaction.fromJson(data)};

  Future<Map<String, dynamic>> _post(
    String accessToken,
    String transactionId,
    String action, {
    required String fallback,
  }) {
    return _send(
      action,
      () => _client.post(_url(transactionId, action),
          headers: _headers(accessToken)),
      fallback: fallback,
      parse: _transaction,
    );
  }

  Future<Map<String, dynamic>> _send(
    String operation,
    Future<http.Response> Function() request, {
    required String fallback,
    required Map<String, dynamic> Function(Map<String, dynamic> data) parse,
    Map<String, dynamic> Function(Map<String, dynamic> data)? parseError,
  }) async {
    try {
      final response = await request().timeout(_timeout);
      final status = response.statusCode;
      if (status == 401) {
        return {'success': false, 'status': 401, 'error': 'unauthorized'};
      }

      Map<String, dynamic> data = const {};
      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) data = Map<String, dynamic>.from(decoded);
        } on FormatException {
          // Not JSON; handled below.
        }
      }

      if (status == 200 || status == 201) {
        return {'success': true, 'status': status, ...parse(data)};
      }

      final message = data['message']?.toString();
      return {
        'success': false,
        'status': status,
        if (data['error'] != null) 'code': data['error'].toString(),
        if (data['reason'] != null) 'reason': data['reason'].toString(),
        'error': message != null && message.isNotEmpty
            ? message
            : TransactionsService.errorMessageFromResponseBody(
                response.body,
                fallback: fallback,
              ),
        ...?parseError?.call(data),
      };
    } catch (e) {
      LogService.instance.error(
        'TransactionActionsService',
        '$operation failed with ${e.runtimeType}',
      );
      return {'success': false, 'error': fallback};
    }
  }
}
