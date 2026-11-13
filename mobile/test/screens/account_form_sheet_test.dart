import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/screens/account_form_sheet.dart';
import 'package:sure_mobile/services/accounts_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/metadata_picker_sheet.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _accountJson({
  String id = 'new1',
  String name = 'New',
  String type = 'depository',
  String classification = 'asset',
}) =>
    {
      'id': id,
      'name': name,
      'balance': r'$1,500.00',
      'balance_cents': 150000,
      'currency': 'USD',
      'classification': classification,
      'account_type': type,
    };

final _checking = Account(
  id: 'chk',
  name: 'Checking',
  balance: r'$1,500.00',
  balanceCents: 150000,
  currency: 'USD',
  classification: 'asset',
  accountType: 'depository',
  subtype: 'checking',
  institutionName: 'Ally',
);

class _Harness {
  final requests = <http.Request>[];
  final results = <AccountFormResult?>[];
  http.Response Function(http.Request request)? reply;

  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;

  AccountsService service() => AccountsService(
        client: MockClient((request) async {
          requests.add(request);
          final custom = reply;
          if (custom != null) return custom(request);
          if (request.method == 'DELETE') {
            return http.Response(
                jsonEncode({'id': 'chk', 'message': 'Account scheduled for deletion'}),
                202);
          }
          return http.Response(jsonEncode(_accountJson()),
              request.method == 'POST' ? 201 : 200);
        }),
      );

  Future<void> open(
    WidgetTester tester, {
    Account? account,
    String? initialType,
  }) async {
    final svc = service();
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              results.add(await showSureSheet<AccountFormResult>(
                context: context,
                builder: (_) => AccountFormSheet(
                  account: account,
                  initialType: initialType,
                  service: svc,
                  accessTokenLoader: () async => 'token',
                  onUnauthorized: () async {},
                  today: DateTime(2026, 11, 13),
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

Finder _amount() => find.descendant(
    of: find.byKey(const ValueKey('spaBalance')),
    matching: find.byType(TextFormField));

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String rowKey, String option) async {
  await _tap(tester, find.byKey(ValueKey(rowKey)));
  final search = find.descendant(
      of: find.byType(MetadataPickerSheet), matching: find.byType(TextField));
  await tester.enterText(search.first, option);
  await tester.pumpAndSettle();
  await tester.tap(find
      .descendant(
          of: find.byType(MetadataPickerSheet),
          matching: find.textContaining(option))
      .last);
  await tester.pumpAndSettle();
  expect(find.byType(MetadataPickerSheet), findsNothing);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('spaSave')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('type step lists Connect a bank and the web\'s types in order',
      (tester) async {
    final h = _Harness();
    await h.open(tester);

    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Connect a bank'), findsOneWidget);
    final labels = [
      'Cash or bank',
      'Investment',
      'Crypto',
      'Property',
      'Vehicle',
      'Credit card',
      'Loan',
      'Other asset',
      'Other liability',
    ];
    final ys = [
      for (final label in labels) tester.getTopLeft(find.text(label)).dy,
    ];
    expect(ys, [...ys]..sort());

    await tester.tap(find.text('Credit card'));
    await tester.pumpAndSettle();
    expect(find.text('Amount owed'), findsOneWidget);
    expect(find.text('APR'), findsOneWidget);
    await tester.tap(find.text('‹ Type'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a bank'), findsOneWidget);

    await tester.tap(find.text('Connect a bank'));
    await tester.pumpAndSettle();
    expect(h.results.single?.connectBank, isTrue);
    expect(h.requests, isEmpty);
  });

  testWidgets('creates a bank account with its subtype', (tester) async {
    final h = _Harness();
    await h.open(tester);
    await tester.tap(find.text('Cash or bank'));
    await tester.pumpAndSettle();

    expect(find.text('Current balance'), findsOneWidget);
    await tester.enterText(_amount(), '1500');
    await _enter(tester, 'spaName', 'Everyday');
    await _pick(tester, 'spaSubtype', 'Checking');
    await _save(tester);

    expect(h.requests.single.method, 'POST');
    expect(h.lastBody['account'], {
      'accountable_type': 'Depository',
      'name': 'Everyday',
      'balance': '1500',
      'currency': 'USD',
      'subtype': 'checking',
      'opening_balance_date': '2024-11-13',
    });
    expect(h.results.single?.account?.id, 'new1');
  });

  testWidgets('a property needs a type and posts its address',
      (tester) async {
    final h = _Harness();
    await h.open(tester, initialType: 'property');

    expect(find.text('‹ Type'), findsNothing, reason: 'type was preselected');
    expect(find.text('Current value'), findsOneWidget);
    await tester.enterText(_amount(), '450000');
    await _enter(tester, 'spaName', 'Home');
    await _save(tester);
    expect(find.text('Choose a property type'), findsOneWidget);
    expect(h.requests, isEmpty);

    await _pick(tester, 'spaSubtype', 'Single Family Home');
    await _enter(tester, 'spa-year_built', '1995');
    await _enter(tester, 'spa-area_value', '1800');
    await _enter(tester, 'spa-line1', '1 Main St');
    await _enter(tester, 'spa-locality', 'Springfield');
    await _enter(tester, 'spa-region', 'IL');
    await _enter(tester, 'spa-postal_code', '62701');
    await _pick(tester, 'spa-country', 'United States');
    await _save(tester);

    expect(h.lastBody['account'], {
      'accountable_type': 'Property',
      'name': 'Home',
      'balance': '450000',
      'currency': 'USD',
      'accountable_attributes': {
        'subtype': 'single_family_home',
        'year_built': 1995,
        'area_value': 1800,
        'area_unit': 'sqft',
        'address_attributes': {
          'line1': '1 Main St',
          'locality': 'Springfield',
          'region': 'IL',
          'postal_code': '62701',
          'country': 'US',
        },
      },
    });
  });

  testWidgets('creates a vehicle with its details', (tester) async {
    final h = _Harness();
    await h.open(tester, initialType: 'vehicle');

    await tester.enterText(_amount(), '18000');
    await _enter(tester, 'spaName', 'Volvo');
    await _enter(tester, 'spa-make', 'Volvo');
    await _enter(tester, 'spa-model', 'V60');
    await _enter(tester, 'spa-year', '2021');
    await _enter(tester, 'spa-mileage_value', '42000');
    await _pick(tester, 'spa-mileage_unit', 'Kilometers');
    await _enter(tester, 'spa-initial_balance', '32000');
    expect(find.byKey(const ValueKey('spa-purchase_date')), findsNothing,
        reason: 'the web asks for the purchase date only on edit');
    await _save(tester);

    expect(h.lastBody['account']['accountable_type'], 'Vehicle');
    expect(h.lastBody['account']['accountable_attributes'], {
      'make': 'Volvo',
      'model': 'V60',
      'year': 2021,
      'mileage_value': 42000,
      'mileage_unit': 'km',
      'initial_balance': '32000',
    });
  });

  testWidgets('creates a loan and a credit card with their terms',
      (tester) async {
    final h = _Harness();
    await h.open(tester, initialType: 'loan');
    await tester.enterText(_amount(), '250000');
    await _enter(tester, 'spaName', 'Mortgage');
    await _pick(tester, 'spaSubtype', 'Mortgage');
    await _enter(tester, 'spa-interest_rate', '6.1');
    await _enter(tester, 'spa-term_months', '360');
    await _save(tester);

    expect(h.lastBody['account']['accountable_type'], 'Loan');
    expect(h.lastBody['account']['accountable_attributes'], {
      'subtype': 'mortgage',
      'interest_rate': '6.1',
      'rate_type': 'fixed',
      'term_months': 360,
    });
  });

  testWidgets('a credit card posts APR and statement days', (tester) async {
    final h = _Harness();
    await h.open(tester, initialType: 'credit_card');
    await tester.enterText(_amount(), '420');
    await _enter(tester, 'spaName', 'Visa');
    await _enter(tester, 'spa-apr', '19.99');
    await _pick(tester, 'spa-due_day', 'Day 25');
    await _save(tester);

    expect(h.lastBody['account']['accountable_type'], 'CreditCard');
    expect(h.lastBody['account']['accountable_attributes'],
        {'apr': '19.99', 'due_day': '25'});
  });

  testWidgets('a 422 shows the server message and keeps the sheet',
      (tester) async {
    final h = _Harness()
      ..reply = (_) => http.Response(
          jsonEncode({
            'error': 'validation_failed',
            'message': "Name can't be blank",
          }),
          422);
    await h.open(tester, initialType: 'other_asset');
    await tester.enterText(_amount(), '5');
    await _enter(tester, 'spaName', 'Art');
    await _save(tester);

    expect(find.text("Name can't be blank"), findsOneWidget);
    expect(find.byType(SureSheet), findsOneWidget);
  });

  testWidgets('edit is prefilled and sends only what changed',
      (tester) async {
    final h = _Harness();
    await h.open(tester, account: _checking);

    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('‹ Type'), findsNothing);
    expect(tester.widget<TextFormField>(_amount()).controller!.text,
        '1,500.00');
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('spaName')))
            .controller!
            .text,
        'Checking');
    expect(find.text('Checking'), findsWidgets, reason: 'subtype row');

    await _enter(tester, 'spaName', 'Everyday Checking');
    await _save(tester);

    expect(h.requests.single.method, 'PATCH');
    expect(h.requests.single.url.path, '/api/v1/accounts/chk');
    expect(h.lastBody['account'], {'name': 'Everyday Checking'});
  });

  testWidgets('a linked account locks balance and currency after the 422',
      (tester) async {
    final h = _Harness()
      ..reply = (request) => jsonDecode(request.body)['account']
              .containsKey('balance')
          ? http.Response(
              jsonEncode({
                'error': 'validation_failed',
                'message': 'Linked accounts cannot change: balance',
              }),
              422)
          : http.Response(jsonEncode(_accountJson(id: 'chk')), 200);
    await h.open(tester, account: _checking);

    await tester.enterText(_amount(), '1800');
    await _save(tester);

    expect(find.text('Linked accounts cannot change: balance'), findsOneWidget);
    expect(find.text('Synced from your bank'), findsOneWidget);
    expect(tester.widget<TextFormField>(_amount()).enabled, isFalse);
    expect(find.byKey(const ValueKey('spaDelete')), findsNothing);

    await _enter(tester, 'spaName', 'Joint');
    await _save(tester);
    expect(h.lastBody['account'], {'name': 'Joint'});
    expect(h.results.single?.account?.id, 'chk');
  });

  testWidgets('deletes after confirming (202)', (tester) async {
    final h = _Harness();
    await h.open(tester, account: _checking);

    await _tap(tester, find.byKey(const ValueKey('spaDelete')));
    expect(find.text('Delete Checking?'), findsOneWidget);
    expect(
        find.text(
            "Its transactions and history are removed. This can't be undone."),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(h.requests.single.method, 'DELETE');
    expect(h.results.single?.deleted, isTrue);
    expect(find.text('Account deleted'), findsOneWidget);
  });

  testWidgets('a linked account cannot be deleted (422)', (tester) async {
    final h = _Harness()
      ..reply = (_) => http.Response(
          jsonEncode({
            'error': 'validation_failed',
            'message':
                'Linked accounts cannot be deleted; disconnect the account first',
          }),
          422);
    await h.open(tester, account: _checking);

    await _tap(tester, find.byKey(const ValueKey('spaDelete')));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Linked accounts cannot be deleted; disconnect the account first'),
        findsOneWidget);
    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('spaDelete')), findsNothing);
    expect(find.text('Synced from your bank'), findsOneWidget);
  });

  testWidgets('a read-only sign-in gets a clear message', (tester) async {
    final h = _Harness()
      ..reply = (_) => http.Response(
          jsonEncode({
            'error': 'insufficient_scope',
            'message': 'This action requires the read_write scope',
          }),
          403);
    await h.open(tester, initialType: 'other_liability');
    await tester.enterText(_amount(), '5');
    await _enter(tester, 'spaName', 'IOU');
    await _save(tester);

    expect(
        find.text(
            'This sign-in can only view data. Sign in again with full access to change accounts.'),
        findsOneWidget);
  });

  testWidgets('fits a 320 px phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    final h = _Harness();
    await h.open(tester, initialType: 'property');
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('spaMore')));
    expect(tester.takeException(), isNull);
  });

  test('investment subtypes put the currency\'s region first', () {
    final gbp = investmentSubtypeOptions(currency: 'GBP');
    expect(gbp.first.id, 'isa');
    final usd = investmentSubtypeOptions(currency: 'USD');
    expect(usd.first.id, 'brokerage');
    expect(usd.length, gbp.length);
    final none = investmentSubtypeOptions();
    expect(none.first.id, 'pension', reason: 'generic first without a region');
  });
}
