import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transaction_split.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'transactions_service.dart';

/// `/api/v1/transactions/:id/split`: read, create, replace and remove a split.
///
/// Results are `{'success': bool, ...}` maps. A successful read or write
/// carries `'split'`; a 404 from read/update/destroy sets `'notSplit': true`;
/// a 401 gives `'error': 'unauthorized'`.
class TransactionSplitService {
  TransactionSplitService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Uri _url(String transactionId) => Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/transactions/'
        '${Uri.encodeComponent(transactionId)}/split',
      );

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> getSplit({
    required String accessToken,
    required String transactionId,
  }) {
    return _send(
      'getSplit',
      () => _client.get(_url(transactionId), headers: _headers(accessToken)),
      fallback: 'Failed to load split',
    );
  }

  Future<Map<String, dynamic>> createSplit({
    required String accessToken,
    required String transactionId,
    required List<SplitPart> parts,
  }) {
    return _send(
      'createSplit',
      () => _client.post(
        _url(transactionId),
        headers: _headers(accessToken),
        body: _body(parts),
      ),
      fallback: 'Failed to split transaction',
    );
  }

  /// Replaces every child. Anything not sent (a merchant, tags, exclusion) is
  /// not carried over, so send each part in full.
  Future<Map<String, dynamic>> updateSplit({
    required String accessToken,
    required String transactionId,
    required List<SplitPart> parts,
  }) {
    return _send(
      'updateSplit',
      () => _client.patch(
        _url(transactionId),
        headers: _headers(accessToken),
        body: _body(parts),
      ),
      fallback: 'Failed to update split',
    );
  }

  Future<Map<String, dynamic>> deleteSplit({
    required String accessToken,
    required String transactionId,
  }) {
    return _send(
      'deleteSplit',
      () => _client.delete(_url(transactionId), headers: _headers(accessToken)),
      fallback: 'Failed to remove split',
    );
  }

  /// The API's message, plus its `errors` when they add detail. The split
  /// endpoints repeat the message as the only error when there is none.
  static String errorMessage(String body, {required String fallback}) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final message = data['message']?.toString();
        final errors = data['errors'] is List
            ? (data['errors'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty && e != message)
                .toList()
            : const <String>[];
        if (message != null && message.isNotEmpty) {
          return errors.isEmpty ? message : '$message: ${errors.join('; ')}';
        }
      }
    } catch (_) {
      // Not JSON; use the fallback.
    }
    return TransactionsService.errorMessageFromResponseBody(
      body,
      fallback: fallback,
    );
  }

  String _body(List<SplitPart> parts) => jsonEncode({
        'split': {'splits': parts.map((part) => part.toJson()).toList()},
      });

  Future<Map<String, dynamic>> _send(
    String operation,
    Future<http.Response> Function() request, {
    required String fallback,
  }) async {
    try {
      final response = await request().timeout(_timeout);
      final status = response.statusCode;

      if (status == 204) return {'success': true};
      if (status == 200 || status == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'split': TransactionSplit.fromJson(data)};
      }
      if (status == 401) return {'success': false, 'error': 'unauthorized'};

      return {
        'success': false,
        if (status == 404) 'notSplit': true,
        'error': errorMessage(response.body, fallback: fallback),
      };
    } catch (e) {
      LogService.instance.error(
        'TransactionSplitService',
        '$operation failed with ${e.runtimeType}',
      );
      return {'success': false, 'error': fallback};
    }
  }
}
