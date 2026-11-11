import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/screens/statement_upload_screen.dart';
import 'package:sure_mobile/services/account_statements_service.dart';
import 'package:sure_mobile/services/file_pick.dart';
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

Map<String, dynamic> _statement() => {
      'id': 'st_1',
      'filename': 'oct.pdf',
      'byte_size': 2048,
      'period_start_on': '2026-10-01',
      'period_end_on': '2026-10-31',
      'account': {'id': 'acct_1', 'name': 'Checking', 'currency': 'USD'},
      'created_at': '2026-11-01T09:00:00Z',
    };

Future<void> _pump(WidgetTester tester, MockClient client, PickedFileData file) =>
    pumpLocalized(
      tester,
      StatementUploadScreen(
        service: AccountStatementsService(client: client),
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async {},
        accounts: _accounts,
        pickFile: (_) async => file,
      ),
    );

SureButton _upload(WidgetTester tester) => tester.widget<SureButton>(
    find.ancestor(of: find.text('Upload'), matching: find.byType(SureButton)));

void main() {
  testWidgets('lists the account statements and shows a duplicate', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.queryParameters['account_id'], 'acct_1');
        return http.Response(jsonEncode({'data': [_statement()], 'meta': {}}), 200);
      }
      return http.Response(jsonEncode({'data': _statement(), 'meta': {'duplicate': true}}), 200);
    });
    await _pump(tester, client, PickedFileData.bytes('oct.pdf', utf8.encode('%PDF-1.4')));

    expect(find.text('oct.pdf'), findsOneWidget);
    expect(_upload(tester).onPressed, isNull);

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.text('Already uploaded on Nov 1, 2026.'), findsOneWidget);
  });

  testWidgets('shows the server validation error', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'data': [], 'meta': {}}), 200);
      }
      return http.Response(
          jsonEncode({'error': 'validation_failed', 'message': 'file must be a readable .pdf document'}), 422);
    });
    await _pump(tester, client, PickedFileData.bytes('bad.pdf', [1, 2, 3]));

    expect(find.text('No statements for this account yet.'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('file must be a readable .pdf document'), findsOneWidget);
  });

  testWidgets('rejects unsupported types and oversized files', (tester) async {
    final client = MockClient((_) async => http.Response(jsonEncode({'data': [], 'meta': {}}), 200));
    await _pump(tester, client, PickedFileData.bytes('photo.png', [1]));
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a PDF, CSV or XLSX file.'), findsOneWidget);
    expect(_upload(tester).onPressed, isNull);
  });
}
