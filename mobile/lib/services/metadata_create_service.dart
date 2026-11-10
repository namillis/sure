import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/category.dart';
import '../models/merchant.dart';
import '../models/transaction_tag.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Creates the tags, categories and merchants a transaction can point at.
///
/// Results are `{'success': bool, ...}` maps carrying `'tag'`, `'category'`
/// or `'merchant'`, with `'error': 'unauthorized'` on 401.
class MetadataCreateService {
  MetadataCreateService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Map<String, String> _jsonHeaders(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  /// `POST /api/v1/tags`. The server picks a color.
  Future<Map<String, dynamic>> createTag({
    required String accessToken,
    required String name,
  }) async {
    return _postJson(
      'createTag',
      path: '/api/v1/tags',
      body: {
        'tag': {'name': name.trim()},
      },
      resultKey: 'tag',
      parse: (json) => TransactionTag.fromJson(json),
      accessToken: accessToken,
      fallback: 'Failed to create tag',
    );
  }

  /// `POST /api/v1/categories`. The server suggests an icon; fails when the
  /// family has locked its categories.
  Future<Map<String, dynamic>> createCategory({
    required String accessToken,
    required String name,
  }) async {
    return _postJson(
      'createCategory',
      path: '/api/v1/categories',
      body: {
        'category': {'name': name.trim()},
      },
      resultKey: 'category',
      parse: (json) => Category.fromJson(json),
      accessToken: accessToken,
      fallback: 'Failed to create category',
    );
  }

  /// Creates one family merchant. The API only creates merchants by CSV
  /// import (`POST /api/v1/merchants` with a `file` part), so this uploads a
  /// one-row CSV. When the merchant already exists the import skips it, and
  /// the existing one is looked up by name instead.
  Future<Map<String, dynamic>> createMerchant({
    required String accessToken,
    required String name,
  }) async {
    final trimmed = name.trim();
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/merchants');
    final csv = 'name\n"${trimmed.replaceAll('"', '""')}"\n';

    // Built by hand: the server compares the part's Content-Type to an exact
    // list ("text/csv", ...), and MultipartFile can only set a bare type
    // through http_parser, which isn't a dependency of this app.
    final boundary =
        'sure-mobile-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final body = '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="merchant.csv"\r\n'
        'Content-Type: text/csv\r\n'
        '\r\n'
        '$csv\r\n'
        '--$boundary--\r\n';

    try {
      final response = await _client
          .post(
            url,
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'multipart/form-data; boundary=$boundary',
            },
            body: utf8.encode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      if (response.statusCode != 201 && response.statusCode != 200) {
        return {
          'success': false,
          'error': extractErrorMessage(
            response.body,
            fallback: 'Failed to create merchant',
          ),
        };
      }

      final data = jsonDecode(response.body);
      final created = extractJsonObjectList(data, key: 'merchants');
      if (created.isNotEmpty) {
        return {'success': true, 'merchant': Merchant.fromJson(created.first)};
      }

      return await _findMerchant(accessToken: accessToken, name: trimmed);
    } catch (e) {
      _logFailure('createMerchant', e);
      return {'success': false, 'error': 'Failed to create merchant'};
    }
  }

  Future<Map<String, dynamic>> _findMerchant({
    required String accessToken,
    required String name,
  }) async {
    final response = await _client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/v1/merchants'),
          headers: _jsonHeaders(accessToken),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    if (response.statusCode == 200) {
      for (final json
          in extractJsonObjectList(jsonDecode(response.body), key: 'merchants')) {
        if (json['name']?.toString() == name) {
          return {'success': true, 'merchant': Merchant.fromJson(json)};
        }
      }
    }
    return {'success': false, 'error': 'Failed to create merchant'};
  }

  Future<Map<String, dynamic>> _postJson<T>(
    String operation, {
    required String path,
    required Map<String, dynamic> body,
    required String resultKey,
    required T Function(Map<String, dynamic>) parse,
    required String accessToken,
    required String fallback,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: _jsonHeaders(accessToken),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, resultKey: parse(data)};
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: fallback),
      };
    } catch (e) {
      _logFailure(operation, e);
      return {'success': false, 'error': fallback};
    }
  }

  void _logFailure(String operation, Object error) {
    LogService.instance.error(
      'MetadataCreateService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
