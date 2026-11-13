import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/screens/profile_options.dart';
import 'package:sure_mobile/screens/profile_screen.dart';
import 'package:sure_mobile/services/profile_service.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Future<String?> _token() async => 'token';

Map<String, dynamic> _me({String first = 'Ada', String timezone = 'Europe/Stockholm'}) => {
      'id': 'u1',
      'email': 'ada@example.com',
      'first_name': first,
      'last_name': 'Lovelace',
      'display_name': '$first Lovelace',
      'role': 'admin',
      'locale': null,
      'theme': 'system',
      'default_period': 'last_30_days',
      'family': {
        'id': 'f1',
        'name': 'The Lovelaces',
        'currency': 'SEK',
        'country': 'SE',
        'timezone': timezone,
        'date_format': '%Y-%m-%d',
        'locale': 'en',
      },
    };

void main() {
  late List<String> requests;
  late List<Map<String, dynamic>> bodies;
  late http.Response Function(http.Request) onPatch;
  late List<(String?, String?)> names;

  setUp(() {
    requests = [];
    bodies = [];
    names = [];
    onPatch = (request) {
      final user = (jsonDecode(request.body) as Map)['user'] as Map;
      return http.Response(
          jsonEncode(_me(
              first: user['first_name'] as String? ?? 'Ada',
              timezone: ((user['family_attributes'] as Map?)?['timezone']
                      as String?) ??
                  'Europe/Stockholm')),
          200);
    };
  });

  Future<void> pump(WidgetTester tester, {int getStatus = 200}) async {
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        return http.Response(
            getStatus == 200 ? jsonEncode(_me()) : '{}', getStatus);
      }
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return onPatch(request);
    });
    await pumpLocalized(
      tester,
      ProfileScreen(
        service: ProfileService(client: client),
        accessTokenLoader: _token,
        onUnauthorized: () async {},
        onNameSaved: (first, last) async => names.add((first, last)),
      ),
      logicalHeight: 1400,
    );
  }

  String? valueOf(WidgetTester tester, String key) =>
      tester.widget<SureListRow>(find.byKey(ValueKey(key))).value;

  TextButton saveButton(WidgetTester tester) => tester.widget<TextButton>(
      find.descendant(
          of: find.byKey(const ValueKey('profileSave')),
          matching: find.byType(TextButton)));

  testWidgets('loads the profile and household preferences', (tester) async {
    await pump(tester);
    expect(requests, ['GET /api/v1/users/me']);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('The Lovelaces'), findsOneWidget);
    expect(find.text('Change on the web'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(valueOf(tester, 'profileLocale'), 'Automatic');
    expect(valueOf(tester, 'profileDefaultPeriod'), 'Last 30 days');
    expect(valueOf(tester, 'profileCurrency'), 'SEK');
    expect(valueOf(tester, 'profileCountry'), '🇸🇪 Sweden');
    expect(valueOf(tester, 'profileTimezone'), 'Europe/Stockholm');
    expect(valueOf(tester, 'profileDateFormat'), 'YYYY-MM-DD');
    expect(valueOf(tester, 'profileHouseholdLocale'), 'English (en)');
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('saves only the changed fields', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('profileFirstName')), 'Augusta');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('profileTimezone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(SureSearchField), matching: find.byType(TextField)),
        'Helsinki');
    await tester.pumpAndSettle();
    await tester.tap(find.text('(+02:00) Europe/Helsinki'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profileLocale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swedish (sv)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profileSave')));
    await tester.pumpAndSettle();

    expect(requests.last, 'PATCH /api/v1/users/me');
    expect(bodies.single, {
      'user': {
        'first_name': 'Augusta',
        'locale': 'sv',
        'family_attributes': {'timezone': 'Europe/Helsinki'},
      },
    });
    expect(names, [('Augusta', 'Lovelace')]);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('shows a 422 inline and keeps the edits', (tester) async {
    onPatch = (_) => http.Response(
        jsonEncode({
          'error': 'validation_failed',
          'message': 'Default period is not included in the list',
        }),
        422);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('profileDefaultPeriod')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profileSave')));
    await tester.pumpAndSettle();

    expect(bodies.single, {
      'user': {'default_period': 'all_time'},
    });
    expect(find.text('Default period is not included in the list'),
        findsOneWidget);
    expect(valueOf(tester, 'profileDefaultPeriod'), 'All time');
    expect(saveButton(tester).onPressed, isNotNull);
    expect(names, isEmpty);
  });

  testWidgets('lays out at 320 px without overflow', (tester) async {
    await pump(tester);
    tester.view.physicalSize = const Size(960, 1400 * 3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('🇸🇪 Sweden'), findsOneWidget);
  });

  testWidgets('a load failure offers to try again', (tester) async {
    await pump(tester, getStatus: 500);
    expect(find.byKey(const ValueKey('profileError')), findsOneWidget);
  });

  test('option lists come from the server sources', () {
    expect(kProfileDateFormats.length, 11);
    expect(kProfilePeriods.first, 'last_day');
    expect(kProfilePeriods.last, 'all_time');
    expect(kProfileCurrencies.first.$1, 'USD');
    expect(kProfileTimezones.any((t) => t.$1 == 'Europe/Kiev'), false);
    expect(kProfileTimezones.any((t) => t.$1 == 'Europe/Kyiv'), true);
  });
}
