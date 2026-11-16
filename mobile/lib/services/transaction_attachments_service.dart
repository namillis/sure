import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/transaction_attachment.dart';
import 'api_config.dart';
import 'imports_service.dart' show apiFailure;
import 'log_service.dart';

/// Client for a transaction's attachments (Sure+ `transactions.attachments`).
/// Returns the app's `{'success': bool, ...}` maps, with
/// `'error': 'unauthorized'` on 401 and the server's message otherwise.
class TransactionAttachmentsService {
  static const Duration _timeout = Duration(seconds: 60);

  final http.Client _client;
  final bool _ownsClient;

  TransactionAttachmentsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  String _attachmentsPath(String transactionId) =>
      '/api/v1/transactions/${Uri.encodeComponent(transactionId)}/attachments';

  /// Where [attachment]'s file streams from. The JSON `url` is used only
  /// when it points at the signed-in server, so the auth headers never go
  /// to another host.
  Uri fileUri(TransactionAttachment attachment) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final url = Uri.tryParse(attachment.url);
    if (url != null &&
        url.hasScheme &&
        url.scheme == base.scheme &&
        url.host == base.host &&
        url.port == base.port) {
      return url;
    }
    return _uri('/api/v1/attachments/${Uri.encodeComponent(attachment.id)}');
  }

  /// `POST /transactions/:id/attachments` as multipart `file`.
  /// `'attachment'` holds the stored [TransactionAttachment].
  Future<Map<String, dynamic>> upload({
    required String accessToken,
    required String transactionId,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    try {
      final slash = contentType.indexOf('/');
      final request =
          http.MultipartRequest('POST', _uri(_attachmentsPath(transactionId)))
            ..headers.addAll(ApiConfig.getAuthHeaders(accessToken))
            ..files.add(http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: http.MediaType(contentType.substring(0, slash),
                  contentType.substring(slash + 1)),
            ));
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(_timeout));
      if (response.statusCode == 201 || response.statusCode == 200) {
        final attachment =
            TransactionAttachment.fromJson(jsonDecode(response.body));
        if (attachment == null) throw const FormatException('No attachment');
        return {'success': true, 'attachment': attachment};
      }
      return apiFailure(response, 'The file could not be attached');
    } catch (e) {
      return _error('upload', e, 'Unable to upload. Please try again later.');
    }
  }

  /// `DELETE /transactions/:id/attachments/:attachment_id`.
  Future<Map<String, dynamic>> delete({
    required String accessToken,
    required String transactionId,
    required String attachmentId,
  }) async {
    try {
      final response = await _client
          .delete(
            _uri('${_attachmentsPath(transactionId)}/'
                '${Uri.encodeComponent(attachmentId)}'),
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(_timeout);
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return apiFailure(response, 'The file could not be deleted');
    } catch (e) {
      return _error('delete', e, 'Unable to delete. Please try again later.');
    }
  }

  /// The file's bytes, fetched with the auth headers. `'bytes'` holds a
  /// [Uint8List].
  Future<Map<String, dynamic>> download({
    required String accessToken,
    required TransactionAttachment attachment,
  }) async {
    try {
      final response = await _client
          .get(fileUri(attachment),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return {'success': true, 'bytes': response.bodyBytes};
      }
      return apiFailure(response, 'The file could not be loaded');
    } catch (e) {
      return _error('download', e, 'Unable to load the file.');
    }
  }

  Map<String, dynamic> _error(String operation, Object error, String message) {
    LogService.instance.error('TransactionAttachmentsService',
        '$operation failed with ${error.runtimeType}');
    return {'success': false, 'error': message};
  }
}

/// The attachment types the server accepts, detected from the file's first
/// bytes (the server checks real bytes, not names): `image/jpeg`,
/// `image/png`, `image/gif`, `image/webp` or `application/pdf`. Null for
/// anything else, HEIC included.
String? attachmentContentType(Uint8List bytes) {
  bool startsWith(List<int> prefix, [int offset = 0]) {
    if (bytes.length < offset + prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(ascii.encode('GIF8'))) return 'image/gif';
  if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
    return 'image/webp';
  }
  if (startsWith(ascii.encode('%PDF-'))) return 'application/pdf';
  return null;
}

/// [filename] with the extension that matches [contentType], so a photo
/// re-encoded to JPEG isn't uploaded as `IMG_1.heic`.
String attachmentFilename(String filename, String contentType) {
  const extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'application/pdf': 'pdf',
  };
  final ext = extensions[contentType] ?? 'bin';
  final name = filename.trim().isEmpty ? 'receipt' : filename.trim();
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final current = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (current == ext || (ext == 'jpg' && current == 'jpeg')) return name;
  return '$stem.$ext';
}
