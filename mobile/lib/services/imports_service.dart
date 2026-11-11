import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/data_import.dart';
import 'api_config.dart';
import 'log_service.dart';

/// Client for `/api/v1/imports`. Returns the app's `{'success': bool, ...}`
/// maps, with `'error': 'unauthorized'` on 401.
///
/// The API has no endpoint that publishes an existing import: the only way
/// to start one is `POST /imports` with `publish=true`. So the wizard
/// previews with [preflight] and publishes with one [create] call.
class ImportsService {
  static const Duration _timeout = Duration(seconds: 60);

  final http.Client _client;
  final bool _ownsClient;

  ImportsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/imports$path')
          .replace(queryParameters: query);

  /// Newest first. `'imports'` holds a `List<DataImport>`.
  Future<Map<String, dynamic>> list({
    required String accessToken,
    int page = 1,
    int perPage = 25,
  }) async {
    try {
      final response = await _client
          .get(
            _uri('', {'page': '$page', 'per_page': '$perPage'}),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return _failure(response, 'Failed to load imports');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'imports': (data['data'] as List<dynamic>? ?? [])
            .map((j) => DataImport.fromJson(j as Map<String, dynamic>))
            .toList(),
      };
    } catch (e) {
      return _error('list', e, 'Unable to load imports. Please try again later.');
    }
  }

  /// `'import'` holds a [DataImport].
  Future<Map<String, dynamic>> show({
    required String accessToken,
    required String id,
  }) async {
    try {
      final response = await _client
          .get(_uri('/${Uri.encodeComponent(id)}'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return _failure(response, 'Failed to load import');
      }
      return {'success': true, 'import': _parseImport(response.body)};
    } catch (e) {
      return _error('show', e, 'Unable to load import. Please try again later.');
    }
  }

  /// The first [perPage] parsed rows. `'rows'` holds a `List<DataImportRow>`.
  Future<Map<String, dynamic>> rows({
    required String accessToken,
    required String id,
    int perPage = 20,
  }) async {
    try {
      final response = await _client
          .get(
            _uri('/${Uri.encodeComponent(id)}/rows',
                {'page': '1', 'per_page': '$perPage'}),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return _failure(response, 'Failed to load rows');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'rows': (data['data'] as List<dynamic>? ?? [])
            .map((j) => DataImportRow.fromJson(j as Map<String, dynamic>))
            .toList(),
      };
    } catch (e) {
      return _error('rows', e, 'Unable to load rows. Please try again later.');
    }
  }

  /// Checks [csv] without saving anything. [config] uses the
  /// `import_config_params` names (date_col_label, col_sep, ...).
  /// `'preflight'` holds an [ImportPreflight].
  Future<Map<String, dynamic>> preflight({
    required String accessToken,
    required List<int> csv,
    required String filename,
    String? accountId,
    Map<String, String> config = const {},
  }) async {
    try {
      final response = await _multipart(
        '/preflight',
        accessToken: accessToken,
        csv: csv,
        filename: filename,
        fields: {
          'type': 'TransactionImport',
          if (accountId != null) 'account_id': accountId,
          ...config,
        },
      );
      if (response.statusCode != 200) {
        return _failure(response, 'Could not check the file');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'preflight':
            ImportPreflight.fromJson(data['data'] as Map<String, dynamic>),
      };
    } catch (e) {
      return _error('preflight', e, 'Unable to check the file. Please try again later.');
    }
  }

  /// Creates a TransactionImport from [csv] into [accountId]; with [publish]
  /// the server also queues it. `'import'` holds the created [DataImport].
  Future<Map<String, dynamic>> create({
    required String accessToken,
    required List<int> csv,
    required String filename,
    required String accountId,
    Map<String, String> config = const {},
    bool publish = true,
  }) async {
    try {
      final response = await _multipart(
        '',
        accessToken: accessToken,
        csv: csv,
        filename: filename,
        fields: {
          'type': 'TransactionImport',
          'account_id': accountId,
          ...config,
          if (publish) 'publish': 'true',
        },
      );
      if (response.statusCode != 201) {
        return _failure(response, 'Import could not be created');
      }
      return {'success': true, 'import': _parseImport(response.body)};
    } catch (e) {
      return _error('create', e, 'Unable to start the import. Please try again later.');
    }
  }

  /// Polls [show] every [interval] until the import is terminal or no longer
  /// importing, [timeout] passes on [clock], or [cancelled] returns true.
  /// `'import'` holds the last [DataImport]; `'timedOut'` says the cap hit.
  Future<Map<String, dynamic>> waitForCompletion({
    required String accessToken,
    required String id,
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 3),
    DateTime Function() clock = DateTime.now,
    Future<void> Function(Duration)? sleep,
    bool Function()? cancelled,
    void Function(DataImport)? onUpdate,
  }) async {
    final wait = sleep ?? (d) => Future<void>.delayed(d);
    final deadline = clock().add(timeout);
    DataImport? last;
    while (true) {
      final result = await show(accessToken: accessToken, id: id);
      if (result['success'] != true) return result;
      last = result['import'] as DataImport;
      onUpdate?.call(last);
      if (last.terminal || !last.inProgress) {
        return {'success': true, 'import': last, 'timedOut': false};
      }
      if (cancelled?.call() == true) {
        return {'success': true, 'import': last, 'timedOut': false, 'cancelled': true};
      }
      if (!clock().isBefore(deadline)) {
        return {'success': true, 'import': last, 'timedOut': true};
      }
      await wait(interval);
    }
  }

  Future<http.Response> _multipart(
    String path, {
    required String accessToken,
    required List<int> csv,
    required String filename,
    required Map<String, String> fields,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(ApiConfig.getAuthHeaders(accessToken))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        csv,
        filename: filename,
        contentType: http.MediaType('text', 'csv'),
      ));
    final streamed = await _client.send(request).timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  DataImport _parseImport(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    return DataImport.fromJson(data['data'] as Map<String, dynamic>);
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) =>
      apiFailure(response, fallback);

  Map<String, dynamic> _error(String operation, Object error, String message) {
    LogService.instance
        .error('ImportsService', '$operation failed with ${error.runtimeType}');
    return {'success': false, 'error': message};
  }
}

/// 401 is `unauthorized`; otherwise the server's `errors` or `message`, else
/// [fallback]. `'code'` is the server's `error` code and `'status'` the HTTP
/// status.
Map<String, dynamic> apiFailure(http.Response response, String fallback) {
  if (response.statusCode == 401) {
    return {'success': false, 'error': 'unauthorized'};
  }
  var message = fallback;
  String? code;
  try {
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      code = data['error']?.toString();
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        message = errors
            .map((e) => e is Map ? (e['message'] ?? e).toString() : e.toString())
            .join('\n');
      } else if (data['message'] is String) {
        message = data['message'] as String;
      }
    }
  } catch (_) {}
  return {
    'success': false,
    'error': message,
    if (code != null) 'code': code,
    'status': response.statusCode,
  };
}
