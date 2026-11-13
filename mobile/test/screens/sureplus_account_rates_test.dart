import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/account_form_sheet.dart';
import 'package:sure_mobile/services/accounts_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_actions_menu.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

const _p = ServerFeaturesProvider.accountsPermissions;
const _r = ServerFeaturesProvider.accountsLoanRates;
const _w = ServerFeaturesProvider.accountsWrite;

Map<String, dynamic> _json({
  String id = 'acc',
  String name = 'Account',
  String type = 'depository',
  bool linked = false,
  bool edit = true,
  bool? delete,
  List<String> locked = const [],
  Map<String, dynamic>? accountable,
}) =>
    {
      'id': id,
      'name': name,
      'balance': r'$1,500.00',
      'balance_cents': 150000,
      'currency': 'USD',
      'classification': 'asset',
      'account_type': type,
      'linked': linked,
      'permissions': {'edit': edit, 'delete': delete ?? (edit && !linked)},
      'locked_fields': locked,
      if (accountable != null) 'accountable': accountable,
    };

final _loanAccountable = {
  'subtype': 'mortgage',
  'rate_type': 'variable',
  'interest_rate': '4.5',
  'term_months': 360,
  'initial_balance': '300000.0',
  'start_date': '2020-01-15',
  'down_payment': null,
  'insurance_rate': '0.36',
  'insurance_rate_type': 'level_term',
  'day_count_convention': 'actual_365',
  'principal_only_transfers': false,
  'rate_changes': [
    {'effective_date': '2024-03-01', 'rate': '5.25'},
  ],
};

class _Harness {
  _Harness(this.features, {this.show});

  final Set<String> features;

  /// The GET show body; null answers 404.
  final Map<String, dynamic>? show;
  final requests = <http.Request>[];
  final results = <AccountFormResult?>[];

  Map<String, dynamic> get patchBody => jsonDecode(
          requests.lastWhere((r) => r.method == 'PATCH').body)['account']
      as Map<String, dynamic>;

  Iterable<http.Request> get gets => requests.where((r) => r.method == 'GET');

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final provider = ServerFeaturesProvider()..debugSet(features);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false)),
        ChangeNotifierProvider<ServerFeaturesProvider>.value(value: provider),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: home),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Account account) async {
    final service = AccountsService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return show == null
              ? http.Response('{"error":"not_found"}', 404)
              : http.Response(jsonEncode(show), 200);
        }
        return http.Response(
            jsonEncode(_json(id: account.id, type: account.accountType)),
            200);
      }),
    );
    await pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              results.add(await showSureSheet<AccountFormResult>(
                context: context,
                builder: (_) => AccountFormSheet(
                  account: account,
                  service: service,
                  accessTokenLoader: () async => 'token',
                  onUnauthorized: () async {},
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _showMore(WidgetTester tester) => _tap(
    tester,
    find
        .descendant(
            of: find.byKey(const ValueKey('spaMore')),
            matching: find.byType(Text))
        .last);

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('spaSave')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester
    .widget<TextFormField>(find.byKey(ValueKey(key)))
    .controller!
    .text;

void main() {
  final linkedChecking = Account.fromJson(_json(
    id: 'chk',
    name: 'Checking',
    linked: true,
    locked: const ['balance', 'currency'],
  ));

  group('accounts.permissions', () {
    Future<void> openMenu(
        WidgetTester tester, Account account, Set<String> features) async {
      await _Harness(features).pump(
        tester,
        Scaffold(
          appBar: AppBar(actions: [
            AccountActionsMenu(account: account, onChanged: () {}),
          ]),
        ),
      );
      await tester.tap(find.byType(AccountActionsMenu));
      await tester.pumpAndSettle();
    }

    final shared = Account.fromJson(_json(edit: false));

    testWidgets('hides Edit account when permissions.edit is false',
        (tester) async {
      await openMenu(tester, shared, {_w, _p});
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Edit account'), findsNothing);
    });

    testWidgets('keeps Edit account without the feature', (tester) async {
      await openMenu(tester, shared, {_w});
      expect(find.text('Edit account'), findsOneWidget);
    });

    testWidgets('locked fields are read-only up front and Delete is hidden',
        (tester) async {
      final h = _Harness({_w, _p});
      await h.open(tester, linkedChecking);

      expect(find.text('Synced from your bank'), findsOneWidget);
      expect(tester.widget<TextFormField>(_amount()).enabled, isFalse);
      expect(
          tester
              .widget<SureListRow>(find.byKey(const ValueKey('spaCurrency')))
              .onTap,
          isNull);
      expect(find.byKey(const ValueKey('spaDelete')), findsNothing);

      await _enter(tester, 'spaName', 'Joint');
      await _save(tester);
      expect(h.patchBody, {'name': 'Joint'});
    });

    testWidgets('without the feature the sheet learns it from the 422',
        (tester) async {
      final h = _Harness({_w});
      await h.open(tester, linkedChecking);

      expect(find.text('Synced from your bank'), findsNothing);
      expect(tester.widget<TextFormField>(_amount()).enabled, isTrue);
      expect(find.byKey(const ValueKey('spaDelete')), findsOneWidget);
    });

    testWidgets('a linked vehicle shows its purchase price read-only',
        (tester) async {
      final vehicle = Account.fromJson(_json(
        id: 'car',
        type: 'vehicle',
        linked: true,
        locked: const [
          'balance',
          'currency',
          'accountable_attributes.initial_balance',
          'accountable_attributes.initial_balance_shown',
          'accountable_attributes.purchase_date',
        ],
        accountable: {
          'make': 'Volvo',
          'model': 'V60',
          'year': 2021,
          'mileage_value': 42000,
          'mileage_unit': 'km',
          'initial_balance': '30000.0',
          'initial_balance_shown': '30000.0',
          'purchase_date': '2021-05-01',
        },
      ));
      final h = _Harness({_w, _p, _r});
      await h.open(tester, vehicle);

      expect(find.byKey(const ValueKey('sa2VehicleSynced')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('spa-initial_balance')),
              matching: find.byType(TextFormField)),
          findsNothing);
      expect(find.text('30000'), findsOneWidget);

      await _enter(tester, 'spa-make', 'Saab');
      await _save(tester);
      expect(h.patchBody['accountable_attributes'], {'make': 'Saab'},
          reason: 'locked fields, including initial_balance_shown, stay out');
    });
  });

  group('accounts.loan_rates', () {
    final loan = Account.fromJson(_json(
      id: 'loan',
      name: 'Mortgage',
      type: 'loan',
    ));

    testWidgets('prefills the loan from the show response', (tester) async {
      final h = _Harness({_w, _r},
          show: _json(id: 'loan', type: 'loan', accountable: _loanAccountable));
      await h.open(tester, loan);
      await _showMore(tester);

      expect(h.gets.single.url.path, '/api/v1/accounts/loan');
      expect(_text(tester, 'spa-interest_rate'), '4.5');
      expect(_text(tester, 'spa-term_months'), '360');
      expect(_text(tester, 'spa-insurance_rate'), '0.36');
      expect(find.text('Level term'), findsOneWidget);
      expect(find.text('Actual/365'), findsOneWidget);
      expect(find.text('Rate changes'), findsOneWidget);
      expect(find.text('Mar 1, 2024'), findsOneWidget);
      expect(find.text('5.25%'), findsOneWidget);

      await _enter(tester, 'spaName', 'Home loan');
      await _save(tester);
      expect(h.patchBody, {'name': 'Home loan'},
          reason: 'untouched prefill and rate changes are not sent');
    });

    testWidgets('sends changed loan fields and the new rate change list',
        (tester) async {
      final h = _Harness({_w, _r},
          show: _json(id: 'loan', type: 'loan', accountable: _loanAccountable));
      await h.open(tester, loan);
      await _showMore(tester);

      await _enter(tester, 'spa-insurance_rate', '');
      await _tap(
          tester,
          find.descendant(
              of: find.byKey(const ValueKey('sa2PrincipalOnly')),
              matching: find.byType(Switch)));

      await _tap(tester, find.byKey(const ValueKey('sa2AddRateChange')));
      await tester.enterText(
          find.byKey(const ValueKey('sa2RateChangeRate')), '150');
      await tester.tap(find.byKey(const ValueKey('sa2RateChangeSave')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a rate from 0 to 100'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('sa2RateChangeRate')), '3.9');
      await tester.tap(find.byKey(const ValueKey('sa2RateChangeSave')));
      await tester.pumpAndSettle();

      await _save(tester);
      final today = DateUtils.dateOnly(DateTime.now());
      final iso = '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      expect(h.patchBody['accountable_attributes'], {
        'insurance_rate': null,
        'principal_only_transfers': true,
        'rate_changes': [
          {'effective_date': '2024-03-01', 'rate': '5.25'},
          {'effective_date': iso, 'rate': '3.9'},
        ],
      });
    });

    testWidgets('swiping away the last rate change sends []', (tester) async {
      final h = _Harness({_w, _r});
      final withBlock = Account.fromJson(
          _json(id: 'loan', type: 'loan', accountable: _loanAccountable));
      await h.open(tester, withBlock);
      expect(h.gets, isEmpty, reason: 'the account already has the block');
      await _showMore(tester);

      final row = find.byKey(const ValueKey('sa2RateChange-0'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.drag(row, const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(SureSwipeActions), matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(find.text('5.25%'), findsNothing);

      await _save(tester);
      expect(h.patchBody, {
        'accountable_attributes': {'rate_changes': <dynamic>[]},
      });
    });

    testWidgets('editing a rate change replaces it', (tester) async {
      final h = _Harness({_w, _r});
      await h.open(
          tester,
          Account.fromJson(
              _json(id: 'loan', type: 'loan', accountable: _loanAccountable)));
      await _showMore(tester);

      await _tap(tester, find.text('Mar 1, 2024'));
      expect(_text(tester, 'sa2RateChangeRate'), '5.25');
      await tester.enterText(
          find.byKey(const ValueKey('sa2RateChangeRate')), '5.5');
      await tester.tap(find.byKey(const ValueKey('sa2RateChangeSave')));
      await tester.pumpAndSettle();

      await _save(tester);
      expect(h.patchBody['accountable_attributes'], {
        'rate_changes': [
          {'effective_date': '2024-03-01', 'rate': '5.5'},
        ],
      });
    });

    testWidgets('vehicles send initial_balance_shown back unchanged',
        (tester) async {
      final h = _Harness({_w, _r});
      await h.open(
        tester,
        Account.fromJson(_json(id: 'car', type: 'vehicle', accountable: {
          'make': 'Volvo',
          'model': null,
          'year': 2021,
          'mileage_value': null,
          'mileage_unit': 'km',
          'initial_balance': '30000.0',
          'initial_balance_shown': '30000.0',
          'purchase_date': '2021-05-01',
        })),
      );
      expect(_text(tester, 'spa-make'), 'Volvo');
      expect(_text(tester, 'spa-initial_balance'), '30000');

      await _enter(tester, 'spa-initial_balance', '28000');
      await _save(tester);
      expect(h.patchBody['accountable_attributes'], {
        'initial_balance': '28000',
        'initial_balance_shown': '30000.0',
      });
    });

    testWidgets('without the feature: no fetch and no extra loan rows',
        (tester) async {
      final h = _Harness({_w},
          show: _json(id: 'loan', type: 'loan', accountable: _loanAccountable));
      await h.open(tester, loan);
      await _showMore(tester);

      expect(h.gets, isEmpty);
      expect(_text(tester, 'spa-interest_rate'), '');
      expect(find.byKey(const ValueKey('spa-insurance_rate')), findsNothing);
      expect(find.text('Rate changes'), findsNothing);
      expect(find.byKey(const ValueKey('sa2PrincipalOnly')), findsNothing);
    });

    testWidgets('a failed fetch leaves the sheet as without the feature',
        (tester) async {
      final h = _Harness({_w, _r});
      await h.open(tester, loan);
      await _showMore(tester);

      expect(h.gets.length, 1);
      expect(find.byKey(const ValueKey('spa-insurance_rate')), findsOneWidget);
      expect(find.text('Rate changes'), findsNothing,
          reason: 'the list is unknown, so it cannot be replaced');
      await _enter(tester, 'spaName', 'Loan');
      await _save(tester);
      expect(h.patchBody, {'name': 'Loan'});
    });

    testWidgets('fits a 320 px phone with the loan rows open',
        (tester) async {
      final h = _Harness({_w, _r});
      await h.open(
          tester,
          Account.fromJson(
              _json(id: 'loan', type: 'loan', accountable: _loanAccountable)));
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      await tester.pumpAndSettle();
      await _showMore(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('sa2AddRateChange')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
