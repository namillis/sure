import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'log_service.dart';

/// Stores manual closing prices with `POST /api/v1/security_prices`.
///
/// The server only accepts this on self-hosted instances, for a security no
/// provider tracks, held in an account the caller can write to (one with a
/// trade in the security, or a linked account). It then queues a sync of
/// those accounts, so holding values update once the sync finishes.
class SecurityPricesService {
  final http.Client _client;
  final bool _ownsClient;

  SecurityPricesService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Error code the server returns when the instance is not self-hosted.
  static const selfHostedOnly = 'self_hosted_only';

  /// Error code for an unknown security, or one none of the caller's
  /// writable accounts can price.
  static const notFound = 'record_not_found';

  /// Stores one close of [price] (a canonical decimal string, see
  /// `AmountParser.canonicalize`) on [date] (`yyyy-MM-dd`) in [currency].
  ///
  /// On success returns `result`: the decoded response (`security_id`,
  /// `currency`, `created`, `updated`, `start_date`, `end_date`). On failure
  /// returns `error` (a readable message, or `unauthorized` on 401) and, when
  /// the server sent one, its error `code`.
  Future<Map<String, dynamic>> createPrice({
    required String accessToken,
    required String securityId,
    required String price,
    required String date,
    required String currency,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/security_prices');
    final body = {
      'security_id': securityId,
      'prices': [
        {'date': date, 'price': price, 'currency': currency},
      ],
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'result':
              decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'code': _errorCode(response.body),
        'error': errorMessage(response.body),
      };
    } catch (e) {
      LogService.instance.error(
        'SecurityPricesService',
        'createPrice failed with ${e.runtimeType}',
      );
      return {'success': false, 'error': 'Unable to save the price.'};
    }
  }

  static String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// The server's message, followed by its per-row messages. A 422 carries
  /// `errors` as a list of `{index, message}` objects (or plain strings from
  /// other validation paths).
  static String errorMessage(String body) {
    const fallback = 'Failed to save the price';
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return fallback;

      final message = decoded['message'] ?? decoded['error'];
      final errors = decoded['errors'];
      final details = <String>[
        if (errors is List)
          for (final error in errors)
            if (error is Map && error['message'] != null)
              error['message'].toString()
            else if (error is String && error.trim().isNotEmpty)
              error.trim(),
      ].where((detail) => detail != message?.toString()).toList();

      if (message != null && details.isNotEmpty) {
        return '$message: ${details.join('; ')}';
      }
      if (details.isNotEmpty) return details.join('; ');
      if (message != null) return message.toString();
    } catch (_) {}
    return fallback;
  }
}
