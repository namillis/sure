import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import 'ds/ds.dart';

/// The web's `--color-violet-500`. The mobile palette has no violet token, so
/// the assistant badge passes it to [SureCategoryIcon] the way a server
/// category color is passed (tinted fill, full-color glyph, light and dark).
/// shortcut: hard-coded web token, move to SureTokenPalette when it gains violet.
const String assistantColor = '#875BF7';

/// Lucide square-pen, the chat list's compose action.
const String composeIcon = 'square-pen';

/// The assistant's badge: a violet-tinted circle with a sparkles glyph.
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = SureCategoryIcon.rowSize});

  final double size;

  @override
  Widget build(BuildContext context) => SureCategoryIcon(
        name: 'Assistant',
        color: assistantColor,
        icon: SureIcons.sparkles,
        size: size,
      );
}

/// The time a chat is listed under: its `last_message_at`, else its
/// creation time, in local time.
DateTime chatListTime(Chat chat) => (chat.lastMessageAt ?? chat.createdAt).toLocal();

/// Chats whose title contains [query], ignoring case and surrounding spaces.
/// The API sends no last-message preview, so only the title is searched.
List<Chat> filterChats(List<Chat> chats, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return chats;
  return chats.where((c) => c.title.toLowerCase().contains(q)).toList();
}

/// Splits [chats] into runs that share a local calendar day, keeping their
/// order (the server sends newest first).
List<({DateTime day, List<Chat> chats})> groupChatsByDay(List<Chat> chats) {
  final groups = <({DateTime day, List<Chat> chats})>[];
  for (final chat in chats) {
    final t = chatListTime(chat);
    final day = DateTime(t.year, t.month, t.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.chats.add(chat);
    } else {
      groups.add((day: day, chats: [chat]));
    }
  }
  return groups;
}

/// A chat row's trailing time: "now", "5m", "2h" for today, otherwise the
/// short date ("Nov 3").
String chatRelativeTime(
  DateTime time, {
  required AppLocalizations l,
  required String locale,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final local = time.toLocal();
  final sameDay = local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  final diff = reference.difference(local);
  if (sameDay && !diff.isNegative) {
    if (diff.inMinutes < 1) return l.ds3aNow;
    if (diff.inHours < 1) return l.ds3aMinutesShort(diff.inMinutes);
    return l.ds3aHoursShort(diff.inHours);
  }
  if (sameDay) return l.ds3aNow;
  return SureDates.short(local, locale: locale, now: reference);
}

/// The multi-select check circle that replaces a chat row's badge.
class ChatSelectionCircle extends StatelessWidget {
  const ChatSelectionCircle({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      checked: selected,
      child: SizedBox.square(
        dimension: SureCategoryIcon.rowSize,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? palette.link : null,
              border: selected
                  ? null
                  : Border.all(color: palette.textSubdued, width: 1.5),
            ),
            alignment: Alignment.center,
            child: selected
                ? const SureIcon(SureIcons.check,
                    size: 14, color: Color(0xFFFFFFFF))
                : null,
          ),
        ),
      ),
    );
  }
}

/// "Couldn't get a reply." in a destructive-tinted panel, the server's
/// [detail] under it, and a "Retry" link.
class ChatReplyErrorPanel extends StatelessWidget {
  const ChatReplyErrorPanel({
    super.key,
    required this.onRetry,
    this.detail,
    this.busy = false,
  });

  final VoidCallback onRetry;
  final String? detail;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final l = AppLocalizations.of(context);
    final detailText = detail?.trim();
    return Container(
      decoration: BoxDecoration(
        color: palette.destructive.withValues(alpha: colors.isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
        border: Border.all(color: palette.destructive.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          SureIcon(SureIcons.circleAlert, size: 18, color: palette.destructive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.ds3aReplyFailed,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: SureTokens.weightMedium,
                    color: palette.textPrimary,
                  ),
                ),
                if (detailText != null && detailText.isNotEmpty)
                  Text(
                    detailText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRetry,
            style: TextButton.styleFrom(
              foregroundColor: palette.link,
              disabledForegroundColor: palette.textSubdued,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              l.ds3aRetry,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
