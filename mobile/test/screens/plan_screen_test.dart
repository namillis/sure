import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/plan_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

void main() {
  Future<void> pumpPlan(WidgetTester tester, {WidgetBuilder? recurring}) {
    return tester.pumpWidget(MaterialApp(
      theme: SureTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: recurring == null
            ? PlanScreen(
                budgetBuilder: (_) => const Text('budget body'),
                recurringBuilder: (_) => const ComingSoonView(),
              )
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

  testWidgets('shows a large Plan title and marks the web-only segments',
      (tester) async {
    await pumpPlan(tester);

    // The large title, plus the small bar title that fades in on scroll.
    expect(find.text('Plan'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('planSectionSwitcher')), findsOneWidget);
    final webMarks = tester
        .widgetList<SureIcon>(find.byType(SureIcon))
        .where((icon) => icon.name == SureIcons.arrowUpRight);
    expect(webMarks, hasLength(2));
  });

  testWidgets('Goals opens an empty state with a web button', (tester) async {
    await pumpPlan(tester);

    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsNWidgets(2)); // segment + empty state
    expect(find.text('Open on the web'), findsOneWidget);
  });

  testWidgets('the segmented control fits a 320 px wide screen',
      (tester) async {
    tester.view.physicalSize = const Size(960, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpPlan(tester);

    expect(tester.takeException(), isNull);
  });
}
