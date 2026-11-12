import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/chat.dart';
import 'package:sure_mobile/widgets/chat_widgets.dart';

Chat _chat(String id, DateTime created, {String? title, DateTime? last}) => Chat(
      id: id,
      title: title ?? 'Chat $id',
      createdAt: created,
      updatedAt: created,
      lastMessageAt: last,
    );

void main() {
  final l = lookupAppLocalizations(const Locale('en'));
  setUpAll(() => initializeDateFormatting('en'));

  group('filterChats', () {
    final chats = [
      _chat('1', DateTime(2026, 11, 11), title: 'Groceries budget'),
      _chat('2', DateTime(2026, 11, 10), title: 'Net worth'),
    ];

    test('matches the title ignoring case and spaces', () {
      expect(filterChats(chats, '  GROCER ').map((c) => c.id), ['1']);
    });

    test('an empty query keeps every chat', () {
      expect(filterChats(chats, ' '), chats);
    });

    test('no match gives an empty list', () {
      expect(filterChats(chats, 'rent'), isEmpty);
    });
  });

  group('groupChatsByDay', () {
    test('groups consecutive chats of one local day, keeping order', () {
      final groups = groupChatsByDay([
        _chat('a', DateTime(2026, 11, 11, 9)),
        _chat('b', DateTime(2026, 11, 11, 8)),
        _chat('c', DateTime(2026, 11, 3, 20)),
      ]);
      expect(groups.map((g) => g.day),
          [DateTime(2026, 11, 11), DateTime(2026, 11, 3)]);
      expect(groups.first.chats.map((c) => c.id), ['a', 'b']);
      expect(groups.last.chats.map((c) => c.id), ['c']);
    });

    test('uses last_message_at when the server sends it', () {
      final groups = groupChatsByDay([
        _chat('a', DateTime(2026, 11, 1), last: DateTime(2026, 11, 9, 12)),
      ]);
      expect(groups.single.day, DateTime(2026, 11, 9));
    });
  });

  group('chatRelativeTime', () {
    final now = DateTime(2026, 11, 11, 18, 0);
    String format(DateTime t) =>
        chatRelativeTime(t, l: l, locale: 'en', now: now);

    test('today: now, minutes, hours', () {
      expect(format(now.subtract(const Duration(seconds: 20))), 'now');
      expect(format(now.subtract(const Duration(minutes: 5))), '5m');
      expect(format(now.subtract(const Duration(hours: 2))), '2h');
    });

    test('an earlier day shows the short date', () {
      expect(format(DateTime(2026, 11, 3, 10)), 'Nov 3');
      expect(format(DateTime(2025, 12, 30)), 'Dec 30, 2025');
    });

    test('a time later today (clock skew) reads now', () {
      expect(format(now.add(const Duration(minutes: 3))), 'now');
    });
  });
}
