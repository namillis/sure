import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account_statement.dart';
import 'package:sure_mobile/services/account_statements_service.dart';

Map<String, dynamic> statementJson({String id = 'st_1', String filename = 'oct.pdf'}) => {
      'id': id,
      'filename': filename,
      'content_type': 'application/pdf',
      'byte_size': 2048,
      'content_sha256': 'abc',
      'review_status': 'unreviewed',
      'period_start_on': '2026-10-01',
      'period_end_on': '2026-10-31',
      'currency': 'USD',
      'opening_balance': null,
      'closing_balance': null,
      'institution_name_hint': null,
      'account_last4_hint': null,
      'account': {'id': 'acct_1', 'name': 'Checking', 'currency': 'USD'},
      'suggested_account': null,
      'match_confidence': null,
      'created_at': '2026-11-01T09:00:00Z',
      'updated_at': '2026-11-01T09:00:00Z',
    };

void main() {
  group('AccountStatementsService', () {
    test('list filters by account and parses statements', () async {
      final service = AccountStatementsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/account_statements');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
              jsonEncode({'data': [statementJson()], 'meta': {'page': 1, 'per_page': 25, 'total_count': 1, 'total_pages': 1}}),
              200);
        }),
      );

      final result = await service.list(accessToken: 'token', accountId: 'acct_1');
      final statements = (result['statements'] as List).cast<AccountStatement>();
      expect(statements.single.filename, 'oct.pdf');
      expect(statements.single.accountName, 'Checking');
      expect(statements.single.periodEnd, DateTime(2026, 10, 31));
      expect(statements.single.byteSize, 2048);
    });

    test('upload sends multipart file, content type and account_id', () async {
      late http.Request sent;
      final service = AccountStatementsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'data': statementJson(), 'meta': {'duplicate': false}}), 201);
        }),
      );

      final result = await service.upload(
          accessToken: 'token', bytes: utf8.encode('%PDF-1.4 x'), filename: 'Oct.PDF', accountId: 'acct_1');

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/account_statements');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      final body = utf8.decode(sent.bodyBytes);
      expect(body, contains('name="file"; filename="Oct.PDF"'));
      expect(body, contains('content-type: application/pdf'));
      expect(body, contains('name="account_id"\r\n\r\nacct_1'));
      expect(result['success'], true);
      expect(result['duplicate'], false);
      expect((result['statement'] as AccountStatement).id, 'st_1');
    });

    test('xlsx gets the spreadsheet content type; no account omits the field', () async {
      late http.Request sent;
      final service = AccountStatementsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'data': statementJson(), 'meta': {'duplicate': false}}), 201);
        }),
      );
      await service.upload(accessToken: 't', bytes: [1, 2, 3], filename: 'a.xlsx');
      final body = utf8.decode(sent.bodyBytes, allowMalformed: true);
      expect(body, contains('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
      expect(body, isNot(contains('name="account_id"')));
    });

    test('a visible duplicate is 200 with meta.duplicate', () async {
      final service = AccountStatementsService(
        client: MockClient((_) async =>
            http.Response(jsonEncode({'data': statementJson(), 'meta': {'duplicate': true}}), 200)),
      );
      final result = await service.upload(accessToken: 't', bytes: [1], filename: 'a.pdf');
      expect(result['success'], true);
      expect(result['duplicate'], true);
      expect((result['statement'] as AccountStatement).createdAt, DateTime.utc(2026, 11, 1, 9));
    });

    test('a hidden duplicate is 409 with code duplicate', () async {
      final service = AccountStatementsService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'duplicate', 'message': 'This file is already in the Statement Vault'}), 409)),
      );
      final result = await service.upload(accessToken: 't', bytes: [1], filename: 'a.pdf');
      expect(result['success'], false);
      expect(result['code'], 'duplicate');
      expect(result['error'], 'This file is already in the Statement Vault');
    });

    test('422 validation error and 401', () async {
      final service = AccountStatementsService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'validation_failed', 'message': 'file must be a readable .pdf, .csv, .xlsx document'}), 422)),
      );
      final result = await service.upload(accessToken: 't', bytes: [1], filename: 'a.pdf');
      expect(result['status'], 422);
      expect(result['error'], contains('readable'));

      final unauthorized = AccountStatementsService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect((await unauthorized.upload(accessToken: 't', bytes: [1], filename: 'a.pdf'))['error'], 'unauthorized');
      expect((await unauthorized.list(accessToken: 't'))['error'], 'unauthorized');
    });
  });
}
