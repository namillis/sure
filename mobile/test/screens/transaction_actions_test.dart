import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/merchant.dart';
import 'package:sure_mobile/models/offline_transaction.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/models/transaction_tag.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/merchants_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/recurring_form_screen.dart';
import 'package:sure_mobile/screens/transaction_actions.dart';
import 'package:sure_mobile/screens/transaction_edit_screen.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/services/transaction_actions_service.dart';
import 'package:sure_mobile/services/transaction_split_service.dart';
import 'package:sure_mobile/services/transactions_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

import '../support/recurring_fixtures.dart';

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  int logouts = 0;
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async => logouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategories extends ChangeNotifier implements CategoriesProvider {
  @override
  List<Category> get categories => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCategories({required String accessToken}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMerchants extends ChangeNotifier implements MerchantsProvider {
  @override
  List<Merchant> get merchants => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchMerchants({
    required String accessToken,
    bool forceRefresh = false,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTags extends ChangeNotifier implements TagsProvider {
  @override
  List<TransactionTag> get tags => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTags({
    required String accessToken,
    bool forceRefresh = false,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccounts extends ChangeNotifier implements AccountsProvider {
  @override
  List<Account> get accounts => [
        Account(
          id: 'acct_1',
          name: 'Checking',
          balance: '\$0.00',
          currency: 'USD',
          classification: 'asset',
          accountType: 'depository',
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionsProvider {
  @override
  String? error;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _allFeatures = {
  ServerFeaturesProvider.transactionsTransfers,
  ServerFeaturesProvider.transactionsDuplicates,
  ServerFeaturesProvider.transactionsMarkRecurring,
  ServerFeaturesProvider.transactionsLocks,
};

String _thisYear(String monthDay) => '${DateTime.now().year}-$monthDay';

OfflineTransaction _txn() => OfflineTransaction(
      id: 'txn_1',
      localId: 'local_1',
      accountId: 'acct_1',
      name: 'Blue Bottle',
      date: _thisYear('11-06'),
      amount: '\$4.50',
      currency: 'USD',
      nature: 'expense',
      syncStatus: SyncStatus.synced,
    );

Map<String, dynamic> _json({
  String id = 'txn_1',
  String name = 'Blue Bottle',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'entry_id': 'entry_$id',
      'date': _thisYear('11-06'),
      'amount': '\$4.50',
      'amount_decimal': '4.5',
      'currency': 'USD',
      'name': name,
      'classification': 'expense',
      'split_parent': false,
      'account': {'id': 'acct_1', 'name': 'Checking'},
      'transfer': null,
      'pending': false,
      'duplicate_suspected': false,
      'duplicate_confidence': null,
      'duplicate_candidate': null,
      'sync_locked': false,
      'locked_attributes': [],
      'reconciled_status': 'unreconciled',
      'reconcilable': false,
      ...extra,
    };

Map<String, dynamic> _transfer({String status = 'pending'}) => {
      'id': 'tr_1',
      'amount': '\$4.50',
      'currency': 'USD',
      'status': status,
      'other_account': {
        'id': 'acct_2',
        'name': 'Savings',
        'account_type': 'depository',
      },
    };

final _duplicate = {
  'duplicate_suspected': true,
  'pending': true,
  'duplicate_confidence': 'medium',
  'duplicate_candidate': {
    'id': 'txn_2',
    'entry_id': 'entry_txn_2',
    'date': _thisYear('11-08'),
    'name': 'Blue Bottle Coffee',
    'amount': '\$4.50',
    'amount_cents': 450,
    'signed_amount_cents': -450,
    'currency': 'USD',
  },
};

typedef _Handler = FutureOr<http.Response> Function(http.Request request);

class _Harness {
  final auth = _FakeAuth();
  final requests = <http.Request>[];
  bool? result;

  /// Action requests only (not the detail GET or the recurring list).
  List<http.Request> get actions => [
        for (final r in requests)
          if (!r.url.path.endsWith('/transactions/txn_1') &&
              !r.url.path.endsWith('/transactions/txn_2') &&
              !r.url.path.endsWith('/recurring_transactions'))
            r,
      ];
}

Future<_Harness> _open(
  WidgetTester tester, {
  Set<String> features = _allFeatures,
  Map<String, dynamic> extra = const {},
  Map<String, _Handler> handlers = const {},
  double width = 390,
  Brightness brightness = Brightness.light,
}) async {
  final h = _Harness();
  final client = MockClient((request) async {
    h.requests.add(request);
    final key = '${request.method} ${request.url.path.split('/').last}';
    final handler = handlers[key];
    if (handler != null) return handler(request);
    if (request.url.path.endsWith('/recurring_transactions')) {
      return http.Response(recurringIndexBody(const []), 200);
    }
    if (request.url.path.endsWith('/transactions/txn_2')) {
      return http.Response(
          jsonEncode(_json(id: 'txn_2', name: 'Blue Bottle Coffee')), 200);
    }
    return http.Response(jsonEncode(_json(extra: extra)), 200);
  });

  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => _Connectivity(),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: h.auth),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategories(),
        ),
        ChangeNotifierProvider<MerchantsProvider>(
          create: (_) => _FakeMerchants(),
        ),
        ChangeNotifierProvider<TagsProvider>(create: (_) => _FakeTags()),
        ChangeNotifierProvider<AccountsProvider>(
          create: (_) => _FakeAccounts(),
        ),
        ChangeNotifierProvider<TransactionsProvider>(
          create: (_) => _FakeTransactions(),
        ),
        ChangeNotifierProvider<ServerFeaturesProvider>(
          create: (_) => ServerFeaturesProvider()..debugSet(features),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                h.result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => TransactionEditScreen(
                      transaction: _txn(),
                      transactionsService: TransactionsService(client: client),
                      splitService: TransactionSplitService(client: client),
                      recurringService:
                          RecurringTransactionsService(client: client),
                      actionsService: TransactionActionsService(client: client),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _back(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.maybePop();
  await tester.pumpAndSettle();
}

Finder _inRow(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.text(text),
    );

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  group('without the features', () {
    testWidgets('keeps today\'s screen whatever the transaction carries',
        (tester) async {
      final h = await _open(
        tester,
        features: const {},
        extra: {
          ..._duplicate,
          'sync_locked': true,
          'locked_attributes': [
            {'field': 'name', 'locked_at': '2026-11-01T00:00:00Z'},
          ],
          'reconcilable': true,
          'transfer': _transfer(),
        },
      );

      expect(find.byKey(const ValueKey('transaction-duplicate-banner')),
          findsNothing);
      expect(find.byKey(const ValueKey('transaction-sync-lock-banner')),
          findsNothing);
      expect(find.byKey(const ValueKey('transaction-reconcile-row')),
          findsNothing);
      expect(find.byKey(const ValueKey('transaction-mark-recurring-row')),
          findsNothing);
      expect(find.text('Mark as transfer'), findsNothing);
      // The old read-only transfer row and the recurring form link.
      expect(_inRow('transaction-transfer-row', 'To Savings'), findsOneWidget);
      expect(find.text('Mark as recurring'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transaction-transfer-row')));
      await tester.pumpAndSettle();
      expect(find.text('Not a transfer'), findsNothing);
      expect(h.actions, isEmpty);
    });

    testWidgets('a pending transaction offers no match row', (tester) async {
      await _open(tester, features: const {}, extra: {'pending': true});
      expect(find.text('Match to posted transaction'), findsNothing);
    });
  });

  group('duplicates', () {
    testWidgets('low confidence reads "Review"', (tester) async {
      await _open(tester, extra: {
        ..._duplicate,
        'duplicate_confidence': 'low',
      });
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Possible duplicate'), findsNothing);
    });

    testWidgets('the banner shows the candidate; Merge shows the survivor',
        (tester) async {
      final h = await _open(tester, extra: _duplicate, handlers: {
        'POST merge_duplicate': (_) => http.Response(
            jsonEncode(_json(id: 'txn_2', name: 'Blue Bottle Coffee')), 200),
      });

      final banner = find.byKey(const ValueKey('transaction-duplicate-banner'));
      expect(
          find.descendant(
              of: banner, matching: find.text('Possible duplicate')),
          findsOneWidget);
      expect(
          find.descendant(
              of: banner, matching: find.text('Blue Bottle Coffee · Nov 8')),
          findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('-\$4.50')),
          findsOneWidget);
      // A suspected duplicate shows the banner, not the pending match row.
      expect(find.text('Match to posted transaction'), findsNothing);

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(h.actions.single.method, 'POST');
      expect(h.actions.single.url.path,
          '/api/v1/transactions/txn_1/merge_duplicate');
      expect(banner, findsNothing);
      final name = tester.widget<TextFormField>(
          find.byKey(const ValueKey('transaction-name-field')));
      expect(name.controller!.text, 'Blue Bottle Coffee');
      // The screen now works on the survivor.
      expect(
          h.requests.where((r) => r.url.path.endsWith('/transactions/txn_2')),
          isNotEmpty);

      await _back(tester);
      expect(h.result, isTrue);
    });

    testWidgets('"Not a duplicate" dismisses the suggestion', (tester) async {
      final h = await _open(tester, extra: _duplicate, handlers: {
        'POST dismiss_duplicate': (_) =>
            http.Response(jsonEncode(_json(extra: {'pending': true})), 200),
      });

      await tester.tap(find.text('Not a duplicate'));
      await tester.pumpAndSettle();

      expect(h.actions.single.url.path,
          '/api/v1/transactions/txn_1/dismiss_duplicate');
      expect(find.byKey(const ValueKey('transaction-duplicate-banner')),
          findsNothing);
      // Still pending, so it can be matched by hand.
      expect(find.text('Match to posted transaction'), findsOneWidget);
    });

    testWidgets('a failed merge shows the server message', (tester) async {
      await _open(tester, extra: _duplicate, handlers: {
        'POST merge_duplicate': (_) => http.Response(
            jsonEncode({'error': 'merge_failed', 'message': 'Could not merge'}),
            422),
      });

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(find.text('Could not merge'), findsOneWidget);
      expect(find.byKey(const ValueKey('transaction-duplicate-banner')),
          findsOneWidget);
    });

    testWidgets('a read-only sign-in gets a clear message', (tester) async {
      await _open(tester, extra: _duplicate, handlers: {
        'POST dismiss_duplicate': (_) => http.Response(
            jsonEncode({
              'error': 'insufficient_scope',
              'message': "This action requires the 'write' scope",
            }),
            403),
      });

      await tester.tap(find.text('Not a duplicate'));
      await tester.pumpAndSettle();

      expect(
          find.text('This sign-in can only view data. Sign in again with '
              'full access to make changes.'),
          findsOneWidget);
    });

    testWidgets('pending: pick a posted transaction, paged with Load more',
        (tester) async {
      final h = await _open(tester, extra: {
        'pending': true
      }, handlers: {
        'GET pending_merge_candidates': (request) {
          final offset = request.url.queryParameters['offset'];
          final page = offset == '0'
              ? [_json(id: 'p1', name: 'Posted one')]
              : [_json(id: 'p2', name: 'Posted two')];
          return http.Response(
            jsonEncode({
              'candidates': page,
              'pagination': {
                'offset': int.parse(offset!),
                'limit': 10,
                'has_more': offset == '0',
              },
            }),
            200,
          );
        },
        'POST pending_merge': (_) => http.Response(
            jsonEncode(_json(id: 'txn_2', name: 'Blue Bottle Coffee')), 200),
      });

      await tester.tap(find.text('Match to posted transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Posted transaction'), findsOneWidget);
      expect(find.text('Posted one'), findsOneWidget);
      expect(find.text('Posted two'), findsNothing);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Posted two'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(
          h.actions
              .where((r) => r.method == 'GET')
              .map((r) => r.url.queryParameters['offset']),
          ['0', '1']);

      await tester.tap(find.text('Posted two'));
      await tester.pumpAndSettle();

      final merge = h.actions.last;
      expect(merge.url.path, '/api/v1/transactions/txn_1/pending_merge');
      expect(_body(merge), {
        'pending_merge': {'posted_entry_id': 'entry_p2'},
      });
      expect(find.text('Posted transaction'), findsNothing);
      final name = tester.widget<TextFormField>(
          find.byKey(const ValueKey('transaction-name-field')));
      expect(name.controller!.text, 'Blue Bottle Coffee');
    });
  });

  group('transfers', () {
    Map<String, _Handler> candidates({List<Map<String, dynamic>>? list}) => {
          'GET transfer_candidates': (_) => http.Response(
                jsonEncode({
                  'candidates': list ??
                      [
                        {
                          'transaction': _json(
                              id: 'c1',
                              name: 'Transfer from checking',
                              extra: {'amount': '-\$4.50'}),
                          'account': {'id': 'acct_2', 'name': 'Savings'},
                        },
                      ],
                  'accounts': [
                    {
                      'id': 'acct_3',
                      'name': 'Brokerage',
                      'account_type': 'investment',
                      'currency': 'USD',
                    },
                  ],
                }),
                200,
              ),
        };

    http.Response matched(http.Request _) => http.Response(
          jsonEncode({
            'transfer': {'id': 'tr_1'},
            'inflow': _json(id: 'c1'),
            'outflow': _json(extra: {'transfer': _transfer()}),
          }),
          201,
        );

    testWidgets('match an existing transaction', (tester) async {
      final h = await _open(tester, handlers: {
        ...candidates(),
        'POST transfer_match': matched,
      });

      await tester.tap(find.text('Mark as transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Matching transactions'), findsOneWidget);
      expect(find.text('Or create the other side in'), findsOneWidget);
      expect(find.text('Nov 6 · Savings'), findsOneWidget);

      await tester.tap(find.text('Transfer from checking'));
      await tester.pumpAndSettle();

      final post = h.actions.last;
      expect(post.url.path, '/api/v1/transactions/txn_1/transfer_match');
      expect(_body(post), {
        'transfer_match': {
          'method': 'existing',
          'matched_entry_id': 'entry_c1',
        },
      });
      expect(find.text('Matching transactions'), findsNothing);
      expect(_inRow('transaction-transfer-row', 'Transfer'), findsOneWidget);
      expect(_inRow('transaction-transfer-row', 'Pending · Savings'),
          findsOneWidget);
    });

    testWidgets('create the other side in an account', (tester) async {
      final h = await _open(tester, handlers: {
        ...candidates(list: const []),
        'POST transfer_match': matched,
      });

      await tester.tap(find.text('Mark as transfer'));
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions'), findsOneWidget);
      // Without suggestions there is no hint to dismiss.
      expect(find.byKey(const ValueKey('transfer-dismiss-hint')), findsNothing);

      await tester.tap(find.text('Brokerage'));
      await tester.pumpAndSettle();

      expect(_body(h.actions.last), {
        'transfer_match': {'method': 'new', 'target_account_id': 'acct_3'},
      });
    });

    testWidgets('a 422 reason gets a plain message', (tester) async {
      await _open(tester, handlers: {
        ...candidates(),
        'POST transfer_match': (_) => http.Response(
              jsonEncode({
                'error': 'validation_failed',
                'message': 'raw matcher text',
                'reason': 'same_account',
              }),
              422,
            ),
      });

      await tester.tap(find.text('Mark as transfer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer from checking'));
      await tester.pumpAndSettle();

      expect(
          find.text("Both sides of a transfer can't be in the same account."),
          findsOneWidget);
      expect(find.text('raw matcher text'), findsNothing);
      expect(find.text('Matching transactions'), findsOneWidget);
    });

    testWidgets('an unknown reason falls back to the server message',
        (tester) async {
      await _open(tester, handlers: {
        ...candidates(),
        'POST transfer_match': (_) => http.Response(
              jsonEncode({'error': 'x', 'message': 'Server says no'}),
              422,
            ),
      });

      await tester.tap(find.text('Mark as transfer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer from checking'));
      await tester.pumpAndSettle();

      expect(find.text('Server says no'), findsOneWidget);
    });

    testWidgets('a hint can be dismissed with "Not a transfer"',
        (tester) async {
      final h = await _open(tester, handlers: {
        ...candidates(),
        'DELETE transfer_match': (_) => http.Response(jsonEncode(_json()), 200),
      });

      await tester.tap(find.text('Mark as transfer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer-dismiss-hint')));
      await tester.pumpAndSettle();
      expect(find.text('Not a transfer?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Not a transfer'));
      await tester.pumpAndSettle();

      expect(h.actions.last.method, 'DELETE');
      expect(find.text('Matching transactions'), findsNothing);
    });

    testWidgets('an existing transfer: "Not a transfer" after a confirm',
        (tester) async {
      final h = await _open(
        tester,
        extra: {'transfer': _transfer(status: 'confirmed')},
        handlers: {
          'DELETE transfer_match': (_) =>
              http.Response(jsonEncode(_json()), 200),
        },
      );

      expect(_inRow('transaction-transfer-row', 'Confirmed · Savings'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transaction-transfer-row')));
      await tester.pumpAndSettle();
      expect(find.text('With Savings'), findsOneWidget);

      // Cancelling the confirm sends nothing.
      await tester.tap(find.byKey(const ValueKey('transfer-not-a-transfer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(h.actions, isEmpty);

      await tester.tap(find.byKey(const ValueKey('transfer-not-a-transfer')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Not a transfer'));
      await tester.pumpAndSettle();

      expect(h.actions.single.method, 'DELETE');
      expect(h.actions.single.url.path,
          '/api/v1/transactions/txn_1/transfer_match');
      expect(find.text('With Savings'), findsNothing);
      expect(find.text('Mark as transfer'), findsOneWidget);
      await _back(tester);
      expect(h.result, isTrue);
    });
  });

  group('sync locks', () {
    testWidgets('lists the locked fields and unlocks after a confirm',
        (tester) async {
      final h = await _open(tester, extra: {
        'sync_locked': true,
        'locked_attributes': [
          {'field': 'name', 'locked_at': '2026-11-01T00:00:00Z'},
          {'field': 'category_id', 'locked_at': '2026-11-01T00:00:00Z'},
          {'field': 'tag_ids', 'locked_at': '2026-11-01T00:00:00Z'},
        ],
      }, handlers: {
        'POST unlock': (_) => http.Response(jsonEncode(_json()), 200),
      });

      expect(find.text('Protected from sync'), findsOneWidget);
      expect(find.text('Locked: Name, Category, Tags'), findsOneWidget);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Allow sync to update?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(h.actions.single.url.path, '/api/v1/transactions/txn_1/unlock');
      expect(find.text('Protected from sync'), findsNothing);
    });
  });

  group('reconcile', () {
    testWidgets('hidden unless reconcilable', (tester) async {
      await _open(tester);
      expect(find.byKey(const ValueKey('transaction-reconcile-row')),
          findsNothing);
    });

    testWidgets('one tap, one request; the row is disabled while it runs',
        (tester) async {
      final pending = Completer<http.Response>();
      final h = await _open(tester, extra: {
        'reconcilable': true,
      }, handlers: {
        'PATCH reconcile': (_) => pending.future,
      });

      expect(_inRow('transaction-reconcile-row', 'Status'), findsOneWidget);
      expect(
          _inRow('transaction-reconcile-row', 'Unreconciled'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('transaction-reconcile-row')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('transaction-reconcile-row')));
      await tester.pump();
      expect(h.actions, hasLength(1));
      expect(h.actions.single.method, 'PATCH');

      pending.complete(http.Response(
          jsonEncode(_json(extra: {
            'reconcilable': true,
            'reconciled_status': 'cleared',
          })),
          200));
      await tester.pumpAndSettle();
      expect(_inRow('transaction-reconcile-row', 'Cleared'), findsOneWidget);
    });

    testWidgets('a failure shows the message and is not retried',
        (tester) async {
      final h = await _open(tester, extra: {
        'reconcilable': true,
      }, handlers: {
        'PATCH reconcile': (_) => http.Response(
              jsonEncode({
                'error': 'reconciliation_disabled',
                'message': 'Reconciliation is off',
              }),
              422,
            ),
      });

      await tester.tap(find.byKey(const ValueKey('transaction-reconcile-row')));
      await tester.pumpAndSettle();

      expect(find.text('Reconciliation is off'), findsOneWidget);
      expect(h.actions, hasLength(1));
      expect(
          _inRow('transaction-reconcile-row', 'Unreconciled'), findsOneWidget);
    });
  });

  group('mark as recurring', () {
    testWidgets('201: "Added to recurring" with Open', (tester) async {
      final h = await _open(tester, handlers: {
        'POST mark_as_recurring': (_) => http.Response(
            jsonEncode(recurringJson(id: 'rt_1', name: 'Blue Bottle')), 201),
      });

      // Only the actions panel offers it.
      expect(find.text('Mark as recurring'), findsOneWidget);
      await tester.tap(find.text('Mark as recurring'));
      await tester.pumpAndSettle();

      expect(h.actions.single.url.path,
          '/api/v1/transactions/txn_1/mark_as_recurring');
      expect(find.text('Added to recurring'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(RecurringFormScreen), findsOneWidget);
    });

    testWidgets('409 with a series: "Already recurring" with Open',
        (tester) async {
      await _open(tester, handlers: {
        'POST mark_as_recurring': (_) => http.Response(
              jsonEncode({
                'error': 'conflict',
                'message': 'Already exists',
                'errors': ['Already exists'],
                'recurring_transaction': recurringJson(id: 'rt_1'),
              }),
              409,
            ),
      });

      await tester.tap(find.text('Mark as recurring'));
      await tester.pumpAndSettle();

      expect(find.text('Already recurring'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Already exists'), findsNothing);
    });

    testWidgets('409 without a visible series: no Open', (tester) async {
      await _open(tester, handlers: {
        'POST mark_as_recurring': (_) => http.Response(
              jsonEncode({
                'error': 'conflict',
                'message': 'Already exists',
                'errors': ['Already exists'],
                'recurring_transaction': null,
              }),
              409,
            ),
      });

      await tester.tap(find.text('Mark as recurring'));
      await tester.pumpAndSettle();

      expect(find.text('Already recurring'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets('403 shows the server message', (tester) async {
      await _open(tester, handlers: {
        'POST mark_as_recurring': (_) => http.Response(
              jsonEncode({
                'error': 'forbidden',
                'message': 'You do not have write access to this account',
              }),
              403,
            ),
      });

      await tester.tap(find.text('Mark as recurring'));
      await tester.pumpAndSettle();

      expect(find.text('You do not have write access to this account'),
          findsOneWidget);
      expect(find.text('Mark as recurring'), findsOneWidget);
    });
  });

  testWidgets('an unauthorized action signs out', (tester) async {
    final h = await _open(tester, extra: _duplicate, handlers: {
      'POST dismiss_duplicate': (_) => http.Response('{}', 401),
    });

    await tester.tap(find.text('Not a duplicate'));
    await tester.pumpAndSettle();

    expect(h.auth.logouts, 1);
    expect(find.text('Session expired. Please login again.'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow at 320 px with every action ($brightness)',
        (tester) async {
      await _open(
        tester,
        width: 320,
        brightness: brightness,
        extra: {
          ..._duplicate,
          'duplicate_candidate': {
            ...(_duplicate['duplicate_candidate'] as Map),
            'name': 'A very long merchant name that keeps going and going',
            'amount': '\$12,345.67',
          },
          'sync_locked': true,
          'locked_attributes': [
            for (final field in [
              'name',
              'date',
              'amount',
              'notes',
              'category_id',
              'merchant_id',
              'tag_ids',
            ])
              {'field': field, 'locked_at': '2026-11-01T00:00:00Z'},
          ],
          'reconcilable': true,
          'reconciled_status': 'reconciled',
          'transfer': _transfer(),
        },
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.text('Protected from sync'), findsOneWidget);
      expect(_inRow('transaction-reconcile-row', 'Reconciled'), findsOneWidget);
    });
  }

  group('helpers', () {
    test('lockedFieldLabel humanizes unknown fields', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(lockedFieldLabel(l, 'merchant_id'), 'Merchant');
      expect(lockedFieldLabel(l, 'investment_activity_label'),
          'Investment activity label');
      expect(lockedFieldLabel(l, 'account_id'), 'Account');
    });

    test('transferStatusValue without a status shows the account', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      final transfer = TransactionTransfer.fromJson({
        'id': 't',
        'other_account': {'name': 'Savings'},
      })!;
      expect(transferStatusValue(l, transfer), 'Savings');
    });
  });
}
