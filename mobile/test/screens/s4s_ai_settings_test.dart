import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/ai_settings.dart';
import 'package:sure_mobile/screens/ai_settings_screen.dart';
import 'package:sure_mobile/screens/classifier_settings_screen.dart';
import 'package:sure_mobile/services/ai_settings_service.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _settings({
  bool ruleActive = false,
  bool customChat = false,
  bool formatRisk = false,
}) =>
    {
      'ai_settings': {
        'ai_available': true,
        'ai_enabled': true,
        'prompt_max_length': 100,
        'prompts': [
          {
            'key': 'chat_system',
            'value': customChat ? 'Be brief.' : null,
            'default': 'You are a helpful assistant.',
            'custom': customChat,
            'format_risk': false,
            'format_risk_key': null,
          },
          {
            'key': 'categorizer_openai',
            'value': formatRisk ? 'Categorize.' : null,
            'default': 'Return {"categorizations": []}',
            'custom': formatRisk,
            'format_risk': formatRisk,
            'format_risk_key': 'categorizations',
          },
        ],
        'classifier': {
          'settings': {
            'skip_self_labels': true,
            'self_label_grace_days': 90,
            'max_training_transactions': 5000,
            'word_split': 'ascii',
            'threshold': 0.7,
            'smoothing': 1.0,
            'similar_min_neighbours': 2,
            'excluded_category_ids': <String>[],
          },
          'defaults': {
            'skip_self_labels': true,
            'self_label_grace_days': 90,
            'max_training_transactions': 5000,
            'word_split': 'ascii',
            'threshold': 0.7,
            'smoothing': 1.0,
            'similar_min_neighbours': 2,
            'excluded_category_ids': <String>[],
          },
          'default': true,
          'ranges': {
            'self_label_grace_days': {'min': 1, 'max': 3650},
            'max_training_transactions': {'min': 100, 'max': 20000},
            'threshold': {'min': 0.05, 'max': 0.99},
            'smoothing': {'min': 0.001, 'max': 10.0},
            'similar_min_neighbours': {'min': 1, 'max': 3},
          },
          'choices': {
            'word_split': ['ascii', 'unicode', 'symbols'],
          },
          'rules': [
            {
              'action_type': 'fill_similar_merchants',
              'name': 'Merchant matcher',
              'exists': true,
              'active': true,
            },
            {
              'action_type': 'bayes_categorize',
              'name': 'Category classifier',
              'exists': true,
              'active': ruleActive,
            },
          ],
          'evaluation': {'running': false},
        },
      },
    };

final _usage = {
  'llm_usage': {
    'total_requests': 42,
    'total_cost': r'$0.00',
    'total_cost_cents': 0,
    'total_cost_amount': '0.0031',
    'by_model': [
      {
        'model': 'gpt-4.1-mini',
        'total_requests': 42,
        'total_tokens': 1000,
        'cost': r'$0.0031',
        'cost_cents': 0,
        'cost_amount': '0.0031',
      },
    ],
  },
};

void main() {
  Future<void> pump(WidgetTester tester, MockClient client,
          {VoidCallback? onForbidden}) =>
      pumpLocalized(
        tester,
        AiSettingsScreen(
          service: AiSettingsService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          onForbidden: onForbidden,
        ),
      );

  http.Response? route(http.Request request) {
    if (request.method == 'GET' && request.url.path.endsWith('/usage')) {
      return http.Response(jsonEncode(_usage), 200);
    }
    if (request.method == 'GET') {
      return http.Response(jsonEncode(_settings()), 200);
    }
    return null;
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);

  test('cost shows the unrounded amount below a cent', () {
    expect(aiCostLabel(AiUsage.fromJson(_usage)), r'$0.0031');
    expect(
        aiCostLabel(const AiUsage(totalCost: r'$1.20', totalCostAmount: '1.2')),
        r'$1.20');
  });

  testWidgets('shows the classifier, prompts and usage', (tester) async {
    await pump(tester, MockClient((r) async => route(r)!));
    expect(find.text('Categorize with the classifier'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
    expect(find.text('Clear category locks'), findsOneWidget);
    expect(find.text('Classifier settings'), findsOneWidget);
    expect(find.text('Chat system prompt'), findsOneWidget);
    expect(find.text('Categorizer (OpenAI)'), findsOneWidget);
    expect(find.text('Default'), findsNWidgets(2));
    await scrollTo(tester, find.text('By model'));
    expect(find.text(r'$0.0031'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);

    await tester.tap(find.text('By model'));
    await tester.pumpAndSettle();
    expect(find.text('gpt-4.1-mini'), findsOneWidget);
    expect(find.text('42 requests'), findsOneWidget);
  });

  testWidgets('the switch PATCHes rules_active', (tester) async {
    final patches = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return http.Response(jsonEncode(_settings(ruleActive: true)), 200);
        }
        return route(request)!;
      }),
    );
    await tester.tap(find.byKey(const ValueKey('aiClassifierSwitch')));
    await tester.pumpAndSettle();
    expect(jsonDecode(patches.single.body), {
      'ai_settings': {
        'classifier': {
          'rules_active': {'bayes_categorize': true},
        },
      },
    });
    final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('aiClassifierSwitch')));
    expect(toggle.value, isTrue);
  });

  testWidgets('classifier_rule_missing offers to add the rule again',
      (tester) async {
    final posts = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response(
              jsonEncode({
                'error': 'classifier_rule_missing',
                'message': 'The rule was deleted.',
              }),
              422);
        }
        if (request.method == 'POST') {
          posts.add(request);
          return http.Response(jsonEncode(_settings()), 201);
        }
        return route(request)!;
      }),
    );
    await tester.tap(find.byKey(const ValueKey('aiClassifierSwitch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aiRuleMissingBanner')), findsOneWidget);
    expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('aiClassifierSwitch')))
            .value,
        isFalse);

    await tester.tap(find.text('Add the classifier rule again'));
    await tester.pumpAndSettle();
    expect(posts.single.url.path, '/api/v1/settings/ai/classifier/rules');
    expect(jsonDecode(posts.single.body), {'action_type': 'bayes_categorize'});
    expect(find.byKey(const ValueKey('aiRuleMissingBanner')), findsNothing);
    expect(find.text('Classifier rule added'), findsOneWidget);
  });

  testWidgets('Run now and Clear locks confirm, then show Queued',
      (tester) async {
    final posts = <String>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts.add(request.url.path);
          return http.Response(
              jsonEncode({
                'data': {'status': 'queued', 'job': 'classifier_run'},
              }),
              202);
        }
        return route(request)!;
      }),
    );

    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();
    expect(find.text('Run the classifier now?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);

    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/v1/settings/ai/classifier/run']);
    expect(find.text('Queued'), findsOneWidget);

    await tester.tap(find.text('Clear category locks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear locks'));
    await tester.pumpAndSettle();
    expect(posts.last, '/api/v1/settings/ai/classifier/clear_locks');
  });

  testWidgets('a prompt sheet counts characters, warns and resets',
      (tester) async {
    final patches = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return http.Response(jsonEncode(_settings()), 200);
        }
        if (request.method == 'GET' && !request.url.path.endsWith('/usage')) {
          return http.Response(jsonEncode(_settings(formatRisk: true)), 200);
        }
        return route(request)!;
      }),
    );
    expect(find.text('Custom'), findsOneWidget);
    await tester.tap(find.text('Categorizer (OpenAI)'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('aiPromptFormatRisk')), findsOneWidget);
    expect(find.textContaining('“categorizations”'), findsOneWidget);
    expect(find.text('11 / 100'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('aiPromptField')), 'x' * 101);
    await tester.pump();
    expect(find.text('101 / 100'), findsOneWidget);
    expect(find.text('This prompt is too long.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aiPromptSave')));
    await tester.pumpAndSettle();
    expect(patches, isEmpty);

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(jsonDecode(patches.single.body), {
      'ai_settings': {
        'prompts': {'categorizer_openai': ''},
      },
    });
    expect(find.text('Prompt saved'), findsOneWidget);
  });

  testWidgets('saving an edited prompt sends its text', (tester) async {
    final patches = <http.Request>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return http.Response(jsonEncode(_settings(customChat: true)), 200);
        }
        return route(request)!;
      }),
    );
    await tester.tap(find.text('Chat system prompt'));
    await tester.pumpAndSettle();
    // The default prefills the field and has no reset.
    expect(find.text('You are a helpful assistant.'), findsOneWidget);
    expect(find.text('Reset to default'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('aiPromptField')), 'Be brief.');
    await tester.tap(find.byKey(const ValueKey('aiPromptSave')));
    await tester.pumpAndSettle();
    expect(jsonDecode(patches.single.body), {
      'ai_settings': {
        'prompts': {'chat_system': 'Be brief.'},
      },
    });
    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('a 403 reports forbidden and shows the message', (tester) async {
    var forbidden = 0;
    await pump(
      tester,
      MockClient((_) async => http.Response(
          jsonEncode({
            'error': 'forbidden',
            'message': 'AI settings require a family admin',
          }),
          403)),
      onForbidden: () => forbidden++,
    );
    expect(forbidden, 1);
    expect(find.text('AI settings require a family admin'), findsOneWidget);
  });

  testWidgets('fits a 320 px screen, banner included', (tester) async {
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response(
              jsonEncode({'error': 'classifier_rule_missing', 'message': 'x'}),
              422);
        }
        return route(request)!;
      }),
    );
    tester.view.physicalSize = const Size(960, 1920);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aiClassifierSwitch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aiRuleMissingBanner')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Classifier settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('classifier settings', () {
    Future<List<Map<String, dynamic>>> pumpSettings(WidgetTester tester,
        {bool fail = false}) async {
      final saves = <Map<String, dynamic>>[];
      final initial =
          AiSettings.fromJson(_settings()).classifier;
      await pumpLocalized(
        tester,
        ClassifierSettingsScreen(
          initial: initial,
          saveDelay: const Duration(milliseconds: 100),
          onSave: (values) async {
            saves.add(values);
            if (fail) return null;
            final next = {...initial.settings, ...values};
            return ClassifierSettings(
              settings: next,
              defaults: initial.defaults,
              ranges: initial.ranges,
              choices: initial.choices,
              rules: initial.rules,
            );
          },
        ),
      );
      return saves;
    }

    test('number controls', () {
      expect(classifierNumberControl(const SettingRange(0.05, 0.99), false),
          (slider: true, step: 0.01));
      expect(classifierNumberControl(const SettingRange(1, 3), true),
          (slider: false, step: 1));
      expect(classifierNumberControl(const SettingRange(1, 3650), true),
          (slider: false, step: 30));
      expect(classifierNumberControl(const SettingRange(100, 20000), true),
          (slider: false, step: 100));
    });

    testWidgets('builds rows from settings, ranges and choices',
        (tester) async {
      await pumpSettings(tester);
      expect(find.text("Don't learn from its own unconfirmed guesses"),
          findsOneWidget);
      expect(find.text('Words are made of'), findsOneWidget);
      expect(find.text('a–z, 0–9'), findsOneWidget);
      expect(find.text('Threshold'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Merchants agreeing'), findsOneWidget);
      // The category list has no native control.
      expect(find.textContaining('Excluded'), findsNothing);
    });

    testWidgets('a switch saves at once, a stepper after a pause',
        (tester) async {
      final saves = await pumpSettings(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('cls-skip_self_labels')),
          matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(saves.single, {'skip_self_labels': false});

      final plus = find.descendant(
          of: find.byKey(const ValueKey('cls-similar_min_neighbours')),
          matching: find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Increase'));
      await tester.tap(plus);
      await tester.pump();
      expect(saves, hasLength(1));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(saves.last, {'similar_min_neighbours': 3});
      // At the maximum the plus button is off.
      expect(tester.widget<IconButton>(plus).onPressed, isNull);
    });

    testWidgets('a choice opens a picker and saves it', (tester) async {
      final saves = await pumpSettings(tester);
      await tester.tap(find.text('Words are made of'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any script'));
      await tester.pumpAndSettle();
      expect(saves.single, {'word_split': 'unicode'});
      expect(find.text('Any script'), findsOneWidget);
    });

    testWidgets('a failed save puts the old value back', (tester) async {
      await pumpSettings(tester, fail: true);
      final toggle = find.descendant(
          of: find.byKey(const ValueKey('cls-skip_self_labels')),
          matching: find.byType(Switch));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
    });
  });
}
