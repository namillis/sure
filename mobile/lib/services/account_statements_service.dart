import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account_statement.dart';
import '../utils/data_import_logic.dart';
import 'api_config.dart';
import 'imports_service.dart' show apiFailure;
import 'log_service.dart';

/// Client for `/api/v1/account_statements` (the Statement Vault). Returns the
/// app's `{'success': bool, ...}` maps, with `'error': 'unauthorized'` on 401.
class AccountStatementsService {
  static const Duration _timeout = Duration(seconds: 90);

  final http.Client _client;
  final bool _ownsClient;

  AccountStatementsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri([Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/account_statements')
          .replace(queryParameters: query);

  /// Newest first, optionally only [accountId]'s. `'statements'` holds a
  /// `List<AccountStatement>`.
  Future<Map<String, dynamic>> list({
    required String accessToken,
    String? accountId,
    int perPage = 25,
  }) async {
    try {
      final response = await _client
          .get(
            _uri({
              'page': '1',
              'per_page': '$perPage',
              if (accountId != null) 'account_id': accountId,
            }),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return apiFailure(response, 'Failed to load statements');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'statements': (data['data'] as List<dynamic>? ?? [])
            .map((j) => AccountStatement.fromJson(j as Map<String, dynamic>))
            .toList(),
      };
    } catch (e) {
      return _error('list', e, 'Unable to load statements. Please try again later.');
    }
  }

  /// Uploads [bytes] as `file`, linked to [accountId] when given.
  ///
  /// On success `'statement'` holds the stored [AccountStatement] and
  /// `'duplicate'` says the server already had this file (it then returns
  /// the existing copy). A duplicate the user can't see comes back as
  /// `'code': 'duplicate'` with `'success': false`.
  Future<Map<String, dynamic>> upload({
    required String accessToken,
    required List<int> bytes,
    required String filename,
    String? accountId,
  }) async {
    try {
      final type = statementContentTypes[fileExtension(filename)] ??
          'application/octet-stream';
      final slash = type.indexOf('/');
      final request = http.MultipartRequest('POST', _uri())
        ..headers.addAll(ApiConfig.getAuthHeaders(accessToken))
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: http.MediaType(
              type.substring(0, slash), type.substring(slash + 1)),
        ));
      if (accountId != null) request.fields['account_id'] = accountId;
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(_timeout));
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final meta = data['meta'] as Map<String, dynamic>? ?? const {};
        return {
          'success': true,
          'statement': AccountStatement.fromJson(
              data['data'] as Map<String, dynamic>),
          'duplicate': meta['duplicate'] == true,
        };
      }
      return apiFailure(response, 'Statement could not be uploaded');
    } catch (e) {
      return _error('upload', e, 'Unable to upload. Please try again later.');
    }
  }

  Map<String, dynamic> _error(String operation, Object error, String message) {
    LogService.instance.error(
        'AccountStatementsService', '$operation failed with ${error.runtimeType}');
    return {'success': false, 'error': message};
  }
}
