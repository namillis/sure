import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/l10n/app_localizations_en.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/auth_fields.dart';
import 'package:sure_mobile/screens/biometric_lock_screen.dart';
import 'package:sure_mobile/screens/intro_screen.dart';
import 'package:sure_mobile/screens/sso_onboarding_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/sure_button.dart';

class _FakeSsoAuth extends AuthProvider {
  _FakeSsoAuth({
    this.allowCreate = true,
    this.invitation = false,
    this.error,
  });

  final bool allowCreate;
  final bool invitation;
  String? error;
  int cancels = 0;
  final links = <String>[];
  final creates = <String>[];

  @override
  String? get ssoEmail => 'pat@example.test';
  @override
  String? get ssoFirstName => 'Pat';
  @override
  String? get ssoLastName => 'Doe';
  @override
  bool get ssoAllowAccountCreation => allowCreate;
  @override
  bool get ssoHasPendingInvitation => invitation;
  @override
  String? get errorMessage => error;
  @override
  bool get isLoading => false;

  @override
  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  void cancelSsoOnboarding() => cancels++;

  @override
  Future<bool> ssoLinkAccount({
    required String email,
    required String password,
  }) async {
    links.add('$email:$password');
    return false;
  }

  @override
  Future<bool> ssoCreateAccount({String? firstName, String? lastName}) async {
    creates.add('$firstName $lastName');
    return false;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  AuthProvider? auth,
  Brightness brightness = Brightness.light,
  double width = 390,
  TargetPlatform? platform,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = brightness == Brightness.dark ? SureTheme.dark : SureTheme.light;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: auth ?? _FakeSsoAuth()),
        ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false)),
      ],
      child: MaterialApp(
        theme: platform == null ? theme : theme.copyWith(platform: platform),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    ),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('SsoOnboardingScreen', () {
    testWidgets('large title, signed-in subtitle and a back link that cancels',
        (tester) async {
      final auth = _FakeSsoAuth();
      await _pump(tester, const SsoOnboardingScreen(), auth: auth);
      await tester.pumpAndSettle();

      expect(find.byType(SureLargeTitleHeader), findsOneWidget);
      expect(find.text('Link Your Account'), findsWidgets);
      expect(find.text('Signed in as pat@example.test'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);

      await tester.tap(find.byType(SureBackButton));
      expect(auth.cancels, 1);
    });

    testWidgets('links with the prefilled email in a panel form',
        (tester) async {
      final auth = _FakeSsoAuth();
      await _pump(tester, const SsoOnboardingScreen(), auth: auth);
      await tester.pumpAndSettle();

      expect(find.byType(SureSegmentedControl<bool>), findsOneWidget);
      expect(find.byType(AuthNotePanel), findsOneWidget);
      expect(
        find.ancestor(
            of: find.byKey(const ValueKey('sso-link-password')),
            matching: find.byType(SurePanel)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('sso-link-submit')));
      await tester.pump();
      expect(find.text('Password is required'), findsOneWidget);
      expect(auth.links, isEmpty);

      await tester.enterText(
          find.byKey(const ValueKey('sso-link-password')), 'pw');
      await tester.tap(find.byKey(const ValueKey('sso-link-submit')));
      await tester.pump();
      expect(auth.links, ['pat@example.test:pw']);
    });

    testWidgets('the segmented control switches to create with the SSO name',
        (tester) async {
      final auth = _FakeSsoAuth(invitation: true);
      await _pump(tester, const SsoOnboardingScreen(), auth: auth);
      await tester.pumpAndSettle();

      // The pending-invitation label is both the segment and the button.
      await tester.tap(find.text('Accept Invitation').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sso-create-first-name')), findsOneWidget);
      expect(find.text(
              'You have a pending invitation. Accept it to join an existing household.'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sso-create-submit')));
      await tester.pump();
      expect(auth.creates, ['Pat Doe']);
    });

    testWidgets('hides the segmented control when creation is not allowed',
        (tester) async {
      await _pump(tester, const SsoOnboardingScreen(),
          auth: _FakeSsoAuth(allowCreate: false));
      await tester.pumpAndSettle();
      expect(find.byType(SureSegmentedControl<bool>), findsNothing);
      expect(find.byKey(const ValueKey('sso-link-email')), findsOneWidget);
    });

    testWidgets('errors show as a dismissible destructive panel',
        (tester) async {
      await _pump(tester, const SsoOnboardingScreen(),
          auth: _FakeSsoAuth(error: 'Invalid email or password'));
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorPanel), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.byType(AuthErrorPanel), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits 320 px in Swedish ($brightness)', (tester) async {
        await _pump(tester, const SsoOnboardingScreen(),
            auth: _FakeSsoAuth(invitation: true, error: 'Fel'),
            brightness: brightness,
            width: 320,
            locale: const Locale('sv'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('BiometricLockScreen', () {
    testWidgets('logo, locked title, inverse unlock and a quiet log-out link',
        (tester) async {
      var unlocked = 0;
      var loggedOut = 0;
      var prompts = 0;
      await _pump(
        tester,
        BiometricLockScreen(
          onUnlocked: () => unlocked++,
          onLogout: () => loggedOut++,
          authenticate: () async {
            prompts++;
            return prompts > 1;
          },
          loadBiometrics: () async => const [BiometricType.face],
        ),
        platform: TargetPlatform.iOS,
      );
      await tester.pumpAndSettle();

      // The prompt opens on its own; the first attempt fails.
      expect(prompts, 1);
      expect(unlocked, 0);
      expect(find.text('Authentication failed. Tap Unlock to try again.'),
          findsOneWidget);

      expect(find.text('Sure+ is locked'), findsOneWidget);
      final unlock = tester
          .widget<SureButton>(find.byKey(const ValueKey('biometric-unlock')));
      expect(unlock.label, 'Unlock with Face ID');
      expect(unlock.variant, SureButtonVariant.primary);
      expect(find.byType(FilledButton), findsNothing);

      // Retry from the button.
      await tester.tap(find.byKey(const ValueKey('biometric-unlock')));
      await tester.pumpAndSettle();
      expect(prompts, 2);
      expect(unlocked, 1);

      await tester.tap(find.byKey(const ValueKey('biometric-log-out')));
      expect(loggedOut, 1);
    });

    testWidgets('no log-out link without onLogout', (tester) async {
      await _pump(
        tester,
        BiometricLockScreen(
          onUnlocked: () {},
          authenticate: () async => false,
          loadBiometrics: () async => const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biometric-log-out')), findsNothing);
    });

    test('unlock label names Face ID or Touch ID on iOS only', () {
      final l = AppLocalizationsEn();
      expect(biometricUnlockLabel(l, const [BiometricType.face], TargetPlatform.iOS),
          'Unlock with Face ID');
      expect(
          biometricUnlockLabel(
              l, const [BiometricType.fingerprint], TargetPlatform.iOS),
          'Unlock with Touch ID');
      expect(
          biometricUnlockLabel(
              l, const [BiometricType.fingerprint], TargetPlatform.android),
          'Unlock');
      expect(biometricUnlockLabel(l, const [], TargetPlatform.iOS), 'Unlock');
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits 320 px in Swedish ($brightness)', (tester) async {
        await _pump(
          tester,
          BiometricLockScreen(
            onUnlocked: () {},
            onLogout: () {},
            authenticate: () async => false,
            loadBiometrics: () async => const [BiometricType.fingerprint],
          ),
          brightness: brightness,
          width: 320,
          platform: TargetPlatform.iOS,
          locale: const Locale('sv'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Lås upp med Touch ID'), findsOneWidget);
      });
    }
  });

  group('IntroScreen', () {
    testWidgets('large title and the placeholder as an empty-state panel',
        (tester) async {
      await _pump(tester, const Scaffold(body: IntroScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(SureLargeTitleHeader), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      final panel = find.byKey(const ValueKey('intro-panel'));
      expect(
        find.descendant(of: panel, matching: find.byType(SureEmptyState)),
        findsOneWidget,
      );
      expect(find.text('Intro experience coming soon'), findsOneWidget);
    });

    testWidgets('is localized', (tester) async {
      await _pump(tester, const Scaffold(body: IntroScreen()),
          locale: const Locale('sv'), width: 320);
      await tester.pumpAndSettle();
      expect(find.text('Introduktionen kommer snart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('the auth screens\' Lucide icons ship as SVGs', () {
    // Files are read relative to the package root when tests run.
    for (final name in [
      AuthIcons.logIn,
      AuthIcons.link,
      AuthIcons.userPlus,
      AuthIcons.scanFace,
      AuthIcons.fingerprint,
      AuthIcons.mail,
      AuthIcons.shield,
      AuthIcons.key,
    ]) {
      expect(
        File('assets/icons/lucide/$name.svg').existsSync(),
        isTrue,
        reason: name,
      );
    }
  });
}
