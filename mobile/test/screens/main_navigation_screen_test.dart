import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/main_navigation_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shell shows five tabs and switches between them',
      (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false)),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MainNavigationScreen(
          tabBodyBuilder: (_, tab) => Text('body:${tab.name}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final bar = find.byType(NavigationBar);
    expect(
      find.descendant(of: bar, matching: find.byType(NavigationDestination)),
      findsNWidgets(5),
    );
    for (final label in ['Home', 'Activity', 'Plan', 'Invest', 'Assistant']) {
      expect(find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget);
    }
    expect(find.text('body:home'), findsOneWidget);
    // Tabs are built lazily.
    expect(find.text('body:plan', skipOffstage: false), findsNothing);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('body:plan'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
