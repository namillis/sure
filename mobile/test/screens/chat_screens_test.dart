import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/user.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/chat_provider.dart';
import 'package:sure_mobile/screens/chat_conversation_screen.dart';
import 'package:sure_mobile/screens/chat_list_screen.dart';
import 'package:sure_mobile/services/chat_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/chat_widgets.dart';

import '../support/home_fixtures.dart';

class _Auth extends FakeAuth {
  @override
  User? get user => null;
}

String _iso(DateTime t) => t.toUtc().toIso8601String();

Map<String, dynamic> _chatJson(String id, String title, DateTime last) => {
      'id': id,
      'title': title,
      'last_message_at': _iso(last),
      'message_count': 2,
      'error': null,
      'created_at': _iso(last),
      'updated_at': _iso(last),
    };

http.Response _list(List<Map<String, dynamic>> chats) => http.Response(
      jsonEncode({
        'chats': chats,
        'pagination': {
          'page': 1,
          'per_page': 20,
          'total_count': chats.length,
          'total_pages': 1,
        },
      }),
      200,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  MockClient client, {
  double width = 390,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(chatService: ChatService(client: client)),
      ),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('ChatListScreen', () {
    final now = DateTime.now();
    final older = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 8));

    MockClient listClient({List<String>? deleted}) =>
        MockClient((request) async {
          if (request.method == 'DELETE') {
            deleted?.add(request.url.path);
            return http.Response('', 204);
          }
          return _list([
            _chatJson('1', 'Groceries budget',
                now.subtract(const Duration(minutes: 5))),
            _chatJson('2', 'Net worth question', older),
          ]);
        });

    for (final brightness in Brightness.values) {
      testWidgets('large title, compose, search and day sections ($brightness)',
          (tester) async {
        await _pump(tester, const ChatListScreen(), listClient(),
            brightness: brightness);
        expect(find.text('Assistant'), findsWidgets);
        expect(find.bySemanticsLabel('New chat'), findsOneWidget);
        expect(find.text('Search chats'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('5m'), findsOneWidget);
        expect(find.byType(AssistantAvatar), findsNWidgets(2));
        // The old message-count badge is gone.
        expect(find.text('2'), findsNothing);
      });
    }

    testWidgets('search filters by title and shows no-matches', (tester) async {
      await _pump(tester, const ChatListScreen(), listClient());
      await tester.enterText(find.byType(TextField), 'grocer');
      await tester.pumpAndSettle();
      expect(find.text('Groceries budget'), findsOneWidget);
      expect(find.text('Net worth question'), findsNothing);

      await tester.enterText(find.byType(TextField), 'rent');
      await tester.pumpAndSettle();
      expect(find.text('No chats match “rent”'), findsOneWidget);
    });

    testWidgets('swipe left reveals Delete, which confirms then deletes',
        (tester) async {
      final deleted = <String>[];
      await _pump(tester, const ChatListScreen(), listClient(deleted: deleted));
      await tester.drag(find.text('Groceries budget'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      // Every row builds its (zero-width) action; the first row's is open.
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete Chat'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, ['/api/v1/chats/1']);
      expect(find.text('Groceries budget'), findsNothing);
    });

    testWidgets('long-press enters multi-select', (tester) async {
      await _pump(tester, const ChatListScreen(), listClient());
      await tester.longPress(find.text('Groceries budget'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsWidgets);
      expect(find.byType(ChatSelectionCircle), findsNWidgets(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSelectionCircle), findsNothing);
    });

    testWidgets('empty list shows the sparkles empty state', (tester) async {
      await _pump(tester, const ChatListScreen(),
          MockClient((_) async => _list([])));
      expect(find.text('Ask about your money'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'New chat'), findsOneWidget);
    });

    testWidgets('load error offers Try Again', (tester) async {
      await _pump(tester, const ChatListScreen(),
          MockClient((_) async => http.Response('{"error":"boom"}', 500)));
      expect(find.text('Failed to load chats'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('no overflow at 320 px', (tester) async {
      await _pump(tester, const ChatListScreen(), listClient(), width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatConversationScreen', () {
    final t = DateTime(2026, 11, 11, 10);

    Map<String, dynamic> message(String id, String role, String content) => {
          'id': id,
          'type': role == 'user' ? 'user_message' : 'assistant_message',
          'role': role,
          'content': content,
          'created_at': _iso(t),
          'updated_at': _iso(t),
        };

    MockClient chatClient({
      String? error,
      bool answered = true,
      List<String>? posts,
    }) =>
        MockClient((request) async {
          if (request.method == 'POST') {
            posts?.add(request.url.path);
            return http.Response('{"message":"Retry initiated"}', 202);
          }
          return http.Response(
            jsonEncode({
              'id': 'c1',
              'title': 'Spending this month',
              'error': error,
              'created_at': _iso(t),
              'updated_at': _iso(t),
              'messages': [
                message('1', 'user', 'How much did I spend?'),
                if (answered) message('2', 'assistant', 'You spent **a lot**.'),
              ],
            }),
            200,
          );
        });

    for (final brightness in Brightness.values) {
      testWidgets('nav bar, bubbles, composer and disclaimer ($brightness)',
          (tester) async {
        await _pump(tester, const ChatConversationScreen(chatId: 'c1'),
            chatClient(),
            brightness: brightness);
        expect(find.bySemanticsLabel('Chats'), findsOneWidget);
        expect(find.text('Spending this month'), findsOneWidget);
        expect(find.byTooltip('Chat actions'), findsOneWidget);
        expect(find.text('How much did I spend?'), findsOneWidget);
        expect(find.byType(AssistantAvatar), findsOneWidget);
        expect(find.text('Ask anything…'), findsOneWidget);
        expect(find.text('AI responses are informational only.'),
            findsOneWidget);
        expect(find.text("Couldn't get a reply."), findsNothing);
      });
    }

    testWidgets('send is disabled until there is text', (tester) async {
      await _pump(
          tester, const ChatConversationScreen(chatId: 'c1'), chatClient());
      bool sendEnabled() => tester
          .getSemantics(find.bySemanticsLabel('Send'))
          .flagsCollection
          .isEnabled
          .toBoolOrNull()!;
      expect(sendEnabled(), isFalse);
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.pump();
      expect(sendEnabled(), isTrue);
    });

    testWidgets('a failed reply shows the error panel and Retry posts',
        (tester) async {
      final posts = <String>[];
      await _pump(
        tester,
        const ChatConversationScreen(chatId: 'c1'),
        chatClient(error: 'Provider timed out', answered: false, posts: posts),
      );
      expect(find.text("Couldn't get a reply."), findsOneWidget);
      expect(find.text('Provider timed out'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(posts, ['/api/v1/chats/c1/messages/retry']);
      expect(find.text('Thinking'), findsOneWidget);

      // Unmount so the provider stops polling.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new chat shows the greeting and starter questions',
        (tester) async {
      await _pump(
          tester, const ChatConversationScreen(chatId: null), chatClient());
      expect(find.text('Hi there, how can I help?'), findsOneWidget);
      expect(find.text('What is my current net worth?'), findsOneWidget);
      expect(find.byTooltip('Chat actions'), findsNothing);
    });

    testWidgets('no overflow at 320 px', (tester) async {
      await _pump(tester, const ChatConversationScreen(chatId: 'c1'),
          chatClient(error: 'x', answered: false),
          width: 320);
      expect(tester.takeException(), isNull);
    });
  });
}
