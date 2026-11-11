import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// One row of `GET /api/v1/family_exports`.
class FamilyExport {
  const FamilyExport({
    required this.id,
    required this.status,
    required this.filename,
    required this.downloadable,
    this.byteSize,
    this.createdAt,
  });

  final String id;

  /// `pending`, `processing`, `completed` or `failed`.
  final String status;
  final String filename;
  final bool downloadable;
  final int? byteSize;
  final DateTime? createdAt;

  bool get inProgress => status == 'pending' || status == 'processing';

  factory FamilyExport.fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    return FamilyExport(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      filename: json['filename']?.toString() ?? '',
      downloadable: json['downloadable'] == true,
      byteSize: file is Map ? (file['byte_size'] as num?)?.toInt() : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
          ?.toLocal(),
    );
  }
}

/// The file name in a `Content-Disposition` header, preferring the RFC 5987
/// `filename*` form. Returns only a base name, or null when there is none.
String? filenameFromContentDisposition(String? header) {
  if (header == null) return null;
  String? name;
  final extended =
      RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false)
          .firstMatch(header);
  if (extended != null) {
    try {
      name = Uri.decodeComponent(extended.group(1)!.trim());
    } on ArgumentError {
      name = null;
    }
  }
  if (name == null) {
    final plain = RegExp(r'filename\s*=\s*("([^"]*)"|[^;]+)',
            caseSensitive: false)
        .firstMatch(header);
    name = plain == null ? null : (plain.group(2) ?? plain.group(1))?.trim();
  }
  if (name == null) return null;
  // Never let the server pick a directory.
  name = name.split(RegExp(r'[/\\]')).last.trim();
  if (name.isEmpty || name == '.' || name == '..') return null;
  return name;
}

/// Client for `/api/v1/family_exports` (family admins only). Results are
/// `{'success': bool, ...}` maps, with `'error': 'unauthorized'` on 401.
class FamilyExportsService {
  FamilyExportsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);
  static const _downloadTimeout = Duration(minutes: 5);

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  /// Newest first. `'exports'` holds a `List<FamilyExport>`.
  Future<Map<String, dynamic>> list({required String accessToken}) async {
    const fallback = 'Failed to load exports';
    try {
      final response = await _client
          .get(_uri('/api/v1/family_exports', {'per_page': '25'}),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 200) return _failure(response, fallback);
      final exports = extractJsonObjectList(jsonDecode(response.body),
              key: 'data')
          .map(FamilyExport.fromJson)
          .where((e) => e.id.isNotEmpty)
          .toList();
      return {'success': true, 'exports': exports};
    } catch (e) {
      _log('list', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// `POST /api/v1/family_exports` with no body; the server builds it in the
  /// background. `'export'` holds the new pending [FamilyExport].
  Future<Map<String, dynamic>> create({required String accessToken}) async {
    const fallback = 'Failed to start export';
    try {
      final response = await _client
          .post(_uri('/api/v1/family_exports'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 202 &&
          response.statusCode != 201 &&
          response.statusCode != 200) {
        return _failure(response, fallback);
      }
      return {'success': true, 'export': _parseShow(response.body)};
    } catch (e) {
      _log('create', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// `GET /api/v1/family_exports/:id`, for polling one export.
  Future<Map<String, dynamic>> get({
    required String accessToken,
    required String id,
  }) async {
    const fallback = 'Failed to load export';
    try {
      final response = await _client
          .get(_uri('/api/v1/family_exports/${Uri.encodeComponent(id)}'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 200) return _failure(response, fallback);
      return {'success': true, 'export': _parseShow(response.body)};
    } catch (e) {
      _log('get', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// Streams `GET /api/v1/family_exports/:id/download` into a new file in
  /// [directory] (default: the system temp dir), named after the server's
  /// `Content-Disposition` (falling back to [fallbackFilename]).
  /// `'file'` holds the written [File]; the caller deletes it when done.
  Future<Map<String, dynamic>> download({
    required String accessToken,
    required String id,
    required String fallbackFilename,
    Directory? directory,
  }) async {
    const fallback = 'Failed to download export';
    File? file;
    try {
      final request = http.Request(
        'GET',
        _uri('/api/v1/family_exports/${Uri.encodeComponent(id)}/download'),
      )..headers.addAll(ApiConfig.getAuthHeaders(accessToken));
      final response = await _client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        return _failure(http.Response(body, response.statusCode), fallback);
      }
      final name = filenameFromContentDisposition(
              response.headers['content-disposition']) ??
          filenameFromContentDisposition('filename="$fallbackFilename"') ??
          'sure_export.zip';
      final parent = await (directory ?? Directory.systemTemp)
          .createTemp('sure_export_');
      file = File('${parent.path}/$name');
      final sink = file.openWrite();
      try {
        await sink.addStream(response.stream).timeout(_downloadTimeout);
      } finally {
        await sink.close();
      }
      return {'success': true, 'file': file};
    } catch (e) {
      _log('download', e);
      if (file != null) {
        try {
          await file.parent.delete(recursive: true);
        } catch (_) {}
      }
      return {'success': false, 'error': fallback};
    }
  }

  FamilyExport _parseShow(String body) {
    final data = jsonDecode(body);
    final json = data is Map && data['data'] is Map ? data['data'] : data;
    return FamilyExport.fromJson((json as Map).cast<String, dynamic>());
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    return {
      'success': false,
      'status': response.statusCode,
      'error': extractErrorMessage(response.body, fallback: fallback),
    };
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'FamilyExportsService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
