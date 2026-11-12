import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/categories_screen.dart';
import 'package:sure_mobile/screens/export_screen.dart';
import 'package:sure_mobile/screens/import_screen.dart';
import 'package:sure_mobile/screens/merchants_screen.dart';
import 'package:sure_mobile/screens/statement_upload_screen.dart';
import 'package:sure_mobile/screens/tags_screen.dart';
import 'package:sure_mobile/services/account_statements_service.dart';
import 'package:sure_mobile/services/family_exports_service.dart';
import 'package:sure_mobile/services/file_pick.dart';
import 'package:sure_mobile/services/imports_service.dart';
import 'package:sure_mobile/services/metadata_manage_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

/// The Settings -> Data screens at 320 px, in Swedish, light and dark: a
/// layout overflow fails the test.

final _accounts = [
  Account.fromJson({
    'id': 'acct_1',
    'name': 'Ett mycket långt kontonamn för lönekontot',
    'balance': r'$1,000.00',
    'currency': 'USD',
    'classification': 'asset',
    'account_type': 'depository',
  }),
];

Future<void> _pump(WidgetTester tester, Widget child, {required bool dark}) async {
  tester.view.physicalSize = const Size(320 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: false),
      child: MaterialApp(
        theme: dark ? SureTheme.dark : SureTheme.light,
        locale: const Locale('sv'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MockClient _importServer() => MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/imports/preflight') {
        return http.Response(
          jsonEncode({
            'data': {
              'valid': true,
              'headers': ['Date', 'Amount', 'Description'],
              'stats': {'rows_count': 2},
              'errors': [],
              'warnings': ['A rather long warning from the server about the file.'],
            },
          }),
          200,
        );
      }
      return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'imp_1',
                'type': 'TransactionImport',
                'status': 'revert_failed',
                'created_at': '2026-11-10T12:00:00Z',
                'rows_count': 12345,
              }
            ],
            'meta': {},
          }),
          200);
    });

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('import wizard fits ($mode)', (tester) async {
      await _pump(
        tester,
        ImportScreen(
          service: ImportsService(client: _importServer()),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          accounts: _accounts,
          pickFile: (_) async => PickedFileData.bytes(
              'ett-valdigt-langt-filnamn-fran-banken-2026.csv',
              utf8.encode('Date,Amount,Description\n'
                  '2026-11-01,-12.50,En mycket lång beskrivning av ett köp\n'
                  '2026-13-45,abc,Trasig\n')),
        ),
        dark: dark,
      );
      await tester.tap(find.text('Välj CSV-fil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fortsätt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Steg 2 av 4'), findsOneWidget);
      await tester.ensureVisible(find.text('Fortsätt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fortsätt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Steg 3 av 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('statement upload fits ($mode)', (tester) async {
      await _pump(
        tester,
        StatementUploadScreen(
          service: AccountStatementsService(
            client: MockClient((_) async => http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'st_1',
                      'filename': 'kontoutdrag-oktober-2026-lonekonto.pdf',
                      'period_start_on': '2026-10-01',
                      'period_end_on': '2026-10-31',
                      'created_at': '2026-11-01T09:00:00Z',
                    }
                  ],
                  'meta': {},
                }),
                200)),
          ),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          accounts: _accounts,
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists and forms fit ($mode)', (tester) async {
      final categories = MetadataManageService(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'categories': [
                {'id': 'c1', 'name': 'Mat och dryck på restaurang', 'color': '#e99537', 'icon': 'utensils', 'parent': null},
                {
                  'id': 'c2',
                  'name': 'Livsmedel och hushållsartiklar',
                  'color': '#4da568',
                  'parent': {'id': 'c1', 'name': 'Mat'},
                },
              ],
              'pagination': {'total_pages': 1},
            }),
            200)),
      );
      await _pump(
        tester,
        CategoriesScreen(
            service: categories,
            accessTokenLoader: () async => 'token',
            onUnauthorized: () async {}),
        dark: dark,
      );
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        CategoryForm(
          parents: [Category(id: 'c1', name: 'Mat och dryck på restaurang')],
          onSubmit: (_, __, ___) async => null,
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        TagsScreen(
          service: MetadataManageService(
              client: MockClient((_) async => http.Response(
                  '[{"id":"t1","name":"Semesterresa till Norrland","color":"#4da568"}]',
                  200))),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
        ),
        dark: dark,
      );
      await tester.tap(find.text('Semesterresa till Norrland'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _pump(tester, MerchantForm(onSubmit: (_, __, ___) async => null),
          dark: dark);
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        MerchantsScreen(
          service: MetadataManageService(
              client: MockClient((_) async => http.Response(
                  '[{"id":"m1","name":"Ett riktigt långt handlarnamn AB","type":"ProviderMerchant"}]',
                  200))),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('export fits ($mode)', (tester) async {
      await _pump(
        tester,
        ExportScreen(
          service: FamilyExportsService(
            client: MockClient((_) async => http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'e1',
                      'status': 'completed',
                      'filename': 'sure_export.zip',
                      'downloadable': true,
                      'file': {'attached': true, 'byte_size': 123456789},
                      'created_at': '2026-11-10T12:00:00Z',
                    }
                  ],
                }),
                200)),
          ),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
        ),
        dark: dark,
      );
      expect(find.text('Ladda ned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
