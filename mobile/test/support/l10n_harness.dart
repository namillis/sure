import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

/// Pumps [child] inside a localized, themed Scaffold with privacy off, on a
/// tall phone-sized view.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget child, {
  double logicalHeight = 844,
}) async {
  tester.view.physicalSize = Size(1170, logicalHeight * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: false),
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
