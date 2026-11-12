import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/screens/categories_screen.dart';
import 'package:sure_mobile/screens/export_screen.dart';
import 'package:sure_mobile/screens/merchants_screen.dart';
import 'package:sure_mobile/screens/tags_screen.dart';
import 'package:sure_mobile/services/family_exports_service.dart';
import 'package:sure_mobile/services/metadata_create_service.dart';
import 'package:sure_mobile/services/metadata_manage_service.dart';

import '../support/l10n_harness.dart';

Future<String?> _token() async => 'token';

/// Like [pumpLocalized] but without pumpAndSettle, for screens with a
/// spinner that never stops (an export in progress).
Future<void> _pumpUnsettled(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: false),
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: SureTheme.light,
        home: child,
      ),
    ),
  );
  await tester.pump(); // post-frame load
  await tester.pump();
}

void main() {
  group('forms validate', () {
    testWidgets('CategoryForm needs a name and sends color and parent',
        (tester) async {
      String? sentName;
      String? sentColor;
      await pumpLocalized(
        tester,
        // The form is its own sheet (toolbar Save), so no scroll wrapper.
        CategoryForm(
          parents: [Category(id: 'c1', name: 'Food')],
          onSubmit: (name, color, parentId) async {
            sentName = name;
            sentColor = color;
            return 'Categories are locked. Unlock them to add a new category.';
          },
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(sentName, isNull);

      await tester.enterText(find.byType(TextFormField).first, ' Pets ');
      await tester.tap(find.bySemanticsLabel('Color 3'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sentName, 'Pets');
      expect(sentColor, kMetadataColors[2]);
      // The server's message is shown as-is.
      expect(find.textContaining('Categories are locked'), findsOneWidget);
    });

    testWidgets('TagForm needs a name; edit shows delete', (tester) async {
      var submitted = false;
      await pumpLocalized(
        tester,
        TagForm(
          onSubmit: (_, __) async {
            submitted = true;
            return null;
          },
          onDelete: () async => null,
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(submitted, false);
      expect(find.text('Delete tag'), findsOneWidget);
    });

    testWidgets('MerchantForm checks the website', (tester) async {
      String? sentWebsite;
      String? sentColor = 'unset';
      await pumpLocalized(
        tester,
        MerchantForm(
          onSubmit: (name, color, website) async {
            sentWebsite = website;
            sentColor = color;
            return null;
          },
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Cafe');
      await tester.enterText(fields.at(1), 'not a site');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a web address like example.com.'), findsOneWidget);
      expect(sentColor, 'unset');

      await tester.enterText(fields.at(1), 'cafe.example');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sentWebsite, 'cafe.example');
      expect(sentColor, isNull); // "Automatic" by default
    });
  });

  test('isPlausibleWebsite', () {
    expect(isPlausibleWebsite('example.com'), true);
    expect(isPlausibleWebsite('https://www.example.com/x'), true);
    expect(isPlausibleWebsite('example'), false);
    expect(isPlausibleWebsite('a b.com'), false);
  });

  testWidgets('CategoriesScreen indents subcategories and searches',
      (tester) async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'categories': [
            {'id': 'c1', 'name': 'Food', 'color': '#e99537', 'parent': null},
            {
              'id': 'c2',
              'name': 'Groceries',
              'color': '#4da568',
              'parent': {'id': 'c1', 'name': 'Food'},
            },
            {'id': 'c3', 'name': 'Travel', 'color': '#6471eb', 'parent': null},
          ],
          'pagination': {'total_pages': 1},
        }),
        200));
    await pumpLocalized(
      tester,
      CategoriesScreen(
        service: MetadataManageService(client: client),
        createService: MetadataCreateService(client: client),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
      ),
    );
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Groceries')).dx,
        greaterThan(tester.getTopLeft(find.text('Food')).dx));

    await tester.enterText(
        find.descendant(
            of: find.byType(SureSearchField), matching: find.byType(TextField)),
        'trav');
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
    expect(find.text('Travel'), findsOneWidget);
  });

  testWidgets('TagsScreen deletes after confirming', (tester) async {
    final requests = <String>[];
    var deleted = false;
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'DELETE') {
        deleted = true;
        return http.Response('', 204);
      }
      return http.Response(
          deleted ? '[]' : '[{"id":"t1","name":"Trip","color":"#4da568"}]',
          200);
    });
    await pumpLocalized(
      tester,
      TagsScreen(
        service: MetadataManageService(client: client),
        createService: MetadataCreateService(client: client),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
      ),
    );
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete tag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('removed from every transaction'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(requests, contains('DELETE /api/v1/tags/t1'));
    expect(find.text('Tag deleted'), findsOneWidget);
    expect(find.text('No tags yet'), findsOneWidget);
  });

  testWidgets('TagsScreen logs out on 401', (tester) async {
    var loggedOut = false;
    await _pumpUnsettled(
      tester,
      TagsScreen(
        service: MetadataManageService(
            client: MockClient((_) async => http.Response('', 401))),
        accessTokenLoader: _token,
        onUnauthorized: () async => loggedOut = true,
      ),
    );
    expect(loggedOut, true);
  });

  group('ExportScreen', () {
    String export(String status) => jsonEncode({
          'id': 'e1',
          'status': status,
          'filename': 'sure_export_20261110_120000.zip',
          'downloadable': status == 'completed',
          'file': {'attached': status == 'completed', 'byte_size': 2048},
          'created_at': '2026-11-10T12:00:00Z',
        });

    testWidgets('polls an in-progress export until it is ready',
        (tester) async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final status = calls < 3 ? 'processing' : 'completed';
        return http.Response('{"data":[${export(status)}]}', 200);
      });
      await _pumpUnsettled(
        tester,
        ExportScreen(
          service: FamilyExportsService(client: client),
          accessTokenLoader: _token,
          onUnauthorized: () async {},
          pollInterval: const Duration(seconds: 1),
          shareFile: (_, __) async {},
        ),
      );
      expect(calls, 1);
      expect(find.textContaining('Preparing'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(calls, 3);
      expect(find.textContaining('Ready'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      // Nothing in flight, so polling stops.
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 3);
    });

    testWidgets('stops polling at the cap', (tester) async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"data":[${export('pending')}]}', 200);
      });
      await _pumpUnsettled(
        tester,
        ExportScreen(
          service: FamilyExportsService(client: client),
          accessTokenLoader: _token,
          onUnauthorized: () async {},
          pollInterval: const Duration(seconds: 1),
          maxPolls: 2,
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(calls, 3); // first load + 2 polls
      expect(find.textContaining('Still preparing'), findsOneWidget);
    });

    testWidgets('a non-admin sees why', (tester) async {
      await pumpLocalized(
        tester,
        ExportScreen(
          service: FamilyExportsService(
            client: MockClient((_) async => http.Response(
                '{"error":"forbidden","message":"Family exports require a family admin"}',
                403)),
          ),
          accessTokenLoader: _token,
          onUnauthorized: () async {},
        ),
      );
      expect(find.text('Only a family admin can export data.'), findsOneWidget);
    });
  });

  test('formatByteSize', () {
    expect(formatByteSize(512), '512 B');
    expect(formatByteSize(2048), '2.0 KB');
    expect(formatByteSize(3 * 1024 * 1024), '3.0 MB');
  });

  group('restyled list states', () {
    MetadataManageService service(http.Response Function() respond) =>
        MetadataManageService(client: MockClient((_) async => respond()));

    Widget screen(String which, MetadataManageService s) => switch (which) {
          'categories' => CategoriesScreen(
              service: s,
              accessTokenLoader: _token,
              onUnauthorized: () async {}),
          'tags' => TagsScreen(
              service: s,
              accessTokenLoader: _token,
              onUnauthorized: () async {}),
          _ => MerchantsScreen(
              service: s,
              accessTokenLoader: _token,
              onUnauthorized: () async {}),
        };

    String emptyBody(String which) => switch (which) {
          'categories' => jsonEncode({
              'categories': [],
              'pagination': {'total_pages': 1}
            }),
          _ => '[]',
        };

    for (final which in ['categories', 'tags', 'merchants']) {
      testWidgets('$which: empty state offers to add one', (tester) async {
        await pumpLocalized(
            tester, screen(which, service(() => http.Response(emptyBody(which), 200))));
        expect(find.byKey(ValueKey('${which}Empty')), findsOneWidget);
        expect(find.byType(SureEmptyState), findsOneWidget);
        expect(find.byType(SureLargeTitleHeader), findsOneWidget);
      });

      testWidgets('$which: load failure shows an error state that retries',
          (tester) async {
        var calls = 0;
        await pumpLocalized(
            tester,
            screen(
                which,
                service(() {
                  calls++;
                  return http.Response('{}', 500);
                })));
        final error = find.byKey(ValueKey('${which}Error'));
        expect(error, findsOneWidget);
        final before = calls;
        await tester.tap(find.descendant(of: error, matching: find.text('Try Again')));
        await tester.pumpAndSettle();
        expect(calls, greaterThan(before));
      });
    }

    testWidgets('categories show SureCategoryIcon and a no-match state',
        (tester) async {
      await pumpLocalized(
        tester,
        screen(
            'categories',
            service(() => http.Response(
                jsonEncode({
                  'categories': [
                    {
                      'id': 'c1',
                      'name': 'Food',
                      'color': '#e99537',
                      'icon': 'utensils',
                      'parent': null
                    },
                  ],
                  'pagination': {'total_pages': 1},
                }),
                200))),
      );
      final icon = tester.widget<SureCategoryIcon>(find.byType(SureCategoryIcon));
      expect(icon.icon, 'utensils');
      expect(icon.color, '#e99537');

      await tester.enterText(
          find.descendant(
              of: find.byType(SureSearchField), matching: find.byType(TextField)),
          'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches “zzz”.'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('opened from Settings, the back link reads Settings',
        (tester) async {
      await pumpLocalized(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    screen('tags', service(() => http.Response('[]', 200))))),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(SureBackButton), matching: find.text('Settings')),
          findsOneWidget);
    });

    testWidgets('the tag form is a sheet with Save in the toolbar and swatches',
        (tester) async {
      await pumpLocalized(
        tester,
        screen('tags',
            service(() => http.Response('[{"id":"t1","name":"Trip","color":"#4da568"}]', 200))),
      );
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SureSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Edit tag')), findsOneWidget);
      expect(find.byKey(const ValueKey('tagFormSave')), findsOneWidget);
      expect(find.bySemanticsLabel('Color 1'), findsOneWidget);
      expect(find.widgetWithText(SureButtonPanel, 'Delete tag'), findsOneWidget);
    });
  });

  testWidgets('ExportScreen shows an empty state with no exports',
      (tester) async {
    await pumpLocalized(
      tester,
      ExportScreen(
        service: FamilyExportsService(
            client: MockClient((_) async => http.Response('{"data":[]}', 200))),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
      ),
    );
    expect(find.byKey(const ValueKey('exportEmpty')), findsOneWidget);
    expect(find.text('No exports yet'), findsOneWidget);
    expect(find.text('Create export'), findsOneWidget);
  });
}
