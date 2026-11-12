import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/ds/ds.dart';
import '../widgets/typing_indicator.dart';

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

enum _ChatAction { rename, refresh }

class ChatConversationScreen extends StatefulWidget {
  /// Null means this is a brand-new chat — it will be created on first send.
  final String? chatId;

  const ChatConversationScreen({
    super.key,
    required this.chatId,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Tracks the real chat ID once the chat has been created.
  String? _chatId;

  ChatProvider? _chatProvider;
  bool _listenerAdded = false;
  bool _isSendInFlight = false;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatProvider = Provider.of<ChatProvider>(context, listen: false);
      _chatProvider!.addListener(_onChatChanged);
      _listenerAdded = true;
      if (_chatId == null) {
        _chatProvider!.clearCurrentChat();
      }
    });
    if (_chatId != null) {
      _loadChat();
    }
  }

  @override
  void dispose() {
    if (_listenerAdded && _chatProvider != null) {
      _chatProvider!.removeListener(_onChatChanged);
      _chatProvider = null;
      _listenerAdded = false;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (!mounted) return;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (chatProvider.isWaitingForResponse || chatProvider.isSendingMessage || chatProvider.isPolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendSuggestedQuestion(String question) async {
    if (!mounted) return;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (chatProvider.isSendingMessage || chatProvider.isWaitingForResponse) return;
    _messageController.text = question;
    await _sendMessage();
  }

  Future<void> _loadChat({bool forceRefresh = false}) async {
    if (_chatId == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Skip fetch if the provider already has this chat loaded (e.g. just created).
    if (!forceRefresh && chatProvider.currentChat?.id == _chatId) {
      _jumpToBottom();
      return;
    }

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      await authProvider.logout();
      return;
    }

    await chatProvider.fetchChat(
      accessToken: accessToken,
      chatId: _chatId!,
    );
    _jumpToBottom();
  }

  bool _isBusy(ChatProvider chatProvider) =>
      _isSendInFlight ||
      chatProvider.isSendingMessage ||
      chatProvider.isWaitingForResponse ||
      chatProvider.isPolling;

  Future<void> _sendMessage() async {
    if (_isSendInFlight) return;
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    setState(() => _isSendInFlight = true);

    final l = AppLocalizations.of(context);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      final accessToken = await authProvider.getValidAccessToken();
      if (accessToken == null) {
        await authProvider.logout();
        return;
      }

      _messageController.clear();

      if (_chatId == null) {
        // First message in a new chat — create the chat with it.
        final chat = await chatProvider.createChat(
          accessToken: accessToken,
          title: Chat.generateTitle(content),
          initialMessage: content,
        );
        if (!mounted) return;
        if (chat == null) {
          // Restore the message so the user doesn't lose it.
          _messageController.text = content;
          _showError(chatProvider.errorMessage ?? l.chatConversationStartFailed);
          return;
        }
        setState(() => _chatId = chat.id);
      } else {
        final shouldUpdateTitle =
            chatProvider.currentChat?.hasDefaultTitle == true;

        final delivered = await chatProvider.sendMessage(
          accessToken: accessToken,
          chatId: _chatId!,
          content: content,
        );

        if (!delivered) {
          if (!mounted) return;
          // Put the text back so the user can send it again.
          if (_messageController.text.isEmpty) _messageController.text = content;
          _showError(l.ds3aSendFailed);
          return;
        }

        if (shouldUpdateTitle) {
          await chatProvider.updateChatTitle(
            accessToken: accessToken,
            chatId: _chatId!,
            title: Chat.generateTitle(content),
          );
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } finally {
      if (mounted) setState(() => _isSendInFlight = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SureColors.of(context).palette.destructive,
      ),
    );
  }

  Future<void> _retry() async {
    if (_chatId == null || _isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final accessToken = await authProvider.getValidAccessToken();
      if (accessToken == null) {
        await authProvider.logout();
        return;
      }
      await chatProvider.retryLastResponse(
        accessToken: accessToken,
        chatId: _chatId!,
      );
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  Future<void> _editTitle() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final currentTitle = chatProvider.currentChat?.title ?? '';

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final controller = TextEditingController(text: currentTitle);
        return AlertDialog(
          title: Text(dl.chatConversationEditTitle),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: dl.chatConversationTitleLabel,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(dl.commonSave),
            ),
          ],
        );
      },
    );

    if (newTitle != null &&
        newTitle.isNotEmpty &&
        newTitle != currentTitle &&
        mounted) {
      if (_chatId == null) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final accessToken = await authProvider.getValidAccessToken();
      if (accessToken != null) {
        await chatProvider.updateChatTitle(
          accessToken: accessToken,
          chatId: _chatId!,
          title: newTitle,
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// True when the last reply failed: the provider or the server reports an
  /// error and the chat ends without an assistant answer, or the server's
  /// `chat.error` is set.
  bool _replyFailed(ChatProvider chatProvider, List<Message> messages) {
    if (_chatId == null || _isBusy(chatProvider)) return false;
    final chatError = chatProvider.currentChat?.error;
    if (chatError != null && chatError.isNotEmpty) return true;
    if (chatProvider.errorMessage == null) return false;
    final last = messages.lastOrNull;
    return last != null &&
        (last.isUser || (last.isAssistant && last.content.isEmpty));
  }

  Widget? _buildMenu(AppLocalizations l) {
    if (_chatId == null) return null;
    final palette = SureColors.of(context).palette;
    Widget leading(String icon) =>
        SureIcon(icon, size: 20, color: palette.textSecondary);
    return PopupMenuButton<_ChatAction>(
      icon: SureIcon(SureIcons.ellipsis, size: 22, color: palette.textPrimary),
      tooltip: l.ds3aMenu,
      onSelected: (action) {
        switch (action) {
          case _ChatAction.rename:
            _editTitle();
          case _ChatAction.refresh:
            _loadChat(forceRefresh: true);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ChatAction.rename,
          child: ListTile(
            leading: leading(SureIcons.pencil),
            title: Text(l.ds3aRename),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _ChatAction.refresh,
          child: ListTile(
            leading: leading(SureIcons.refresh),
            title: Text(l.ds3aRefresh),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    return Scaffold(
      backgroundColor: palette.surface,
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          final menu = _buildMenu(l);
          final title = chatProvider.currentChat?.title ?? l.chatConversationNewTitle;
          return Column(
            children: [
              SureNavBar(
                title: title,
                showTitle: true,
                leading: SureBackButton(label: l.ds3aBack),
                actions: [if (menu != null) menu],
              ),
              Expanded(child: _buildContent(l, chatProvider)),
              _buildComposer(l, chatProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(AppLocalizations l, ChatProvider chatProvider) {
    if (chatProvider.isLoading && chatProvider.currentChat == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chatProvider.errorMessage != null &&
        chatProvider.currentChat == null &&
        _chatId != null) {
      return Center(
        child: SingleChildScrollView(
          child: SureEmptyState(
            icon: SureIcons.circleAlert,
            title: l.chatConversationLoadError,
            body: chatProvider.errorMessage,
            primaryLabel: l.commonTryAgain,
            onPrimary: _loadChat,
          ),
        ),
      );
    }

    final allMessages = chatProvider.currentChat?.messages ?? [];
    // While waiting for the AI response, hide the last (partial/streaming)
    // assistant message so the typing indicator shows instead of partial content.
    // The full response is revealed once polling detects stable content.
    final messages = chatProvider.isWaitingForResponse
        ? allMessages.where((m) {
            return !(m.isAssistant && m == allMessages.lastOrNull);
          }).toList()
        : allMessages;
    final firstName =
        Provider.of<AuthProvider>(context, listen: true).user?.firstName;

    if (messages.isEmpty &&
        !chatProvider.isLoading &&
        !chatProvider.isSendingMessage &&
        !chatProvider.isWaitingForResponse) {
      return _EmptyState(
        firstName: firstName,
        onQuestionTap: _sendSuggestedQuestion,
      );
    }

    // An assistant message with no text (the server's pending placeholder)
    // and no tool calls has nothing to show.
    final shown = messages
        .where((m) =>
            !m.isAssistant ||
            m.content.isNotEmpty ||
            (m.toolCalls?.isNotEmpty ?? false))
        .toList();
    final waiting = chatProvider.isWaitingForResponse;
    final failed = _replyFailed(chatProvider, messages);
    final extra = (waiting ? 1 : 0) + (failed ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: shown.length + extra,
      itemBuilder: (context, index) {
        if (index < shown.length) {
          return _MessageView(message: shown[index], formatTime: _formatTime);
        }
        if (waiting) return const _ThinkingRow();
        final chatError = chatProvider.currentChat?.error;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ChatReplyErrorPanel(
            detail: chatProvider.errorMessage ??
                (chatError != null && chatError.isNotEmpty ? chatError : null),
            busy: _isRetrying,
            onRetry: _retry,
          ),
        );
      },
    );
  }

  Widget _buildComposer(AppLocalizations l, ChatProvider chatProvider) {
    final palette = SureColors.of(context).palette;
    final busy = _isBusy(chatProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurePanel(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _SendMessageIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                    onInvoke: (_) {
                      if (!_isBusy(chatProvider)) _sendMessage();
                      return null;
                    },
                  ),
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: l.ds3aComposerHint,
                          hintStyle: TextStyle(color: palette.textSubdued),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: TextStyle(fontSize: 15, color: palette.textPrimary),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        autofocus: _chatId == null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _messageController,
                        builder: (context, value, _) => _SendButton(
                          onPressed: busy || value.text.trim().isEmpty
                              ? null
                              : _sendMessage,
                          semanticLabel: l.ds3aSend,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.ds3aDisclaimer,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: palette.textSubdued),
          ),
        ],
      ),
    );
  }
}

/// The round inverse send button with an arrow-up glyph; dimmed when
/// [onPressed] is null.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed, required this.semanticLabel});

  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? palette.bgInverse : palette.surfaceInset,
              ),
              alignment: Alignment.center,
              child: SureIcon(
                SureIcons.arrowUp,
                size: 18,
                color: enabled ? palette.textInverse : palette.textSubdued,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message: the user's as a right-aligned inverse bubble (max 80% wide),
/// the assistant's as full-width markdown beside the small violet avatar.
class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.formatTime});

  final Message message;
  final String Function(DateTime) formatTime;

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final body = TextStyle(fontSize: 15, height: 1.45, color: palette.textPrimary);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      strong: body.copyWith(fontWeight: FontWeight.w600),
      em: body.copyWith(fontStyle: FontStyle.italic),
      listBullet: body,
      h1: body.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      h2: body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      h3: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      a: TextStyle(color: palette.link),
      code: TextStyle(
        fontFamily: SureTokens.fontMono,
        fontSize: 13,
        color: palette.textPrimary,
        backgroundColor: palette.surfaceInset,
      ),
      codeblockDecoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      ),
      blockquote: body.copyWith(color: palette.textSecondary),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.hairline, width: 3)),
      ),
      tableHead: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      tableBody: body.copyWith(fontSize: 13),
      tableBorder: TableBorder.all(
        color: colors.hairline,
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableCellsDecoration: BoxDecoration(color: palette.container),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final time = Text(
      formatTime(message.createdAt),
      style: TextStyle(fontSize: 11, color: palette.textSubdued),
    );

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SelectionArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: palette.bgInverse,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: palette.textInverse),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  time,
                ],
              ),
            ),
          ),
        ),
      );
    }

    final toolCalls = message.toolCalls ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: AssistantAvatar(size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.content.isNotEmpty)
                  SelectionArea(
                    child: MarkdownBody(
                      data: message.content,
                      selectable: false,
                      softLineBreak: true,
                      styleSheet: _markdownStyle(context),
                      sizedImageBuilder: (config) {
                        // Block remote images to prevent unsolicited network requests.
                        if (config.uri.scheme == 'http' ||
                            config.uri.scheme == 'https') {
                          return const SizedBox.shrink();
                        }
                        return Image.asset(config.uri.toString());
                      },
                    ),
                  ),
                if (toolCalls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final toolCall in toolCalls)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: palette.surfaceInset,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              toolCall.displayName,
                              style: TextStyle(
                                  fontSize: 11, color: palette.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                time,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The avatar and the animated "Thinking" label while a reply is written.
class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          AssistantAvatar(size: 20),
          SizedBox(width: 10),
          TypingIndicator(),
        ],
      ),
    );
  }
}

/// A new chat: a greeting and the starter questions as a panel of rows.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.firstName, required this.onQuestionTap});

  final String? firstName;
  final void Function(String) onQuestionTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final l = AppLocalizations.of(context);
    final name = (firstName ?? '').trim();
    final greeting = name.isNotEmpty
        ? l.chatConversationGreetingWithName(name)
        : l.chatConversationGreetingNoName;
    final questions = [
      (icon: SureIcons.wallet, text: l.chatSuggestionNetWorth),
      (icon: SureIcons.chartLine, text: l.chatSuggestionSpending),
      (icon: SureIcons.piggyBank, text: l.chatSuggestionSavings),
      (icon: SureIcons.receipt, text: l.chatSuggestionExpenses),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      children: [
        const Center(child: AssistantAvatar(size: SureCategoryIcon.heroSize)),
        const SizedBox(height: 14),
        Text(
          greeting,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        SurePanel.rows(
          dividerIndent: 48,
          children: [
            for (final q in questions)
              _SuggestionRow(
                icon: q.icon,
                text: q.text,
                onTap: () => onQuestionTap(q.text),
              ),
          ],
        ),
      ],
    );
  }
}

/// A starter question: icon and the full question, wrapping as needed.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final String icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  SureIcon(icon, size: 22, color: palette.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
