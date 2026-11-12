import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/sure_colors.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/ds/ds.dart';
import 'chat_conversation_screen.dart';

/// The Assistant tab: a large title with a compose action, a search field
/// and the chats in day sections. Swipe left to delete one chat; long-press
/// to select several.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedChatIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      await authProvider.logout();
      return;
    }

    await chatProvider.fetchChats(accessToken: accessToken);
  }

  Future<void> _handleRefresh() async {
    await _loadChats();
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedChatIds.clear();
    });
  }

  void _toggleSelectAll(List<String> allIds) {
    setState(() {
      if (_selectedChatIds.length == allIds.length) {
        _selectedChatIds.clear();
      } else {
        _selectedChatIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  void _toggleChatSelection(String id) {
    setState(() {
      if (_selectedChatIds.contains(id)) {
        _selectedChatIds.remove(id);
      } else {
        _selectedChatIds.add(id);
      }
    });
  }

  Future<bool> _confirmDelete(String content) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(dl.chatListDeleteTitle),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(dl.commonDelete,
                  style: TextStyle(color: palette.destructive)),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _deleteSelectedChats() async {
    final l = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final confirmed =
        await _confirmDelete(l.chatListDeleteMultiContent(_selectedChatIds.length));
    if (!confirmed || !mounted) return;

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      await authProvider.logout();
      return;
    }

    final success = await chatProvider.deleteMultipleChats(
      accessToken: accessToken,
      chatIds: _selectedChatIds.toList(),
    );

    if (!mounted) return;
    _exitSelectionMode();
    final palette = SureColors.of(context).palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? l.chatListDeletedSuccess : l.chatListDeleteFailed,
        ),
        backgroundColor: success ? palette.success : palette.destructive,
      ),
    );
  }

  Future<void> _deleteChat(Chat chat) async {
    final l = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final confirmed = await _confirmDelete(l.chatListDeleteSingleContent(chat.title));
    if (!confirmed || !mounted) return;

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      await authProvider.logout();
      return;
    }
    final success = await chatProvider.deleteChat(
      accessToken: accessToken,
      chatId: chat.id,
    );
    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.ds3aDeleteFailed),
        backgroundColor: SureColors.of(context).palette.destructive,
      ),
    );
  }

  Future<void> _openChat(String? chatId) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatConversationScreen(chatId: chatId),
      ),
    );
    if (mounted) _loadChats();
  }

  List<Widget> _headerActions(AppLocalizations l, List<Chat> chats) {
    final palette = SureColors.of(context).palette;
    if (_isSelectionMode) {
      return [
        SureNavIconButton(
          icon: SureIcons.trash,
          semanticLabel: l.ds3aDeleteSelected,
          color: palette.destructive,
          onPressed: _selectedChatIds.isNotEmpty ? _deleteSelectedChats : null,
        ),
        SureNavIconButton(
          icon: SureIcons.listChecks,
          semanticLabel: l.ds3aSelectAll,
          onPressed: () => _toggleSelectAll(chats.map((c) => c.id).toList()),
        ),
        SureNavTextButton(label: l.commonCancel, onPressed: _exitSelectionMode),
      ];
    }
    return [
      SureNavIconButton(
        icon: composeIcon,
        semanticLabel: l.ds3aNewChat,
        onPressed: () => _openChat(null),
      ),
      const SizedBox(width: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final chats = chatProvider.chats;
        return PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exitSelectionMode();
          },
          child: Scaffold(
            backgroundColor: palette.surface,
            body: RefreshIndicator(
              onRefresh: _handleRefresh,
              edgeOffset: MediaQuery.paddingOf(context).top +
                  SureLargeTitleHeader.barHeight,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SureLargeTitleHeader(
                    title: _isSelectionMode
                        ? l.ds3aSelectedCount(_selectedChatIds.length)
                        : l.ds3aTitle,
                    automaticallyImplyLeading: false,
                    actions: _headerActions(l, chats),
                  ),
                  ..._buildBody(l, chatProvider),
                  // Keep the last row clear of the shell's see-through tab
                  // bar (and the home indicator).
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(AppLocalizations l, ChatProvider chatProvider) {
    final chats = chatProvider.chats;

    if (chatProvider.isLoading && chats.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (chatProvider.errorMessage != null && chats.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SureEmptyState(
              icon: SureIcons.circleAlert,
              title: l.chatListError,
              body: chatProvider.errorMessage,
              primaryLabel: l.commonTryAgain,
              onPrimary: _handleRefresh,
            ),
          ),
        ),
      ];
    }

    if (chats.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SureEmptyState(
              icon: SureIcons.sparkles,
              title: l.ds3aEmptyTitle,
              body: l.ds3aEmptyBody,
              primaryLabel: l.ds3aNewChat,
              onPrimary: () => _openChat(null),
            ),
          ),
        ),
      ];
    }

    final visible = filterChats(chats, _query);
    return [
      if (chatProvider.hasIncompleteChatList)
        SliverToBoxAdapter(
          child: SureBanner(
            message: l.chatListIncomplete,
            actionLabel: l.commonTryAgain,
            onAction: _handleRefresh,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SureSearchField(
            controller: _searchController,
            hintText: l.ds3aSearchHint,
            clearSemanticLabel: l.ds3aClearSearch,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverToBoxAdapter(
          child: SureEmptyState(
            icon: SureIcons.search,
            title: l.ds3aNoMatches(_query.trim()),
            body: l.ds3aNoMatchesBody,
          ),
        )
      else
        for (final group in groupChatsByDay(visible)) ...[
          SliverToBoxAdapter(
            child: SureSectionHeader(
              label: SureDates.relativeDayOf(context, group.day),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SurePanel.rows(
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [for (final chat in group.chats) _buildRow(l, chat)],
              ),
            ),
          ),
        ],
    ];
  }

  Widget _buildRow(AppLocalizations l, Chat chat) {
    final palette = SureColors.of(context).palette;
    final selected = _selectedChatIds.contains(chat.id);
    return SureSwipeActions(
      key: ValueKey('chat_${chat.id}'),
      enabled: !_isSelectionMode,
      actions: [
        SureSwipeAction(
          label: l.dsDelete,
          color: palette.destructive,
          onPressed: () => _deleteChat(chat),
        ),
      ],
      child: ColoredBox(
        color: selected ? palette.containerInset : palette.container,
        child: SureListRow(
          leading: _isSelectionMode
              ? ChatSelectionCircle(selected: selected)
              : const AssistantAvatar(),
          title: chat.title,
          trailing: Text(
            chatRelativeTime(
              chatListTime(chat),
              l: l,
              locale: Localizations.localeOf(context).toString(),
            ),
            style: TextStyle(fontSize: 13, color: palette.textSubdued),
          ),
          onTap: () {
            if (_isSelectionMode) {
              _toggleChatSelection(chat.id);
            } else {
              _openChat(chat.id);
            }
          },
          onLongPress: _isSelectionMode
              ? null
              : () {
                  SureHaptics.selection();
                  setState(() {
                    _isSelectionMode = true;
                    _selectedChatIds.add(chat.id);
                  });
                },
        ),
      ),
    );
  }
}
