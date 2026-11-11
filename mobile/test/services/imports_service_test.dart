import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/data_import.dart';
import 'package:sure_mobile/services/imports_service.dart';

Map<String, dynamic> importJson({
  String id = 'imp_1',
  String status = 'pending',
  bool terminal = false,
  int rows = 2,
}) =>
    {
      'id': id,
      'type': 'TransactionImport',
      'status': status,
      'created_at': '2026-11-10T12:00:00Z',
      'updated_at': '2026-11-10T12:00:00Z',
      'account_id': 'acct_1',
      'rows_count': rows,
      'status_detail': {'uploaded': true, 'configured': true, 'terminal': terminal},
    };

/// The decoded text of a multipart body.
String bodyText(http.Request request) => utf8.decode(request.bodyBytes);

/// The value of form field [name] in a multipart body.
String? formField(http.Request request, String name) {
  final match = RegExp('name="$name"\\r\\n\\r\\n([^\\r]*)\\r\\n')
      .firstMatch(bodyText(request));
  return match?.group(1);
}

void main() {
  const csv = 'Date,Amount,Description\n11/01/2026,-12.50,Coffee\n';

  group('ImportsService', () {
    test('list sends paging and parses imports', () async {
      final service = ImportsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/imports');
          expect(request.url.queryParameters, {'page': '1', 'per_page': '25'});
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({
              'data': [
                importJson(status: 'complete', terminal: true, rows: 40),
                {...importJson(id: 'imp_2', status: 'failed'), 'error': 'Bad date'},
              ],
              'meta': {'current_page': 1, 'total_pages': 1},
            }),
            200,
          );
        }),
      );

      final result = await service.list(accessToken: 'token');

      expect(result['success'], true);
      final imports = (result['imports'] as List).cast<DataImport>();
      expect(imports.first.isComplete, true);
      expect(imports.first.rowsCount, 40);
      expect(imports.first.terminal, true);
      expect(imports.first.createdAt, DateTime.utc(2026, 11, 10, 12));
      expect(imports[1].isFailed, true);
      expect(imports[1].error, 'Bad date');
    });

    test('401 is unauthorized', () async {
      final service = ImportsService(
          client: MockClient((_) async => http.Response('{"error":"unauthorized"}', 401)));
      expect((await service.list(accessToken: 't'))['error'], 'unauthorized');
      expect((await service.show(accessToken: 't', id: 'x'))['error'], 'unauthorized');
      expect(
          (await service.preflight(accessToken: 't', csv: utf8.encode(csv), filename: 'a.csv'))['error'],
          'unauthorized');
      expect(
          (await service.create(
                  accessToken: 't', csv: utf8.encode(csv), filename: 'a.csv', accountId: 'a'))['error'],
          'unauthorized');
    });

    test('preflight posts the CSV as multipart with config params', () async {
      late http.Request sent;
      final service = ImportsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'data': {
                'type': 'TransactionImport',
                'valid': false,
                'content': {'filename': 'bank.csv', 'content_type': 'text/csv', 'byte_size': 50},
                'stats': {'rows_count': 1},
                'headers': ['Date', 'Amount', 'Description'],
                'required_headers': ['date', 'amount'],
                'missing_required_headers': ['date'],
                'errors': [
                  {'code': 'missing_required_headers', 'message': 'Missing required columns: date'},
                ],
                'warnings': ['Row count exceeds this import type\'s publish limit.'],
              },
            }),
            200,
          );
        }),
      );

      final result = await service.preflight(
        accessToken: 'token',
        csv: utf8.encode(csv),
        filename: 'bank.csv',
        accountId: 'acct_1',
        config: {'col_sep': ';'},
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/imports/preflight');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(formField(sent, 'type'), 'TransactionImport');
      expect(formField(sent, 'account_id'), 'acct_1');
      expect(formField(sent, 'col_sep'), ';');
      final body = bodyText(sent);
      expect(body, contains('name="file"; filename="bank.csv"'));
      expect(body, contains('content-type: text/csv'));
      expect(body, contains('11/01/2026,-12.50,Coffee'));

      final preflight = result['preflight'] as ImportPreflight;
      expect(preflight.valid, false);
      expect(preflight.headers, ['Date', 'Amount', 'Description']);
      expect(preflight.missingRequiredHeaders, ['date']);
      expect(preflight.errors, ['Missing required columns: date']);
      expect(preflight.warnings, hasLength(1));
      expect(preflight.rowsCount, 1);
    });

    test('preflight 422 returns the server message', () async {
      final service = ImportsService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'invalid_csv', 'message': 'CSV content could not be parsed', 'errors': ['Unclosed quoted field']}),
            422)),
      );
      final result = await service.preflight(
          accessToken: 't', csv: utf8.encode(csv), filename: 'a.csv');
      expect(result['success'], false);
      expect(result['error'], 'Unclosed quoted field');
      expect(result['code'], 'invalid_csv');
      expect(result['status'], 422);
    });

    test('create sends the mapping, account and publish=true', () async {
      late http.Request sent;
      final service = ImportsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'data': importJson(status: 'importing')}), 201);
        }),
      );

      final result = await service.create(
        accessToken: 'token',
        csv: utf8.encode(csv),
        filename: 'bank.csv',
        accountId: 'acct_1',
        config: {
          'date_col_label': 'Date',
          'amount_col_label': 'Amount',
          'name_col_label': 'Description',
          'date_format': '%m/%d/%Y',
          'number_format': '1,234.56',
          'signage_convention': 'inflows_positive',
          'col_sep': ',',
        },
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/imports');
      expect(formField(sent, 'type'), 'TransactionImport');
      expect(formField(sent, 'account_id'), 'acct_1');
      expect(formField(sent, 'publish'), 'true');
      expect(formField(sent, 'date_col_label'), 'Date');
      expect(formField(sent, 'amount_col_label'), 'Amount');
      expect(formField(sent, 'name_col_label'), 'Description');
      expect(formField(sent, 'date_format'), '%m/%d/%Y');
      expect(formField(sent, 'signage_convention'), 'inflows_positive');
      expect(bodyText(sent), contains('filename="bank.csv"'));
      expect((result['import'] as DataImport).status, 'importing');
    });

    test('create without publish omits the flag; 422 lists errors', () async {
      late http.Request sent;
      final service = ImportsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
              jsonEncode({'error': 'validation_failed', 'message': 'Import could not be created', 'errors': ['Col sep is not included in the list']}),
              422);
        }),
      );
      final result = await service.create(
          accessToken: 't', csv: utf8.encode(csv), filename: 'a.csv', accountId: 'a', publish: false);
      expect(formField(sent, 'publish'), isNull);
      expect(result['success'], false);
      expect(result['error'], 'Col sep is not included in the list');
    });

    test('rows parses fields and row errors', () async {
      final service = ImportsService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/imports/imp_1/rows');
          expect(request.url.queryParameters['per_page'], '20');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'r1',
                  'row_number': 1,
                  'valid': true,
                  'errors': [],
                  'fields': {'date': '11/01/2026', 'amount': '-12.50', 'name': 'Coffee', 'category': '', 'tags': '', 'notes': ''},
                  'mappings': {},
                },
                {
                  'id': 'r2',
                  'row_number': 2,
                  'valid': false,
                  'errors': ['Date is not a valid date'],
                  'fields': {'date': '31/31/2026', 'amount': '5', 'name': 'Bad'},
                  'mappings': {},
                },
              ],
              'meta': {'current_page': 1},
            }),
            200,
          );
        }),
      );

      final result = await service.rows(accessToken: 't', id: 'imp_1');
      final rows = (result['rows'] as List).cast<DataImportRow>();
      expect(rows.first.valid, true);
      expect(rows.first.name, 'Coffee');
      expect(rows.first.category, isNull);
      expect(rows[1].valid, false);
      expect(rows[1].errors, ['Date is not a valid date']);
      expect(rows[1].rowNumber, 2);
    });

    test('waitForCompletion polls until complete', () async {
      final statuses = ['importing', 'importing', 'complete'];
      var calls = 0;
      final sleeps = <Duration>[];
      final service = ImportsService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/imports/imp_1');
          final status = statuses[calls++];
          return http.Response(
              jsonEncode({'data': importJson(status: status, terminal: status == 'complete')}), 200);
        }),
      );

      final result = await service.waitForCompletion(
        accessToken: 't',
        id: 'imp_1',
        clock: () => DateTime(2026, 11, 10),
        sleep: (d) async => sleeps.add(d),
      );

      expect(calls, 3);
      expect(sleeps, [const Duration(seconds: 3), const Duration(seconds: 3)]);
      expect(result['timedOut'], false);
      expect((result['import'] as DataImport).isComplete, true);
    });

    test('waitForCompletion stops at the cap on an injected clock', () async {
      var now = DateTime(2026, 11, 10, 12);
      var calls = 0;
      final service = ImportsService(
        client: MockClient((_) async {
          calls++;
          return http.Response(jsonEncode({'data': importJson(status: 'importing')}), 200);
        }),
      );

      final result = await service.waitForCompletion(
        accessToken: 't',
        id: 'imp_1',
        timeout: const Duration(minutes: 2),
        clock: () => now,
        sleep: (d) async => now = now.add(const Duration(seconds: 30)),
      );

      expect(result['timedOut'], true);
      expect(calls, 5); // t = 0, 30, 60, 90, 120 s
      expect((result['import'] as DataImport).inProgress, true);
    });

    test('waitForCompletion stops when cancelled and on a failed status', () async {
      final service = ImportsService(
        client: MockClient((_) async =>
            http.Response(jsonEncode({'data': importJson(status: 'importing')}), 200)),
      );
      final cancelled = await service.waitForCompletion(
          accessToken: 't', id: 'imp_1', cancelled: () => true, sleep: (_) async {});
      expect(cancelled['cancelled'], true);

      final failing = ImportsService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'data': {...importJson(status: 'failed', terminal: true), 'error': 'Boom'}}), 200)),
      );
      final failed = await failing.waitForCompletion(accessToken: 't', id: 'imp_1');
      expect((failed['import'] as DataImport).error, 'Boom');
      expect((failed['import'] as DataImport).isFailed, true);
    });
  });
}
