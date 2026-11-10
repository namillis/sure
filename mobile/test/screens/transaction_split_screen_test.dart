import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/transaction_split_screen.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/transaction_split_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/sure_button.dart';

class _OnlineConnectivity extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('saves only once the parts add up, in the API sign convention',
      (tester) async {
    Object? sentBody;
    final service = TransactionSplitService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/transactions/txn_1/split');
        sentBody = jsonDecode(request.body);
        return http.Response(
          '{"transaction_id":"txn_1","amount":"\$100.00","amount_decimal":"-100.0",'
          '"currency":"USD","children":[]}',
          201,
        );
      }),
    );
    final transaction = Transaction(
      id: 'txn_1',
      accountId: 'acct_1',
      name: 'Paycheck',
      date: '2026-11-01',
      amount: '-\$100.00',
      amountDecimal: '-100.0',
      currency: 'USD',
      nature: 'income',
    );
    bool? popped;
    // Tall enough that the whole list (and its Save button) is built.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false),
          ),
          ChangeNotifierProvider<ConnectivityService>(
            create: (_) => _OnlineConnectivity(),
          ),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
          ChangeNotifierProvider<CategoriesProvider>(
            create: (_) => CategoriesProvider(),
          ),
        ],
        child: MaterialApp(
          theme: SureTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => TransactionSplitScreen(
                      transaction: transaction,
                      splitService: service,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    SureButton saveButton() =>
        tester.widget<SureButton>(find.widgetWithText(SureButton, 'Save split'));

    // Fields: part 1 name, part 1 amount, part 2 name, part 2 amount.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '60');
    await tester.pump();
    expect(find.textContaining('Remaining'), findsOneWidget);
    expect(saveButton().onPressed, isNull);

    await tester.enterText(fields.at(3), '40.01');
    await tester.pump();
    expect(find.textContaining('Over by'), findsOneWidget);
    expect(saveButton().onPressed, isNull);

    await tester.enterText(fields.at(3), '40');
    await tester.enterText(fields.at(0), 'Rent share');
    await tester.pump();
    expect(find.text('The parts add up to the total.'), findsOneWidget);
    expect(saveButton().onPressed, isNotNull);

    await tester.ensureVisible(find.widgetWithText(SureButton, 'Save split'));
    await tester.tap(find.widgetWithText(SureButton, 'Save split'));
    await tester.pumpAndSettle();

    // Income parent: typed positive parts go out negative, like the parent.
    expect(sentBody, {
      'split': {
        'splits': [
          {'amount': '-60', 'name': 'Rent share'},
          {'amount': '-40'},
        ],
      },
    });
    expect(popped, isTrue);
  });
}
