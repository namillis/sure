import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

/// Pumps [child] in a localized, themed Scaffold (privacy off unless
/// [privacyHidden]) on a [width]×[height] logical-pixel view.
Future<void> pumpDs(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double height = 844,
  bool privacyHidden = false,
  bool scroll = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: privacyHidden),
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: scroll ? SingleChildScrollView(child: child) : child,
        ),
      ),
    ),
  );
}

/// Records `HapticFeedback` calls (e.g. `HapticFeedbackType.lightImpact`).
List<String> recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// Light and dark, for tests that must pass in both.
const brightnesses = [Brightness.light, Brightness.dark];
