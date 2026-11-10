import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/plan_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

void main() {
  Future<void> pumpPlan(WidgetTester tester, {WidgetBuilder? recurring}) {
    return tester.pumpWidget(MaterialApp(
      theme: SureTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: recurring == null
            ? PlanScreen(budgetBuilder: (_) => const Text('budget body'))
            : PlanScreen(
                budgetBuilder: (_) => const Text('budget body'),
                recurringBuilder: recurring,
              ),
      ),
    ));
  }

  testWidgets('segments switch between budget, recurring, goals and bills',
      (tester) async {
    await pumpPlan(tester);

    expect(find.text('budget body'), findsOneWidget);

    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('budget body'), findsNothing);

    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Goals live on the web'), findsOneWidget);
    expect(find.text('Open on the web'), findsOneWidget);

    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bills live on the web'), findsOneWidget);

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(find.text('budget body'), findsOneWidget);
  });

  testWidgets('the recurring slot shows the plugged-in screen',
      (tester) async {
    await pumpPlan(tester, recurring: (_) => const Text('recurring body'));

    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();
    expect(find.text('recurring body'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });
}
