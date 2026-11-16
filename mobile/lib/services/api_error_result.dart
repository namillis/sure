import 'dart:convert';

import 'package:http/http.dart' as http;

import 'response_list_parser.dart';

/// A failed `{'success': false, ...}` map for [response]: its `'status'`,
/// the server's error key as `'code'` and the message as `'error'`.
Map<String, dynamic> errorResult(http.Response response,
    {required String fallback}) {
  String? code;
  try {
    final data = jsonDecode(response.body);
    if (data is Map && data['error'] is String) code = data['error'];
  } on FormatException {
    // Not JSON; no code.
  }
  return {
    'success': false,
    'status': response.statusCode,
    if (code != null) 'code': code,
    'error': extractErrorMessage(response.body, fallback: fallback),
  };
}
