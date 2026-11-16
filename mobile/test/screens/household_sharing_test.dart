import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/household_screen.dart';
import 'package:sure_mobile/screens/sharing_screens.dart';
import 'package:sure_mobile/screens/web_view_screen.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/household_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_actions_menu.dart';
import 'package:sure_mobile/widgets/household_settings_rows.dart';

import '../support/home_fixtures.dart';

/// A fake server: answers `METHOD /path` from [routes] and records requests.
class _Server {
  _Server(this.routes);

  final Map<String, http.Response Function(http.Request request)> routes;
  final requests = <http.Request>[];

  HouseholdService get service =>
      HouseholdService(client: MockClient((request) async {
        requests.add(request);
        final key = '${request.method} ${request.url.path}';
        final handler = routes[key];
        if (handler == null) return http.Response('{"error":"nope"}', 404);
        return handler(request);
      }));

  List<http.Request> sent(String method, String path) => requests
      .where((r) => r.method == method && r.url.path == path)
      .toList();
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, dynamic> _household({
  bool admin = true,
  String delivery = 'link_only',
}) =>
    {
      'members': [
        {
          'id': 'u1',
          'name': 'Ada Lovelace',
          'email': 'ada@example.com',
          'role': 'admin',
          'avatar_url': null,
          'is_current_user': true,
        },
        {
          'id': 'u2',
          'name': 'Bob Smith',
          'email': 'bob@example.com',
          'role': 'member',
          'avatar_url': null,
          'is_current_user': false,
        },
      ],
      'pending_invitations': [
        {
          'id': 'i1',
          'email': 'cleo@example.com',
          'role': 'guest',
          'created_at': '2026-11-10T10:00:00Z',
          'expires_at': '2026-11-17T10:00:00Z',
        },
      ],
      'can_manage_invitations': admin,
      'invitations_enabled': true,
      'invitation_delivery': delivery,
    };

class _PushRecorder extends NavigatorObserver {
  final pushed = <Widget>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && previousRoute != null) {
      pushed.add(route.builder(navigator!.context));
    }
  }
}

Future<_PushRecorder> _pump(
  WidgetTester tester,
  Widget home, {
  Set<String> features = const {},
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final observer = _PushRecorder();
  final provider = ServerFeaturesProvider()..debugSet(features);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
        ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false)),
        ChangeNotifierProvider<ServerFeaturesProvider>.value(value: provider),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [observer],
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return observer;
}

Future<String?> _token() async => 'token';

void main() {
  late String previousBaseUrl;

  setUp(() {
    previousBaseUrl = ApiConfig.baseUrl;
    ApiConfig.setBaseUrl('https://sure.example.com');
  });
  tearDown(() => ApiConfig.setBaseUrl(previousBaseUrl));

  group('Settings household rows', () {
    Widget rows(_Server server) => Scaffold(
          body: HouseholdSettingsRows(
              service: server.service, accessTokenLoader: _token),
        );

    testWidgets('without the features nothing shows and nothing loads',
        (tester) async {
      final server = _Server({});
      await _pump(tester, rows(server));
      expect(find.text('Household'), findsNothing);
      expect(find.text('Budget sharing'), findsNothing);
      expect(server.requests, isEmpty);
    });

    testWidgets('household.members shows the Household row', (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
      });
      final observer = await _pump(tester, rows(server),
          features: {ServerFeaturesProvider.householdMembers});
      expect(find.byKey(const ValueKey('settingsHouseholdRow')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settingsBudgetSharingRow')),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('settingsHouseholdRow')));
      await tester.pumpAndSettle();
      expect(observer.pushed.single, isA<HouseholdScreen>());
    });

    testWidgets('Budget sharing shows only when personal_budgets is true',
        (tester) async {
      for (final personal in [true, false]) {
        final server = _Server({
          'GET /api/v1/budget_shares': (_) => _json({
                'personal_budgets': personal,
                'permissions': ['read_write', 'read_only'],
                'members': [],
              }),
        });
        await _pump(tester, rows(server),
            features: {ServerFeaturesProvider.budgetsSharing});
        expect(find.byKey(const ValueKey('settingsBudgetSharingRow')),
            personal ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a failed budget_shares GET hides Budget sharing',
        (tester) async {
      final server = _Server({
        'GET /api/v1/budget_shares': (_) =>
            _json({'error': 'insufficient_scope'}, 403),
      });
      await _pump(tester, rows(server),
          features: {ServerFeaturesProvider.budgetsSharing});
      expect(find.byKey(const ValueKey('settingsBudgetSharingRow')),
          findsNothing);
    });
  });

  group('Household screen', () {
    testWidgets('lists members, invitations and the link-only note',
        (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
      });
      final observer = await _pump(
          tester, HouseholdScreen(service: server.service, accessTokenLoader: _token));
      expect(find.text('Ada Lovelace (you)'), findsOneWidget);
      expect(find.text('Bob Smith'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('cleo@example.com'), findsOneWidget);
      expect(find.textContaining('Guest · expires '), findsOneWidget);
      expect(find.byKey(const ValueKey('householdInvite')), findsOneWidget);
      expect(find.byKey(const ValueKey('householdLinkOnlyNote')),
          findsOneWidget);

      // Not pumped: the web view has no platform implementation in tests.
      await tester.tap(find.byKey(const ValueKey('householdOpenProfileOnWeb')));
      expect((observer.pushed.single as WebViewScreen).path, '/settings/profile');
    });

    testWidgets('non-admins get no "+" and no revoke swipe', (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) =>
            _json(_household(admin: false, delivery: 'email')),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token));
      expect(find.byKey(const ValueKey('householdInvite')), findsNothing);
      expect(find.byKey(const ValueKey('invitation-i1')), findsNothing);
      expect(find.byKey(const ValueKey('householdLinkOnlyNote')), findsNothing);
    });

    testWidgets('invite sends email and role, then reloads', (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
        'POST /api/v1/invitations': (_) =>
            _json({'id': 'i2', 'delivery': 'link_only'}, 201),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token));
      await tester.tap(find.byKey(const ValueKey('householdInvite')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('inviteEmail')), 'dan@example.com');
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('inviteRole')),
          matching: find.text('Guest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inviteSubmit')));
      await tester.pumpAndSettle();

      final post = server.sent('POST', '/api/v1/invitations').single;
      expect(jsonDecode(post.body), {
        'invitation': {'email': 'dan@example.com', 'role': 'guest'},
      });
      expect(find.textContaining('Invitation created'), findsOneWidget);
      expect(server.sent('GET', '/api/v1/family/members'), hasLength(2));
    });

    testWidgets('an invalid email is refused before sending', (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token));
      await tester.tap(find.byKey(const ValueKey('householdInvite')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('inviteEmail')), 'dan');
      await tester.tap(find.byKey(const ValueKey('inviteSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter an email address'), findsOneWidget);
      expect(server.sent('POST', '/api/v1/invitations'), isEmpty);
    });

    testWidgets('a 422 shows the server message in the sheet',
        (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
        'POST /api/v1/invitations': (_) => _json({
              'error': 'validation_failed',
              'message': 'This person is already a member of your household.',
            }, 422),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token));
      await tester.tap(find.byKey(const ValueKey('householdInvite')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('inviteEmail')), 'bob@example.com');
      await tester.tap(find.byKey(const ValueKey('inviteSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('This person is already a member of your household.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('inviteSubmit')), findsOneWidget);
    });

    testWidgets('swipe Revoke asks, then deletes the invitation',
        (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
        'DELETE /api/v1/invitations/i1': (_) => http.Response('', 204),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token));
      await tester.drag(
          find.byKey(const ValueKey('invitation-i1')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(find.text('Revoke the invitation to cleo@example.com?'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
      await tester.pumpAndSettle();
      expect(server.sent('DELETE', '/api/v1/invitations/i1'), hasLength(1));
      expect(find.text('Invitation revoked'), findsOneWidget);
    });

    testWidgets('fits a 320 pt screen', (tester) async {
      final server = _Server({
        'GET /api/v1/family/members': (_) => _json(_household()),
      });
      await _pump(tester,
          HouseholdScreen(service: server.service, accessTokenLoader: _token),
          width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('Account sharing', () {
    final account = Account(
      id: 'a1',
      name: 'Checking',
      balance: r'$10.00',
      balanceCents: 1000,
      currency: 'USD',
      classification: 'asset',
      accountType: 'depository',
    );

    Widget menu() => Scaffold(
          appBar: AppBar(actions: [
            AccountActionsMenu(account: account, onChanged: () {}),
          ]),
        );

    testWidgets('the ⋯ menu offers Sharing only with accounts.sharing',
        (tester) async {
      await _pump(tester, menu());
      await tester.tap(find.byType(AccountActionsMenu));
      await tester.pumpAndSettle();
      expect(find.text('Sharing'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final observer = await _pump(tester, menu(),
          features: {ServerFeaturesProvider.accountsSharing});
      await tester.tap(find.byType(AccountActionsMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sharing'));
      await tester.pump();
      final screen = observer.pushed.single as AccountSharingScreen;
      expect(screen.accountId, 'a1');
    });

    Map<String, dynamic> ownerSharing(String bob) => {
          'account_id': 'a1',
          'is_owner': true,
          'owner': {'id': 'u1', 'name': 'Ada'},
          'permission': null,
          'include_in_finances': null,
          'permissions': ['full_control', 'read_write', 'read_only'],
          'members': [
            {'user_id': 'u2', 'name': 'Bob Smith', 'permission': bob},
          ],
        };

    SureSegmentedControlFinder seg(String userId) =>
        SureSegmentedControlFinder(userId);

    testWidgets('the owner changes one member optimistically', (tester) async {
      final server = _Server({
        'GET /api/v1/accounts/a1/sharing': (_) => _json(ownerSharing('none')),
        'PATCH /api/v1/accounts/a1/sharing': (_) =>
            _json(ownerSharing('read_write')),
      });
      await _pump(
          tester,
          AccountSharingScreen(
              accountId: 'a1',
              service: server.service,
              accessTokenLoader: _token));
      expect(find.text('Bob Smith'), findsOneWidget);
      expect(seg('u2').selected(tester), 'none');
      await tester.tap(seg('u2').label('Edit'));
      await tester.pumpAndSettle();
      final patch = server.sent('PATCH', '/api/v1/accounts/a1/sharing').single;
      expect(jsonDecode(patch.body), {
        'sharing': {
          'members': [
            {'user_id': 'u2', 'permission': 'read_write'},
          ],
        },
      });
      expect(seg('u2').selected(tester), 'read_write');
    });

    testWidgets('a refused change goes back and shows the message',
        (tester) async {
      final server = _Server({
        'GET /api/v1/accounts/a1/sharing': (_) =>
            _json(ownerSharing('read_only')),
        'PATCH /api/v1/accounts/a1/sharing': (_) => _json({
              'error': 'insufficient_scope',
              'message': 'This key is read-only.',
            }, 403),
      });
      await _pump(
          tester,
          AccountSharingScreen(
              accountId: 'a1',
              service: server.service,
              accessTokenLoader: _token));
      await tester.tap(seg('u2').label('Full'));
      await tester.pumpAndSettle();
      expect(seg('u2').selected(tester), 'read_only');
      expect(find.text('This key is read-only.'), findsOneWidget);
    });

    testWidgets('someone it is shared with sees the owner and the switch',
        (tester) async {
      Map<String, dynamic> shared(bool include) => {
            'account_id': 'a1',
            'is_owner': false,
            'owner': {'id': 'u1', 'name': 'Ada'},
            'permission': 'read_only',
            'include_in_finances': include,
            'permissions': ['full_control', 'read_write', 'read_only'],
            'members': [],
          };
      final server = _Server({
        'GET /api/v1/accounts/a1/sharing': (_) => _json(shared(true)),
        'PATCH /api/v1/accounts/a1/sharing': (_) => _json(shared(false)),
      });
      await _pump(
          tester,
          AccountSharingScreen(
              accountId: 'a1',
              service: server.service,
              accessTokenLoader: _token));
      expect(find.text('Shared by Ada · View only'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('includeInFinancesSwitch')));
      await tester.pumpAndSettle();
      final patch = server.sent('PATCH', '/api/v1/accounts/a1/sharing').single;
      expect(jsonDecode(patch.body), {
        'sharing': {'include_in_finances': false},
      });
      final toggle = tester.widget<Switch>(
          find.byKey(const ValueKey('includeInFinancesSwitch')));
      expect(toggle.value, isFalse);
    });
  });

  testWidgets('budget sharing offers None, View and Edit and PATCHes',
      (tester) async {
    Map<String, dynamic> body(String p) => {
          'personal_budgets': true,
          'permissions': ['read_write', 'read_only'],
          'members': [
            {'user_id': 'u2', 'name': 'Bob Smith', 'permission': p},
          ],
        };
    final server = _Server({
      'GET /api/v1/budget_shares': (_) => _json(body('none')),
      'PATCH /api/v1/budget_shares': (_) => _json(body('read_only')),
    });
    await _pump(tester,
        BudgetSharingScreen(service: server.service, accessTokenLoader: _token),
        width: 320);
    expect(find.text('Full'), findsNothing);
    await tester.tap(SureSegmentedControlFinder('u2').label('View'));
    await tester.pumpAndSettle();
    final patch = server.sent('PATCH', '/api/v1/budget_shares').single;
    expect(jsonDecode(patch.body), {
      'budget_shares': {
        'members': [
          {'user_id': 'u2', 'permission': 'read_only'},
        ],
      },
    });
    expect(tester.takeException(), isNull);
  });
}

/// Finds the permission control of one member's [ShareMemberRow].
class SureSegmentedControlFinder {
  SureSegmentedControlFinder(this.userId);

  final String userId;

  Finder get control => find.byKey(ValueKey('shareMember-$userId'));

  Finder label(String text) =>
      find.descendant(of: control, matching: find.text(text));

  String selected(WidgetTester tester) => tester
      .widget<ShareMemberRow>(find.ancestor(
          of: control, matching: find.byType(ShareMemberRow)))
      .member
      .permission;
}
