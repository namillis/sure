import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/screens/login_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this.result);

  final bool result;
  final keys = <String>[];

  @override
  Future<bool> loginWithApiKey({required String apiKey}) async {
    keys.add(apiKey);
    return result;
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // Opens the API-key sheet with an injected controller and returns it so the
  // test can assert the sheet disposed it. A disposed ChangeNotifier throws
  // when used again, which is how we verify disposal.
  Future<(TextEditingController, ValueNotifier<bool?>)> openSheet(
    WidgetTester tester, {
    AuthProvider? auth,
  }) async {
    final controller = TextEditingController();
    final popped = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => auth ?? _FakeAuthProvider(true),
        child: MaterialApp(
          theme: SureTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped.value = await showSureSheet<bool>(
                    context: context,
                    builder: (_) => ApiKeyLoginDialog(controller: controller),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('API Key Login'), findsOneWidget);
    return (controller, popped);
  }

  void expectDisposed(TextEditingController controller) {
    expect(() => controller.addListener(() {}), throwsA(isA<FlutterError>()));
  }

  testWidgets('is a SureSheet with Cancel and a disabled Sign In until a key '
      'is typed', (tester) async {
    await openSheet(tester);

    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final action = find.byKey(const ValueKey('api-key-submit'));
    expect(tester.widget<TextButton>(action).onPressed, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('api-key-field')), 'sk-test');
    await tester.pump();
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
  });

  testWidgets('submits the trimmed key and pops the result', (tester) async {
    final auth = _FakeAuthProvider(false);
    final (_, popped) = await openSheet(tester, auth: auth);

    await tester.enterText(
        find.byKey(const ValueKey('api-key-field')), '  sk-test  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('api-key-submit')));
    await tester.pumpAndSettle();

    expect(auth.keys, ['sk-test']);
    expect(find.text('API Key Login'), findsNothing);
    expect(popped.value, isFalse);
  });

  testWidgets('disposes its controller when cancelled', (tester) async {
    final (controller, _) = await openSheet(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('API Key Login'), findsNothing);
    expectDisposed(controller);
  });

  testWidgets('disposes its controller when dismissed by a barrier tap',
      (tester) async {
    final (controller, _) = await openSheet(tester);

    // The sheet sizes to its content, so the top of the screen is barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('API Key Login'), findsNothing);
    expectDisposed(controller);
  });

  testWidgets('disposes its controller when dismissed by the system back button',
      (tester) async {
    final (controller, _) = await openSheet(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('API Key Login'), findsNothing);
    expectDisposed(controller);
  });
}
