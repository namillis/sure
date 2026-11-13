import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/account_form_sheet.dart';
import 'package:sure_mobile/screens/account_group_screen.dart';
import 'package:sure_mobile/screens/invest_screen.dart';
import 'package:sure_mobile/screens/web_view_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_actions_menu.dart';

import '../support/home_fixtures.dart';

class _PushRecorder extends NavigatorObserver {
  final pushed = <Widget>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && previousRoute != null) {
      pushed.add(route.builder(navigator!.context));
    }
  }
}

final _checking = Account(
  id: 'chk',
  name: 'Checking',
  balance: r'$10.00',
  balanceCents: 1000,
  currency: 'USD',
  classification: 'asset',
  accountType: 'depository',
);

Future<_PushRecorder> _pump(
  WidgetTester tester,
  Widget home, {
  required bool feature,
  List<Account> accounts = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final observer = _PushRecorder();
  final features = ServerFeaturesProvider()
    ..debugSet(feature ? {ServerFeaturesProvider.accountsWrite} : {});
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
        ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false)),
        ChangeNotifierProvider<AccountsProvider>(
            create: (_) => FakeAccountsProvider(accounts: accounts)),
        ChangeNotifierProvider<ServerFeaturesProvider>.value(value: features),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [observer],
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return observer;
}

Widget _addButton() => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => openAddAccount(context),
            child: const Text('add'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('without accounts.write "+" opens the web /accounts/new',
      (tester) async {
    final observer = await _pump(tester, _addButton(), feature: false);
    await tester.tap(find.text('add'));
    expect((observer.pushed.single as WebViewScreen).path, '/accounts/new');
  });

  testWidgets('with accounts.write "+" opens the native type step',
      (tester) async {
    final observer = await _pump(tester, _addButton(), feature: true);
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Cash or bank'), findsOneWidget);
    expect(observer.pushed, isEmpty);
  });

  testWidgets('the account group "+" exists only with the feature',
      (tester) async {
    await _pump(tester, const AccountGroupScreen(accountType: 'credit_card'),
        feature: false);
    expect(find.byKey(const ValueKey('groupAddAccount')), findsNothing);
  });

  testWidgets('the account group "+" opens that type\'s details step',
      (tester) async {
    await _pump(tester, const AccountGroupScreen(accountType: 'credit_card'),
        feature: true);
    await tester.tap(find.byKey(const ValueKey('groupAddAccount')));
    await tester.pumpAndSettle();
    expect(find.text('Credit card'), findsOneWidget);
    expect(find.text('Amount owed'), findsOneWidget);
    expect(find.text('‹ Type'), findsNothing);
  });

  Future<void> openMenu(WidgetTester tester, {required bool feature}) async {
    await _pump(
      tester,
      Scaffold(
        appBar: AppBar(actions: [
          AccountActionsMenu(account: _checking, onChanged: () {}),
        ]),
      ),
      feature: feature,
    );
    await tester.tap(find.byType(AccountActionsMenu));
    await tester.pumpAndSettle();
  }

  testWidgets('the account menu has no Edit account without the feature',
      (tester) async {
    await openMenu(tester, feature: false);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Edit account'), findsNothing);
  });

  testWidgets('Edit account opens the prefilled sheet', (tester) async {
    await openMenu(tester, feature: true);
    await tester.tap(find.text('Edit account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountFormSheet), findsOneWidget);
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('the Invest empty state adds an account natively',
      (tester) async {
    await _pump(tester, const InvestScreen(), feature: true, accounts: [
      homeAccount('cash', balance: r'$1.00'),
    ]);
    expect(find.text('Add an investment or crypto account, or connect a brokerage.'),
        findsOneWidget);
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountFormSheet), findsOneWidget);
  });
}
