import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/activity_transaction.dart';
import 'package:sure_mobile/models/offline_transaction.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_category_icon.dart';
import 'package:sure_mobile/widgets/ds/sure_day_header.dart';
import 'package:sure_mobile/widgets/ds/sure_transaction_row.dart';
import 'package:sure_mobile/widgets/money_text.dart';

import '../../support/ds_harness.dart';

Transaction tx(String amount,
        {String name = 'Whole Foods', String? category}) =>
    Transaction(
      id: 't1',
      accountId: 'a1',
      name: name,
      date: '2026-11-09',
      amount: amount,
      currency: 'USD',
      nature: 'expense',
      categoryName: category,
    );

void main() {
  MoneyText amountOf(WidgetTester tester) =>
      tester.widget<MoneyText>(find.byType(MoneyText));

  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

    testWidgets(
        'expense: minus, textPrimary, mono; Category · Account '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'$54.20', category: 'Groceries'),
          accountName: 'Chase Sapphire',
          accountType: 'credit_card',
          categoryColor: '#407706',
          categoryIcon: 'shopping-bag',
        ),
        brightness: brightness,
      );
      expect(find.text('Whole Foods'), findsOneWidget);
      expect(find.text('Groceries · Chase Sapphire'), findsOneWidget);
      expect(amountOf(tester).text, r'-$54.20');
      expect(amountOf(tester).color, tokens.textPrimary);
      final text = tester.widget<Text>(find.text(r'-$54.20'));
      expect(text.style?.fontFamily, SureTokens.fontMono);
      final icon =
          tester.widget<SureCategoryIcon>(find.byType(SureCategoryIcon));
      expect(icon.icon, 'shopping-bag');
      expect(find.textContaining('USD'), findsNothing);
    });

    testWidgets('income: plus in success (${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'-$3,200.00', name: 'Payroll', category: 'Income'),
          accountType: 'depository',
        ),
        brightness: brightness,
      );
      expect(amountOf(tester).text, r'+$3,200.00');
      expect(amountOf(tester).color, tokens.success);
    });

    testWidgets(
        'transfer: textSecondary, Transfer subtitle (${brightness.name})',
        (tester) async {
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'$500.00', name: 'Payment'),
          accountName: 'Checking',
          accountType: 'depository',
          isTransfer: true,
        ),
        brightness: brightness,
      );
      expect(amountOf(tester).color, tokens.textSecondary);
      expect(find.text('Transfer · Checking'), findsOneWidget);
      expect(
          tester.widget<SureCategoryIcon>(find.byType(SureCategoryIcon)).kind,
          SureCategoryKind.transfer);
    });

    testWidgets(
        'long name, subtitle and amount at 320 px do not overflow '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'$1,234,567.89',
              name: 'An extremely long merchant name that has to ellipsize',
              category: 'A long category name'),
          accountName: 'A long account name as well',
          accountType: 'depository',
          syncStatus: SyncStatus.failed,
        ),
        brightness: brightness,
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('split parent and uncategorized subtitles', (tester) async {
    await pumpDs(
      tester,
      SureTransactionRow(
        transaction: tx(r'$212.48', name: 'Costco'),
        accountName: 'Checking',
        isSplitParent: true,
      ),
    );
    expect(find.text('Split · Checking'), findsOneWidget);
    expect(tester.widget<SureCategoryIcon>(find.byType(SureCategoryIcon)).kind,
        SureCategoryKind.split);

    await pumpDs(
      tester,
      SureTransactionRow(transaction: tx(r'$6.85'), accountName: 'Checking'),
    );
    expect(find.text('Uncategorized · Checking'), findsOneWidget);
  });

  testWidgets('showAccount false leaves the account out', (tester) async {
    await pumpDs(
      tester,
      SureTransactionRow(
        transaction: tx(r'$4.50', category: 'Coffee'),
        accountName: 'Checking',
        showAccount: false,
      ),
    );
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('pending and failed badges', (tester) async {
    await pumpDs(
      tester,
      SureTransactionRow(
          transaction: tx(r'$4.50'), syncStatus: SyncStatus.pending),
    );
    expect(find.text('Pending'), findsOneWidget);
    await pumpDs(
      tester,
      SureTransactionRow(
          transaction: tx(r'$4.50'), syncStatus: SyncStatus.failed),
    );
    expect(find.text('Failed'), findsOneWidget);
    await pumpDs(
      tester,
      SureTransactionRow(
          transaction: tx(r'$4.50'), syncStatus: SyncStatus.synced),
    );
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('privacy mode masks the amount', (tester) async {
    await pumpDs(
      tester,
      SureTransactionRow(transaction: tx(r'$54.20'), accountType: 'depository'),
      privacyHidden: true,
    );
    expect(amountOf(tester).text, r'-$••••');
  });

  testWidgets('activity factory carries the API display context',
      (tester) async {
    final row = ActivityTransaction.fromJson({
      'id': 't1',
      'name': 'Whole Foods',
      'date': '2026-11-09',
      'amount': r'$54.20',
      'currency': 'USD',
      'classification': 'expense',
      'account': {'id': 'a1', 'name': 'Checking', 'account_type': 'depository'},
      'category': {
        'id': 'c1',
        'name': 'Groceries',
        'color': '#407706',
        'icon': 'shopping-bag'
      },
    });
    await pumpDs(tester, SureTransactionRow.activity(row));
    expect(find.text('Groceries · Checking'), findsOneWidget);
    expect(amountOf(tester).text, r'-$54.20');
    final icon = tester.widget<SureCategoryIcon>(find.byType(SureCategoryIcon));
    expect((icon.color, icon.icon), ('#407706', 'shopping-bag'));
  });

  group('swipe actions', () {
    Future<(List<String>, List<String>)> pumpSwipeable(
        WidgetTester tester) async {
      final fired = <String>[];
      final haptics = recordHaptics(tester);
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'$54.20', category: 'Groceries'),
          onTap: () => fired.add('tap'),
          onCategorize: () => fired.add('categorize'),
          onDelete: () => fired.add('delete'),
        ),
      );
      return (fired, haptics);
    }

    testWidgets('swipe left reveals Categorize and Delete', (tester) async {
      final (fired, haptics) = await pumpSwipeable(tester);
      await tester.drag(find.byType(SureTransactionRow), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text('Categorize').hitTestable(), findsOneWidget);
      expect(find.text('Delete').hitTestable(), findsOneWidget);
      final delete = tester.widget<Text>(find.text('Delete'));
      expect(delete.style?.color, const Color(0xFFFFFFFF));

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(fired, ['delete']);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      // The row closes again after an action.
      expect(find.text('Delete').hitTestable(), findsNothing);
    });

    testWidgets('Categorize fires its callback', (tester) async {
      final (fired, _) = await pumpSwipeable(tester);
      await tester.drag(find.byType(SureTransactionRow), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categorize'));
      await tester.pumpAndSettle();
      expect(fired, ['categorize']);
    });

    testWidgets('a short swipe springs back; tapping an open row closes it',
        (tester) async {
      final (fired, _) = await pumpSwipeable(tester);
      await tester.timedDrag(find.byType(SureTransactionRow),
          const Offset(-30, 0), const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Delete').hitTestable(), findsNothing);

      await tester.drag(find.byType(SureTransactionRow), const Offset(-200, 0));
      await tester.pumpAndSettle();
      // Tap the visible part of the slid-over row.
      await tester.tapAt(
          Offset(40, tester.getCenter(find.byType(SureTransactionRow)).dy));
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
      expect(find.text('Delete').hitTestable(), findsNothing);

      await tester.tap(find.text('Whole Foods'));
      expect(fired, ['tap']);
    });

    testWidgets('no swipe in selection mode; long-press reports',
        (tester) async {
      var longPresses = 0;
      await pumpDs(
        tester,
        SureTransactionRow(
          transaction: tx(r'$54.20'),
          selectionMode: true,
          selected: true,
          onLongPress: () => longPresses++,
          onDelete: () {},
        ),
      );
      await tester.drag(find.byType(SureTransactionRow), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      expect(find.byType(SureCategoryIcon), findsNothing);
      await tester.longPress(find.text('Whole Foods'));
      expect(longPresses, 1);
    });
  });

  group('day header', () {
    for (final brightness in brightnesses) {
      testWidgets('label and mono total (${brightness.name}, 320 px)',
          (tester) async {
        await pumpDs(
          tester,
          Builder(
            builder: (context) => SureDayHeader.forDay(
              context,
              DateTime(2026, 11, 10),
              total: r'-$1,234,567.89',
              now: DateTime(2026, 11, 11),
            ),
          ),
          brightness: brightness,
          width: 320,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Yesterday'), findsOneWidget);
        final total = tester.widget<Text>(find.text(r'-$1,234,567.89'));
        expect(total.style?.fontFamily, SureTokens.fontMono);
        final tokens =
            brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;
        expect(total.style?.color, tokens.textSecondary);
      });
    }

    testWidgets('a long label ellipsizes', (tester) async {
      await pumpDs(
        tester,
        SureDayHeader(label: 'A very long label ' * 10, total: r'$1.00'),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
