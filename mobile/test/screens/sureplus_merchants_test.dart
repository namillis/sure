import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/merchants_screen.dart';
import 'package:sure_mobile/services/metadata_create_service.dart';
import 'package:sure_mobile/services/metadata_manage_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Future<String?> _token() async => 'token';

const _merchants = [
  {
    'id': 'm1',
    'name': 'Corner Cafe',
    'type': 'FamilyMerchant',
    'color': '#4da568',
    'website_url': 'cafe.example',
  },
  {'id': 'm2', 'name': 'Amazon', 'type': 'ProviderMerchant'},
];

Future<List<String>> _pump(
  WidgetTester tester, {
  required bool feature,
  List<Map<String, dynamic>>? bodies,
}) async {
  final requests = <String>[];
  final client = MockClient((request) async {
    if (request.method == 'GET') return http.Response(jsonEncode(_merchants), 200);
    requests.add('${request.method} ${request.url.path}');
    if (request.body.isNotEmpty) {
      bodies?.add(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return request.method == 'DELETE'
        ? http.Response('', 204)
        : http.Response(jsonEncode(_merchants.first), 200);
  });
  final features = ServerFeaturesProvider()
    ..debugSet(feature ? {ServerFeaturesProvider.merchantsWrite} : {});
  await pumpLocalized(
    tester,
    ChangeNotifierProvider<ServerFeaturesProvider>.value(
      value: features,
      child: MerchantsScreen(
        service: MetadataManageService(client: client),
        createService: MetadataCreateService(client: client),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
      ),
    ),
  );
  return requests;
}

void main() {
  testWidgets('without merchants.write a family merchant opens the info sheet',
      (tester) async {
    await _pump(tester, feature: false);
    await tester.tap(find.text('Corner Cafe'));
    await tester.pumpAndSettle();
    expect(find.text('Edit on the web'), findsOneWidget);
    expect(find.text('Edit merchant'), findsNothing);
  });

  testWidgets('a provider merchant stays read-only', (tester) async {
    await _pump(tester, feature: true);
    await tester.tap(find.text('Amazon'));
    await tester.pumpAndSettle();
    expect(find.text('Edit merchant'), findsNothing);
    expect(find.text('Delete merchant'), findsNothing);
  });

  testWidgets('edits a family merchant, prefilled from the list',
      (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final requests = await _pump(tester, feature: true, bodies: bodies);
    await tester.tap(find.text('Corner Cafe'));
    await tester.pumpAndSettle();

    expect(find.text('Edit merchant'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'Corner Cafe');
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'cafe.example');
    // No "Automatic" swatch for an existing merchant.
    expect(find.bySemanticsLabel('Automatic'), findsNothing);

    await tester.enterText(fields.at(0), 'Corner Café');
    await tester.enterText(fields.at(1), '');
    await tester.tap(find.byKey(const ValueKey('merchantFormSave')));
    await tester.pumpAndSettle();

    expect(requests, ['PATCH /api/v1/merchants/m1']);
    expect(bodies.single['merchant'], {
      'name': 'Corner Café',
      'color': '#4da568',
      'website_url': '',
    });
    expect(find.text('Merchant saved'), findsOneWidget);
  });

  testWidgets('deletes a family merchant after confirming', (tester) async {
    final requests = await _pump(tester, feature: true);
    await tester.tap(find.text('Corner Cafe'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('merchantFormDelete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Corner Cafe”?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(requests, ['DELETE /api/v1/merchants/m1']);
    expect(find.text('Merchant deleted'), findsOneWidget);
    expect(find.byType(SureSheet), findsNothing);
  });
}
