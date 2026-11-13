import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/categories_screen.dart';
import 'package:sure_mobile/services/metadata_create_service.dart';
import 'package:sure_mobile/services/metadata_manage_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Future<String?> _token() async => 'token';

final _categories = {
  'categories': [
    {'id': 'c1', 'name': 'Food', 'color': '#e99537', 'parent': null},
    {
      'id': 'c2',
      'name': 'Groceries',
      'color': '#e99537',
      'parent': {'id': 'c1', 'name': 'Food'},
    },
    {'id': 'c3', 'name': 'Travel', 'color': '#6471eb', 'parent': null},
  ],
  'pagination': {'total_pages': 1},
};

/// The requests the screen made, as "METHOD path?query" plus bodies.
class _Recorder {
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
}

Future<_Recorder> _pump(
  WidgetTester tester, {
  required bool feature,
  http.Response Function(http.Request request)? onWrite,
}) async {
  final recorder = _Recorder();
  final client = MockClient((request) async {
    if (request.method == 'GET') return http.Response(jsonEncode(_categories), 200);
    recorder.requests.add('${request.method} ${request.url.path}'
        '${request.url.hasQuery ? '?${request.url.query}' : ''}');
    if (request.body.isNotEmpty) {
      recorder.bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return onWrite?.call(request) ??
        (request.method == 'DELETE'
            ? http.Response('', 204)
            : http.Response(
                jsonEncode({'id': 'c2', 'name': 'Groceries', 'parent': null}),
                200));
  });
  final features = ServerFeaturesProvider()
    ..debugSet(feature ? {ServerFeaturesProvider.categoriesWrite} : {});
  await pumpLocalized(
    tester,
    ChangeNotifierProvider<ServerFeaturesProvider>.value(
      value: features,
      child: CategoriesScreen(
        service: MetadataManageService(client: client),
        createService: MetadataCreateService(client: client),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
      ),
    ),
  );
  return recorder;
}

void main() {
  testWidgets('without categories.write a row opens the info sheet',
      (tester) async {
    await _pump(tester, feature: false);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    expect(find.text('Edit on the web'), findsOneWidget);
    expect(find.text('Edit category'), findsNothing);
  });

  testWidgets('edits a subcategory and moves it to the top level',
      (tester) async {
    final recorder = await _pump(tester, feature: true);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Edit category'), findsOneWidget);
    expect(find.text('Edit on the web'), findsNothing);
    final name = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(name).controller!.text, 'Groceries');
    // Prefilled parent.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('categoryFormParent')),
            matching: find.text('Food')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('categoryFormParent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None (top level)').last);
    await tester.pumpAndSettle();
    await tester.enterText(name, 'Food shop');
    await tester.tap(find.byKey(const ValueKey('categoryFormSave')));
    await tester.pumpAndSettle();

    expect(recorder.requests, ['PATCH /api/v1/categories/c2']);
    expect(recorder.bodies.single['category'],
        {'name': 'Food shop', 'color': '#e99537', 'parent_id': ''});
    expect(find.text('Category saved'), findsOneWidget);
  });

  testWidgets('a parent with subcategories has no parent picker',
      (tester) async {
    await _pump(tester, feature: true);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Edit category'), findsOneWidget);
    expect(find.byKey(const ValueKey('categoryFormParent')), findsNothing);
  });

  testWidgets('delete asks where the transactions go', (tester) async {
    final recorder = await _pump(tester, feature: true);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('categoryFormDelete')));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Food”?'), findsOneWidget);
    expect(find.text('Its subcategory becomes a top-level category.'),
        findsOneWidget);
    expect(find.text('Leave uncategorized'), findsOneWidget);
    // Every other category, subcategories by their full name.
    expect(find.text('Food > Groceries'), findsOneWidget);
    await tester.tap(find.text('Travel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('categoryDeleteConfirm')));
    await tester.pumpAndSettle();

    expect(recorder.requests,
        ['DELETE /api/v1/categories/c1?replacement_category_id=c3']);
    expect(find.text('Category deleted'), findsOneWidget);
    expect(find.byType(SureSheet), findsNothing);
  });

  testWidgets('delete can leave transactions uncategorized', (tester) async {
    final recorder = await _pump(tester, feature: true);
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('categoryFormDelete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('top-level category'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('categoryDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(recorder.requests, ['DELETE /api/v1/categories/c3']);
  });

  testWidgets('shows the server message and the read-only scope inline',
      (tester) async {
    var scope = false;
    await _pump(tester, feature: true, onWrite: (_) {
      if (scope) {
        return http.Response(
            jsonEncode({
              'error': 'insufficient_scope',
              'message': "This action requires the 'read_write' scope"
            }),
            403);
      }
      return http.Response(
          jsonEncode({
            'error': 'unprocessable_entity',
            'message': 'Name has already been taken'
          }),
          422);
    });
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('categoryFormSave')));
    await tester.pumpAndSettle();
    expect(find.text('Name has already been taken'), findsOneWidget);

    scope = true;
    await tester.tap(find.byKey(const ValueKey('categoryFormSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('can only view data'), findsOneWidget);
    expect(find.byType(SureSheet), findsOneWidget);
  });
}
