import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/backend_config_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/sure_button.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester, {required bool pushed}) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: SureTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: pushed
          ? Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const BackendConfigScreen()),
                ),
                child: const Text('open'),
              ),
            )
          : const BackendConfigScreen(),
    ));
    await tester.pumpAndSettle();
    if (pushed) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('first run has no back button and fits 320 px', (tester) async {
    await pump(tester, pushed: false);

    expect(find.byType(SureBackButton), findsNothing);
    expect(find.byType(SureButton), findsNWidgets(2));
    expect(
        find.text('https://demo.sure.am\nhttps://your-domain.com\n'
            'http://localhost:3000'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opened from Settings shows a back button that pops',
      (tester) async {
    await pump(tester, pushed: true);

    expect(find.byType(SureBackButton), findsOneWidget);
    await tester.tap(find.byType(SureBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(BackendConfigScreen), findsNothing);
  });

  testWidgets('an empty URL is rejected before saving', (tester) async {
    await pump(tester, pushed: false);

    await tester.enterText(find.byType(TextFormField), '');
    final continueButton = find.byType(SureButton).last;
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a backend URL'), findsOneWidget);
  });
}
