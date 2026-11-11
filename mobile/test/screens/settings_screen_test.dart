import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/l10n/app_localizations_en.dart';
import 'package:sure_mobile/models/user.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/merchants_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/theme_provider.dart';
import 'package:sure_mobile/screens/settings_screen.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/ds_harness.dart' show brightnesses;

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);

  final User? _user;
  int logouts = 0;

  @override
  User? get user => _user;
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async => logouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user({String? first = 'Ada', String? last = 'Lovelace'}) => User(
      id: '1',
      email: 'ada@example.com',
      firstName: first,
      lastName: last,
      uiLayout: 'dashboard',
      aiEnabled: false,
    );

void main() {
  late String previousBaseUrl;
  late ThemeProvider theme;
  late PrivacyProvider privacy;
  late _FakeAuth auth;

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
    theme = ThemeProvider();
    privacy = PrivacyProvider(initialHidden: false);
    auth = _FakeAuth(_user());
  });

  tearDown(() => ApiConfig.setBaseUrl(previousBaseUrl));

  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<PrivacyProvider>.value(value: privacy),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => MerchantsProvider()),
        ChangeNotifierProvider(create: (_) => TagsProvider()),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);

  testWidgets('shows the profile row, groups in order and the version',
      (tester) async {
    await pump(tester);

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('sure.example.com · Profile on web'), findsOneWidget);

    // Section order: Data, Tools, Display, Security, App. The list is lazy,
    // so collect headers as they scroll into view.
    final headers = <String>{};
    void collectHeaders() => headers.addAll(tester
        .widgetList<SureSectionHeader>(find.byType(SureSectionHeader))
        .map((h) => h.label));
    collectHeaders();
    for (final label in [
      'Connections',
      'Import · Upload statement',
      'Categories, tags, merchants',
      'Rules',
      'Export',
      'Account Calendar',
      'Theme',
      'Hide amounts',
      'Password and passkeys',
      'Server',
      'Custom proxy headers',
      '1.7.0 (7)',
      'Check for updates',
      'Contact us',
      'Debug logs',
      'Sign out',
      'Clear local data · Reset · Delete account',
    ]) {
      await scrollTo(tester, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
      collectHeaders();
    }
    expect(headers.toList(), ['Data', 'Tools', 'Display', 'Security', 'App']);

    // The server row shows the host.
    await scrollTo(tester, find.byKey(const ValueKey('settingsServerRow')));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settingsServerRow')),
        matching: find.text('sure.example.com'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no longer offers Group by Account Type', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Sign out'));
    expect(find.text('Group by Account Type'), findsNothing);
  });

  testWidgets('theme control sets light, auto and dark', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.byKey(const ValueKey('settingsThemeControl')));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.system);
  });

  testWidgets('hide amounts switch masks money values', (tester) async {
    await pump(tester);
    final toggle = find.byKey(const ValueKey('settingsHideAmountsSwitch'));
    await scrollTo(tester, toggle);

    await tester
        .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(privacy.hidden, isTrue);
  });

  testWidgets('import row opens a chooser with CSV and statement upload',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('settingsImportRow')));
    await tester.pumpAndSettle();

    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.text('Upload statement'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsNothing);
  });

  testWidgets('metadata row opens a chooser with categories, tags, merchants',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('settingsMetadataRow')));
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Merchants'), findsOneWidget);
  });

  testWidgets(
      'account actions sheet lists the three actions and keeps '
      'each confirm', (tester) async {
    await pump(tester);
    final link = find.byKey(const ValueKey('settingsAccountActionsLink'));
    await scrollTo(tester, link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('Account actions'), findsOneWidget);
    expect(find.text('Clear local data'), findsOneWidget);
    expect(find.text('Reset account'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.byKey(const ValueKey('accountActionCancel')), findsOneWidget);

    // Reset keeps its confirm dialog; cancelling it does nothing.
    await tester.tap(find.byKey(const ValueKey('accountActionReset')));
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppLocalizationsEn().settingsResetAccountContent),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.logouts, 0);

    // Delete keeps its confirm dialog too.
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accountActionDelete')));
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizationsEn().settingsDeleteAccountConfirmContent),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Clear local data keeps its confirm.
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accountActionClear')));
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizationsEn().settingsClearDataContent),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The sheet's own Cancel closes it with no action.
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accountActionCancel')));
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('sign out confirms, then logs out', (tester) async {
    await pump(tester);
    final signOut = find.byKey(const ValueKey('settingsSignOut'));
    await scrollTo(tester, signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
  });

  testWidgets('proxy headers open in a sheet with Cancel and Save',
      (tester) async {
    await pump(tester);
    final row = find.byKey(const ValueKey('settingsProxyHeadersRow'));
    await scrollTo(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Add header'), findsOneWidget);
  });

  for (final brightness in brightnesses) {
    testWidgets('lays out at 320 px without overflow ($brightness)',
        (tester) async {
      auth =
          _FakeAuth(_user(first: 'Bartholomew-Maximilian', last: 'Oyelaran'));
      await pump(tester, width: 320, brightness: brightness);
      await scrollTo(tester, find.text('Sign out'));
      expect(tester.takeException(), isNull);
    });
  }

  group('profileInitials', () {
    test('uses first and last name', () {
      expect(profileInitials(_user()), 'AL');
    });
    test('falls back to the email when there is no name', () {
      expect(profileInitials(_user(first: null, last: null)), 'A');
    });
    test('shows U when signed out', () {
      expect(profileInitials(null), 'U');
    });
  });

  test('serverHost keeps only the host', () {
    expect(serverHost('https://sure.example.com/'), 'sure.example.com');
    expect(serverHost('http://localhost:3000'), 'localhost');
    expect(serverHost('not a url'), 'not a url');
  });

  group('biometricLockLabel', () {
    final l = AppLocalizationsEn();
    test('names Face ID and Touch ID on iOS', () {
      expect(biometricLockLabel(l, [BiometricType.face], TargetPlatform.iOS),
          'Face ID lock');
      expect(
          biometricLockLabel(
              l, [BiometricType.fingerprint], TargetPlatform.iOS),
          'Touch ID lock');
    });
    test('is generic elsewhere or when the type is unknown', () {
      expect(
          biometricLockLabel(
              l, [BiometricType.fingerprint], TargetPlatform.android),
          'Biometric lock');
      expect(biometricLockLabel(l, const [], TargetPlatform.iOS),
          'Biometric lock');
    });
  });
}
