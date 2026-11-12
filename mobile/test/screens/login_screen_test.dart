import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/sso_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/screens/auth_fields.dart';
import 'package:sure_mobile/screens/login_screen.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/sure_button.dart';

class _FakeAuthProvider extends AuthProvider {
  final List<SsoProvider>? providers;
  String? error;
  bool mfa;
  final logins = <Map<String, String?>>[];

  _FakeAuthProvider(this.providers, {this.error, this.mfa = false});

  @override
  Future<List<SsoProvider>?> fetchSsoProviders() async => providers;

  @override
  String? get errorMessage => error;

  @override
  bool get showMfaInput => mfa;

  @override
  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  Future<bool> login({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    logins.add({'email': email, 'password': password, 'otp': otpCode});
    return false;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<_FakeAuthProvider> pumpLogin(
    WidgetTester tester,
    List<SsoProvider>? providers, {
    String? error,
    bool mfa = false,
    VoidCallback? onGoToSettings,
    Brightness brightness = Brightness.light,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _FakeAuthProvider(providers, error: error, mfa: mfa);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme:
              brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LoginScreen(onGoToSettings: onGoToSettings),
        ),
      ),
    );
    return auth;
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<TextFormField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  testWidgets('renders one button per configured SSO provider', (tester) async {
    await pumpLogin(tester, const [
      SsoProvider(
          name: 'openid_connect',
          strategy: 'openid_connect',
          label: 'Authentik'),
      SsoProvider(
          name: 'google_oauth2',
          strategy: 'google_oauth2',
          label: 'Sign in with Google'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Authentik'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('hides SSO when no providers are configured', (tester) async {
    await pumpLogin(tester, const []);
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.text('or'), findsNothing);
  });

  testWidgets('falls back to Google when the provider list is unavailable',
      (tester) async {
    await pumpLogin(tester, null);
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows the large title, fields in one panel, an inverse primary '
      'and outline SSO buttons', (tester) async {
    await pumpLogin(tester, null);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-title')), findsOneWidget);
    expect(find.text('Demo account or Sign Up!', findRichText: true),
        findsOneWidget);

    final fieldsPanel = find.ancestor(
      of: find.byKey(const ValueKey('login-email')),
      matching: find.byType(SurePanel),
    );
    expect(
      find.descendant(
          of: fieldsPanel, matching: find.byKey(const ValueKey('login-password'))),
      findsOneWidget,
    );

    final submit =
        tester.widget<SureButton>(find.byKey(const ValueKey('login-submit')));
    expect(submit.variant, SureButtonVariant.primary);
    expect(submit.fullWidth, isTrue);
    final google = tester.widget<SureButton>(find.ancestor(
      of: find.text('Sign in with Google'),
      matching: find.byType(SureButton),
    ));
    expect(google.variant, SureButtonVariant.outline);
    expect(find.byKey(const ValueKey('login-api-key')), findsOneWidget);
  });

  testWidgets('demo placeholders clear when their field is focused',
      (tester) async {
    await pumpLogin(tester, const []);
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'login-email'), 'user@example.com');
    expect(fieldText(tester, 'login-password'), 'Password1!');

    await tester.tap(find.byKey(const ValueKey('login-email')));
    await tester.pump();
    expect(fieldText(tester, 'login-email'), isEmpty);
    expect(fieldText(tester, 'login-password'), 'Password1!');

    await tester.tap(find.byKey(const ValueKey('login-password')));
    await tester.pump();
    expect(fieldText(tester, 'login-password'), isEmpty);
  });

  testWidgets('the eye button toggles the password between hidden and shown',
      (tester) async {
    await pumpLogin(tester, const []);
    await tester.pumpAndSettle();

    EditableText editable() => tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('login-password')),
        matching: find.byType(EditableText)));
    expect(editable().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(editable().obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('validates and signs in with the entered credentials',
      (tester) async {
    final auth = await pumpLogin(tester, const []);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('login-email')), 'nope');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(auth.logins, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('login-email')), ' a@b.test ');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'pw');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(auth.logins, [
      {'email': 'a@b.test', 'password': 'pw', 'otp': null},
    ]);
  });

  testWidgets('errors show as a destructive panel that can be dismissed',
      (tester) async {
    await pumpLogin(tester, const [], error: 'Invalid email or password');
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('auth-error-panel'));
    expect(panel, findsOneWidget);
    expect(find.descendant(
            of: panel, matching: find.text('Invalid email or password')),
        findsOneWidget);
    final context = tester.element(panel);
    final decoration =
        tester.widget<Container>(panel).decoration! as BoxDecoration;
    expect(decoration.color,
        SureColors.of(context).palette.destructive.withValues(alpha: 0.12));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(panel, findsNothing);
  });

  testWidgets('the MFA step adds a note and a code row and sends the code',
      (tester) async {
    final auth = await pumpLogin(tester, const [],
        mfa: true, error: 'Two-factor authentication required');
    await tester.pumpAndSettle();

    expect(find.byType(AuthNotePanel), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(find.text('Please enter your authentication code'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('login-otp')), ' 123456 ');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(auth.logins.single['otp'], '123456');
    // A failed attempt with a code clears it for the next try.
    expect(fieldText(tester, 'login-otp'), isEmpty);
  });

  testWidgets('the server row shows the URL and opens the backend settings',
      (tester) async {
    var opened = 0;
    await pumpLogin(tester, const [], onGoToSettings: () => opened++);
    await tester.pumpAndSettle();

    final row =
        tester.widget<SureListRow>(find.byKey(const ValueKey('login-server-row')));
    expect(row.title, 'Server');
    expect(row.showChevron, isTrue);
    expect(row.value, isNot(startsWith('http')));

    await tester.ensureVisible(find.byKey(const ValueKey('login-server-row')));
    await tester.tap(find.byKey(const ValueKey('login-server-row')));
    expect(opened, 1);
    await tester.tap(find.byTooltip('Backend Settings'));
    expect(opened, 2);
  });

  testWidgets('the API-key link opens the API-key sheet', (tester) async {
    await pumpLogin(tester, const []);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('login-api-key')));
    await tester.tap(find.byKey(const ValueKey('login-api-key')));
    await tester.pumpAndSettle();

    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.text('API Key Login'), findsOneWidget);
  });

  test('loginServerLabel drops the scheme', () {
    expect(loginServerLabel('https://app.example.test'), 'app.example.test');
    expect(loginServerLabel('http://10.0.2.2:3000'), '10.0.2.2:3000');
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits 320 px with MFA and an error ($brightness)',
        (tester) async {
      await pumpLogin(
        tester,
        const [
          SsoProvider(
              name: 'openid_connect',
              strategy: 'openid_connect',
              label: 'A provider with a fairly long name'),
        ],
        error: 'Invalid authentication code. Please try again.',
        mfa: true,
        brightness: brightness,
        width: 320,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
