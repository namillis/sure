import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/user.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/merchants_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/theme_provider.dart';
import 'package:sure_mobile/screens/ai_settings_screen.dart';
import 'package:sure_mobile/screens/api_keys_screen.dart';
import 'package:sure_mobile/screens/settings_screen.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  User? get user => User(
        id: '1',
        email: 'ada@example.com',
        firstName: 'Ada',
        lastName: 'Lovelace',
        uiLayout: 'dashboard',
        aiEnabled: false,
      );
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PushRecorder extends NavigatorObserver {
  final pushed = <Widget>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && previousRoute != null) {
      pushed.add(route.builder(navigator!.context));
    }
  }
}

void main() {
  late String previousBaseUrl;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'Sure',
      packageName: 'am.sure.app',
      version: '1.7.0',
      buildNumber: '7',
      buildSignature: '',
    );
    previousBaseUrl = ApiConfig.baseUrl;
    ApiConfig.setBaseUrl('https://sure.example.com');
    AiSettingsAccess.reset();
  });

  tearDown(() {
    ApiConfig.setBaseUrl(previousBaseUrl);
    AiSettingsAccess.reset();
  });

  Future<int> pump(
    WidgetTester tester, {
    Set<String> features = const {},
    bool? admin,
    List<NavigatorObserver> observers = const [],
  }) async {
    var adminCalls = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
            create: (_) => PrivacyProvider(initialHidden: false)),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => MerchantsProvider()),
        ChangeNotifierProvider(create: (_) => TagsProvider()),
        ChangeNotifierProvider<ServerFeaturesProvider>.value(
            value: ServerFeaturesProvider()..debugSet(features)),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: observers,
        home: SettingsScreen(adminLoader: () async {
          adminCalls++;
          return admin;
        }),
      ),
    ));
    await tester.pumpAndSettle();
    return adminCalls;
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);

  testWidgets('without the features there are no API keys or AI rows',
      (tester) async {
    final calls = await pump(tester, admin: true);
    await scrollTo(tester, find.text('Debug logs'));
    expect(find.text('API keys'), findsNothing);
    expect(find.text('AI'), findsNothing);
    // No role lookup without settings.ai.
    expect(calls, 0);
  });

  testWidgets('settings.api_keys adds a row that opens API keys',
      (tester) async {
    final observer = _PushRecorder();
    await pump(tester,
        features: const {ServerFeaturesProvider.settingsApiKeys},
        observers: [observer]);
    final row = find.byKey(const ValueKey('settingsApiKeysRow'));
    await scrollTo(tester, row);
    expect(find.descendant(of: row, matching: find.text('API keys')),
        findsOneWidget);
    await tester.tap(row);
    expect(observer.pushed.single, isA<ApiKeysScreen>());
  });

  testWidgets('settings.ai shows the AI row to admins only', (tester) async {
    final observer = _PushRecorder();
    await pump(tester,
        features: const {ServerFeaturesProvider.settingsAi},
        admin: true,
        observers: [observer]);
    final row = find.byKey(const ValueKey('settingsAiRow'));
    await scrollTo(tester, row);
    await tester.tap(row);
    expect(observer.pushed.single, isA<AiSettingsScreen>());
  });

  testWidgets('a member gets no AI row', (tester) async {
    await pump(tester,
        features: const {ServerFeaturesProvider.settingsAi}, admin: false);
    await scrollTo(tester, find.text('Debug logs'));
    expect(find.byKey(const ValueKey('settingsAiRow')), findsNothing);
  });

  testWidgets('the role is looked up once per session', (tester) async {
    expect(
        await pump(tester,
            features: const {ServerFeaturesProvider.settingsAi}, admin: true),
        1);
    expect(
        await pump(tester,
            features: const {ServerFeaturesProvider.settingsAi}, admin: true),
        0);
  });

  testWidgets('after a 403 the AI row stays hidden for the session',
      (tester) async {
    AiSettingsAccess.setAdmin('1', true);
    AiSettingsAccess.hide('1');
    await pump(tester,
        features: const {ServerFeaturesProvider.settingsAi}, admin: true);
    await scrollTo(tester, find.text('Debug logs'));
    expect(find.byKey(const ValueKey('settingsAiRow')), findsNothing);
  });
}
