import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/screens/import_screen.dart';
import 'package:sure_mobile/services/file_pick.dart';
import 'package:sure_mobile/services/imports_service.dart';
import 'package:sure_mobile/widgets/sure_button.dart';

import '../support/l10n_harness.dart';

final _accounts = [
  Account.fromJson({
    'id': 'acct_1',
    'name': 'Checking',
    'balance': r'$1,000.00',
    'currency': 'USD',
    'classification': 'asset',
    'account_type': 'depository',
  }),
];

Map<String, dynamic> _import(String status, {bool terminal = false}) => {
      'id': 'imp_1',
      'type': 'TransactionImport',
      'status': status,
      'created_at': '2026-11-10T12:00:00Z',
      'rows_count': 2,
      'status_detail': {'terminal': terminal},
    };

/// A fake server. [headers] are what preflight reports; show returns
/// [showStatuses] in turn.
MockClient _server({
  required List<String> headers,
  List<String> showStatuses = const ['complete'],
  List<http.Request>? creates,
}) {
  var shows = 0;
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/v1/imports') {
      return http.Response(jsonEncode({'data': [], 'meta': {}}), 200);
    }
    if (path == '/api/v1/imports/preflight') {
      return http.Response(
        jsonEncode({
          'data': {
            'valid': true,
            'headers': headers,
            'stats': {'rows_count': 2},
            'errors': [],
            'warnings': [],
          },
        }),
        200,
      );
    }
    if (request.method == 'POST' && path == '/api/v1/imports') {
      creates?.add(request);
      return http.Response(jsonEncode({'data': _import('importing')}), 201);
    }
    if (path == '/api/v1/imports/imp_1') {
      final status = showStatuses[shows < showStatuses.length ? shows++ : showStatuses.length - 1];
      return http.Response(
          jsonEncode({'data': _import(status, terminal: status == 'complete')}), 200);
    }
    return http.Response('{}', 404);
  });
}

SureButton _button(WidgetTester tester, String label) => tester.widget<SureButton>(
    find.ancestor(of: find.text(label), matching: find.byType(SureButton)).first);

Future<void> _pump(WidgetTester tester, MockClient client, String csv) =>
    pumpLocalized(
      tester,
      logicalHeight: 2400,
      ImportScreen(
        service: ImportsService(client: client),
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async {},
        accounts: _accounts,
        pickFile: (_) async => PickedFileData.bytes('bank.csv', utf8.encode(csv)),
        clock: () => DateTime(2026, 11, 10),
        sleep: (_) async {},
      ),
    );

void main() {
  testWidgets('cannot continue past mapping without date and amount', (tester) async {
    await _pump(tester, _server(headers: ['Col A', 'Col B']), 'Col A,Col B\nx,y\n');

    expect(find.text('No imports yet.'), findsOneWidget);
    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    expect(find.text('bank.csv'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4: Map columns'), findsOneWidget);
    expect(find.text('Choose the date and amount columns to continue.'), findsOneWidget);
    expect(_button(tester, 'Continue').onPressed, isNull);
  });

  testWidgets('rejects a file over the 10 MB limit before upload', (tester) async {
    await pumpLocalized(
      tester,
      ImportScreen(
        service: ImportsService(client: _server(headers: const [])),
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async {},
        accounts: _accounts,
        pickFile: (_) async => PickedFileData(
          name: 'big.csv',
          size: 11 * 1024 * 1024,
          read: () async => throw StateError('must not read'),
        ),
      ),
    );
    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    expect(find.text('This file is too large. The limit is 10.0 MB.'), findsOneWidget);
    expect(_button(tester, 'Continue').onPressed, isNull);
  });

  testWidgets('prefilled mapping previews rows and publishes', (tester) async {
    final creates = <http.Request>[];
    await _pump(
      tester,
      _server(
        headers: ['Date', 'Amount', 'Description'],
        showStatuses: ['importing', 'complete'],
        creates: creates,
      ),
      'Date,Amount,Description\n2026-11-01,-12.50,Coffee\n2026-11-02,abc,Broken\n',
    );

    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(_button(tester, 'Continue').onPressed, isNotNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4: Preview'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Amount "abc" isn\'t a number.'), findsOneWidget);
    expect(find.text('1 row doesn\'t match the chosen formats.'), findsOneWidget);

    await tester.tap(find.widgetWithText(SureButton, 'Import').last);
    await tester.pumpAndSettle();

    expect(find.text('Import complete'), findsOneWidget);
    final body = utf8.decode(creates.single.bodyBytes);
    expect(body, contains('name="date_col_label"\r\n\r\nDate'));
    expect(body, contains('name="date_format"\r\n\r\n%Y-%m-%d'));
    expect(body, contains('name="publish"\r\n\r\ntrue'));
    expect(body, contains('name="account_id"\r\n\r\nacct_1'));
  });

  testWidgets('history lists imports and opens a status sheet', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/imports') {
        return http.Response(
            jsonEncode({'data': [_import('complete', terminal: true)], 'meta': {}}), 200);
      }
      return http.Response(
          jsonEncode({'data': {..._import('complete', terminal: true), 'stats': {'rows_count': 2, 'invalid_rows_count': 0}}}),
          200);
    });
    await pumpLocalized(
      tester,
      ImportScreen(
        service: ImportsService(client: client),
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async {},
        accounts: _accounts,
      ),
    );
    expect(find.text('Import history'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.textContaining('Complete · 2 rows'), findsOneWidget);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Complete'), findsOneWidget);
  });
}
