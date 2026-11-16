import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/recurring_transaction.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/transaction_actions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import '../utils/transaction_amount_display.dart';
import '../widgets/ds/ds.dart';

// Round 4b, section 1: the transaction detail screen's Sure+ actions
// (transfers, duplicates, sync locks, reconcile and "Mark as recurring").
// Each widget runs its own request and reports the server's copy of the
// transaction back through `onUpdated`, so the screen can show it and mark
// the activity list stale.

/// Which section 1 features the server offers. All false without a
/// [ServerFeaturesProvider] above the screen.
class TransactionActionFeatures {
  const TransactionActionFeatures({
    this.transfers = false,
    this.duplicates = false,
    this.markRecurring = false,
    this.locks = false,
  });

  final bool transfers;
  final bool duplicates;
  final bool markRecurring;
  final bool locks;

  factory TransactionActionFeatures.of(BuildContext context) {
    final features = context.watch<ServerFeaturesProvider?>();
    bool has(String name) => features?.has(name) ?? false;
    return TransactionActionFeatures(
      transfers: has(ServerFeaturesProvider.transactionsTransfers),
      duplicates: has(ServerFeaturesProvider.transactionsDuplicates),
      markRecurring: has(ServerFeaturesProvider.transactionsMarkRecurring),
      locks: has(ServerFeaturesProvider.transactionsLocks),
    );
  }
}

/// A plain message for a failed action: read-only sign-ins and the transfer
/// matcher's `reason` keys get their own text, everything else shows the
/// server's message.
String transactionActionError(
  AppLocalizations l,
  Map<String, dynamic> result,
) {
  if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
  final reason = switch (result['reason']) {
    'not_a_candidate' => l.s4tReasonNotACandidate,
    'already_linked' => l.s4tReasonAlreadyLinked,
    'same_account' => l.s4tReasonSameAccount,
    'split_transaction' => l.s4tReasonSplit,
    'excluded_transaction' => l.s4tReasonExcluded,
    'invalid_transfer' => l.s4tReasonInvalidTransfer,
    _ => null,
  };
  if (reason != null) return reason;
  final message = result['error']?.toString();
  return message == null || message.isEmpty
      ? l.transactionEditUpdateFailed
      : message;
}

/// Runs [call] with a fresh token. Resolves with the result on success;
/// otherwise reports a message through [onError] (signing out on 401) and
/// resolves null.
Future<Map<String, dynamic>?> runTransactionAction(
  BuildContext context,
  Future<Map<String, dynamic>> Function(String token) call, {
  required void Function(String message) onError,
}) async {
  final l = AppLocalizations.of(context);
  final auth = context.read<AuthProvider>();
  final token = await auth.getValidAccessToken();
  if (token == null) {
    onError(l.transactionEditSessionExpired);
    return null;
  }
  final result = await call(token);
  if (result['success'] == true) return result;
  if (result['error'] == 'unauthorized') {
    onError(l.transactionEditSessionExpired);
    await auth.logout();
    return null;
  }
  onError(transactionActionError(l, result));
  return null;
}

/// The edit screen's confirm dialog, with a destructive action.
Future<bool> confirmTransactionAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      final palette = SureColors.of(context).palette;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// The plain name of a locked attribute (`category_id` -> "Category").
String lockedFieldLabel(AppLocalizations l, String field) {
  switch (field) {
    case 'name':
      return l.s4tFieldName;
    case 'date':
      return l.s4tFieldDate;
    case 'amount':
      return l.s4tFieldAmount;
    case 'notes':
      return l.s4tFieldNotes;
    case 'category_id' || 'category':
      return l.s4tFieldCategory;
    case 'merchant_id' || 'merchant':
      return l.s4tFieldMerchant;
    case 'tag_ids' || 'tags':
      return l.s4tFieldTags;
    case 'kind':
      return l.s4tFieldKind;
    case 'currency':
      return l.s4tFieldCurrency;
  }
  final words = field
      .replaceAll(RegExp(r'_ids?$'), '')
      .split('_')
      .where((word) => word.isNotEmpty)
      .join(' ');
  if (words.isEmpty) return field;
  return words[0].toUpperCase() + words.substring(1);
}

String reconciledStatusLabel(AppLocalizations l, String? status) =>
    switch (status) {
      'cleared' => l.s4tStatusCleared,
      'reconciled' => l.s4tStatusReconciled,
      _ => l.s4tStatusUnreconciled,
    };

/// "Jan 5" for an API date, else the text as given.
String _day(BuildContext context, String? date) {
  final parsed = SureDates.parseDay(date);
  if (parsed == null) return date ?? '';
  return SureDates.shortOf(context, parsed);
}

/// A mono amount the way the transaction row shows it: money out with a
/// minus in `textPrimary`, money in with a plus in `success`. Every account
/// type flips the API's sign the same way, so no account is needed.
Widget _amountText(BuildContext context, String amount, {double size = 14}) {
  final palette = SureColors.of(context).palette;
  final hidden = Provider.of<PrivacyProvider?>(context)?.hidden ?? false;
  final display =
      TransactionAmountDisplay.of(amount, isAsset: true, isLiability: false);
  final text =
      display.trend == MoneyTrend.inflow ? '+${display.text}' : display.text;
  return MoneyText(
    MoneyMasker.mask(text, hidden: hidden),
    trend: display.trend,
    color: switch (display.trend) {
      MoneyTrend.inflow => palette.success,
      MoneyTrend.outflow => palette.textPrimary,
      MoneyTrend.neutral => palette.textSubdued,
    },
    maxLines: 1,
    style: TextStyle(fontSize: size, fontWeight: SureTokens.weightMedium),
  );
}

Widget _errorLine(BuildContext context, String message) {
  final palette = SureColors.of(context).palette;
  return Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: palette.destructive),
      ),
    ),
  );
}

Widget _spinner() => const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

/// The banners and the pending-match row at the top of the screen: the
/// duplicate banner (or "Match to posted transaction" for a pending
/// transaction without one) and "Protected from sync". Empty when none
/// applies.
class TransactionActionBanners extends StatelessWidget {
  const TransactionActionBanners({
    super.key,
    required this.transaction,
    required this.features,
    required this.service,
    required this.enabled,
    required this.onUpdated,
    required this.onReplaced,
  });

  final Transaction transaction;
  final TransactionActionFeatures features;
  final TransactionActionsService service;
  final bool enabled;

  /// The same transaction, as the server has it after a write.
  final ValueChanged<Transaction> onUpdated;

  /// The transaction was merged away; this is the one that survived.
  final ValueChanged<Transaction> onReplaced;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (features.duplicates) {
      if (transaction.duplicateSuspected == true) {
        children.add(_DuplicateBanner(
          transaction: transaction,
          service: service,
          enabled: enabled,
          onUpdated: onUpdated,
          onReplaced: onReplaced,
        ));
      } else if (transaction.pending == true) {
        children.add(SurePanel.rows(children: [
          _PendingMatchRow(
            transaction: transaction,
            service: service,
            enabled: enabled,
            onReplaced: onReplaced,
          ),
        ]));
      }
    }
    if (features.locks && transaction.syncLocked == true) {
      children.add(_SyncLockBanner(
        transaction: transaction,
        service: service,
        enabled: enabled,
        onUpdated: onUpdated,
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
      ],
    );
  }
}

/// A multi-line notice in a tinted panel: an icon, a bold title, detail
/// lines and link actions. [SureBanner] is one line, which can't hold the
/// duplicate's details and two actions.
class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.details,
    required this.actions,
    this.trailing,
    this.busy = false,
    this.error,
  });

  final String icon;
  final Color tint;
  final String title;
  final List<String> details;
  final Widget? trailing;
  final List<({String label, VoidCallback? onTap})> actions;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SureIcon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
                for (final line in details)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: palette.textSecondary),
                    ),
                  ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        error!,
                        style:
                            TextStyle(fontSize: 13, color: palette.destructive),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 40,
                  child: busy
                      ? Align(
                          alignment: Alignment.centerLeft, child: _spinner())
                      : Wrap(
                          spacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final action in actions)
                              _BannerAction(
                                  label: action.label, onTap: action.onTap),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerAction extends StatelessWidget {
  const _BannerAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onTap == null
                    ? palette.link.withValues(alpha: 0.5)
                    : palette.link,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DuplicateBanner extends StatefulWidget {
  const _DuplicateBanner({
    required this.transaction,
    required this.service,
    required this.enabled,
    required this.onUpdated,
    required this.onReplaced,
  });

  final Transaction transaction;
  final TransactionActionsService service;
  final bool enabled;
  final ValueChanged<Transaction> onUpdated;
  final ValueChanged<Transaction> onReplaced;

  @override
  State<_DuplicateBanner> createState() => _DuplicateBannerState();
}

class _DuplicateBannerState extends State<_DuplicateBanner> {
  bool _busy = false;
  String? _error;

  Future<void> _run(bool merge) async {
    final id = widget.transaction.id;
    if (_busy || id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runTransactionAction(
      context,
      (token) => merge
          ? widget.service.mergeDuplicate(accessToken: token, transactionId: id)
          : widget.service
              .dismissDuplicate(accessToken: token, transactionId: id),
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final updated = result?['transaction'];
    if (updated is! Transaction) return;
    SureHaptics.success();
    merge ? widget.onReplaced(updated) : widget.onUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final t = widget.transaction;
    final candidate = t.duplicateCandidate;
    final line = [
      if (candidate?.name != null) candidate!.name!,
      if (candidate?.date != null) _day(context, candidate!.date),
    ].join(' · ');
    final canAct = widget.enabled && !_busy;
    return _ActionBanner(
      key: const ValueKey('transaction-duplicate-banner'),
      icon: 'copy',
      tint: palette.warning,
      title: t.duplicateConfidence == 'low'
          ? l.s4tDuplicateReview
          : l.s4tDuplicatePossible,
      details: [if (line.isNotEmpty) line],
      trailing: candidate?.amount != null
          ? _amountText(context, candidate!.amount!)
          : null,
      busy: _busy,
      error: _error,
      actions: [
        (label: l.s4tDuplicateMerge, onTap: canAct ? () => _run(true) : null),
        (
          label: l.s4tDuplicateDismiss,
          onTap: canAct ? () => _run(false) : null
        ),
      ],
    );
  }
}

class _SyncLockBanner extends StatefulWidget {
  const _SyncLockBanner({
    required this.transaction,
    required this.service,
    required this.enabled,
    required this.onUpdated,
  });

  final Transaction transaction;
  final TransactionActionsService service;
  final bool enabled;
  final ValueChanged<Transaction> onUpdated;

  @override
  State<_SyncLockBanner> createState() => _SyncLockBannerState();
}

class _SyncLockBannerState extends State<_SyncLockBanner> {
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    final id = widget.transaction.id;
    if (_busy || id == null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await confirmTransactionAction(
      context,
      title: l.s4tUnlockTitle,
      body: l.s4tUnlockBody,
      action: l.s4tUnlock,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runTransactionAction(
      context,
      (token) => widget.service.unlock(accessToken: token, transactionId: id),
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final updated = result?['transaction'];
    if (updated is! Transaction) return;
    SureHaptics.success();
    widget.onUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final labels = <String>{
      for (final lock in widget.transaction.lockedAttributes)
        lockedFieldLabel(l, lock.field),
    };
    return _ActionBanner(
      key: const ValueKey('transaction-sync-lock-banner'),
      icon: 'shield',
      tint: palette.info,
      title: l.s4tSyncLockedTitle,
      details: [
        labels.isEmpty
            ? l.s4tSyncLockedNoFields
            : l.s4tSyncLockedFields(labels.join(', ')),
      ],
      busy: _busy,
      error: _error,
      actions: [
        (label: l.s4tUnlock, onTap: widget.enabled && !_busy ? _unlock : null),
      ],
    );
  }
}

class _PendingMatchRow extends StatelessWidget {
  const _PendingMatchRow({
    required this.transaction,
    required this.service,
    required this.enabled,
    required this.onReplaced,
  });

  final Transaction transaction;
  final TransactionActionsService service;
  final bool enabled;
  final ValueChanged<Transaction> onReplaced;

  Future<void> _open(BuildContext context) async {
    final id = transaction.id;
    if (id == null) return;
    final survivor = await showSureSheet<Transaction>(
      context: context,
      builder: (_) => PendingMatchSheet(transactionId: id, service: service),
    );
    if (survivor == null) return;
    SureHaptics.success();
    onReplaced(survivor);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SureListRow(
      key: const ValueKey('transaction-pending-match-row'),
      title: l.s4tPendingMatch,
      titleColor: palette.link,
      showChevron: true,
      enabled: enabled,
      onTap: enabled ? () => _open(context) : null,
    );
  }
}

/// Picks the posted transaction a pending one became, ten at a time, and
/// merges them. Pops with the surviving transaction.
class PendingMatchSheet extends StatefulWidget {
  const PendingMatchSheet({
    super.key,
    required this.transactionId,
    required this.service,
  });

  final String transactionId;
  final TransactionActionsService service;

  @override
  State<PendingMatchSheet> createState() => _PendingMatchSheetState();
}

class _PendingMatchSheetState extends State<PendingMatchSheet> {
  final List<Transaction> _candidates = [];
  bool _loading = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  bool _loadFailed = false;
  String? _mergingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final offset = _nextOffset;
    final result = await runTransactionAction(
      context,
      (token) => widget.service.pendingMergeCandidates(
        accessToken: token,
        transactionId: widget.transactionId,
        offset: offset,
      ),
      onError: (_) {},
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null) {
        _loadFailed = true;
        return;
      }
      _candidates.addAll(result['candidates'] as List<Transaction>);
      _hasMore = result['hasMore'] == true;
      _nextOffset = result['nextOffset'] as int;
    });
  }

  Future<void> _merge(Transaction candidate) async {
    final entryId = candidate.entryId;
    if (_mergingId != null || entryId == null) return;
    setState(() {
      _mergingId = candidate.id ?? entryId;
      _error = null;
    });
    final result = await runTransactionAction(
      context,
      (token) => widget.service.pendingMerge(
        accessToken: token,
        transactionId: widget.transactionId,
        postedEntryId: entryId,
      ),
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    final survivor = result?['transaction'];
    if (survivor is Transaction) {
      Navigator.of(context).pop(survivor);
      return;
    }
    setState(() => _mergingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final busy = _mergingId != null;
    final children = <Widget>[];

    if (_candidates.isNotEmpty) {
      children.add(SurePanel.rows(children: [
        for (final candidate in _candidates)
          SureListRow(
            key: ValueKey('pending-candidate-${candidate.id}'),
            title: candidate.name,
            subtitle: _day(context, candidate.date),
            trailing: _mergingId == (candidate.id ?? candidate.entryId)
                ? _spinner()
                : _amountText(context, candidate.amount, size: 15),
            enabled: !busy || _mergingId == candidate.id,
            onTap: busy ? null : () => _merge(candidate),
          ),
      ]));
    } else if (!_loading && !_loadFailed) {
      children.add(SureEmptyState(
        icon: SureIcons.inbox,
        title: l.s4tPendingMatchEmpty,
      ));
    }

    if (_loadFailed) {
      children.add(SurePanel.rows(children: [
        SureListRow(
          title: l.s4tLoadFailed,
          titleColor: palette.destructive,
          trailing: TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(foregroundColor: palette.link),
            child: Text(l.commonTryAgain),
          ),
        ),
      ]));
    } else if (_loading) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: _spinner()),
      ));
    } else if (_hasMore) {
      children.add(SureButtonPanel(
        key: const ValueKey('pending-candidates-load-more'),
        label: l.s4tLoadMore,
        onPressed: busy ? null : _load,
        margin: const EdgeInsets.only(top: 12),
      ));
    }

    return SureSheet(
      title: l.s4tPendingMatchTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorLine(context, _error!),
            ],
          ],
        ),
      ),
    );
  }
}

/// The details panel's transfer row. Not a transfer yet: "Mark as transfer",
/// which opens the match sheet. A transfer: "Transfer · Pending · Savings",
/// which opens a sheet with "Not a transfer".
class TransactionTransferRow extends StatelessWidget {
  const TransactionTransferRow({
    super.key,
    required this.transaction,
    required this.service,
    required this.enabled,
    required this.onUpdated,
  });

  final Transaction transaction;
  final TransactionActionsService service;
  final bool enabled;
  final ValueChanged<Transaction> onUpdated;

  Future<void> _open(BuildContext context) async {
    final id = transaction.id;
    if (id == null) return;
    final transfer = transaction.transfer;
    final updated = await showSureSheet<Transaction>(
      context: context,
      builder: (_) => transfer == null
          ? MarkTransferSheet(transactionId: id, service: service)
          : TransferDetailSheet(
              transactionId: id,
              transfer: transfer,
              service: service,
            ),
    );
    if (updated == null) return;
    SureHaptics.success();
    onUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final transfer = transaction.transfer;
    if (transfer == null) {
      return SureListRow(
        key: const ValueKey('transaction-transfer-row'),
        title: l.s4tMarkAsTransfer,
        titleColor: palette.link,
        showChevron: true,
        enabled: enabled,
        onTap: enabled ? () => _open(context) : null,
      );
    }
    return SureListRow(
      key: const ValueKey('transaction-transfer-row'),
      title: l.dsTransfer,
      value: transferStatusValue(l, transfer),
      showChevron: true,
      enabled: enabled,
      onTap: enabled ? () => _open(context) : null,
    );
  }
}

/// "Pending · Savings" (or just the account when the status is unknown).
String transferStatusValue(AppLocalizations l, TransactionTransfer transfer) {
  final account = transfer.otherAccountName ?? l.txnParityTransferOtherAccount;
  final status = switch (transfer.status) {
    'pending' => l.s4tTransferPending,
    'confirmed' => l.s4tTransferConfirmed,
    _ => null,
  };
  return status == null ? account : l.s4tTransferValue(status, account);
}

/// A transfer's sheet: its status and other account, and "Not a transfer".
class TransferDetailSheet extends StatefulWidget {
  const TransferDetailSheet({
    super.key,
    required this.transactionId,
    required this.transfer,
    required this.service,
  });

  final String transactionId;
  final TransactionTransfer transfer;
  final TransactionActionsService service;

  @override
  State<TransferDetailSheet> createState() => _TransferDetailSheetState();
}

class _TransferDetailSheetState extends State<TransferDetailSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _unmatch() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final confirmed = await confirmTransactionAction(
      context,
      title: l.s4tNotATransferTitle,
      body: l.s4tNotATransferBody,
      action: l.s4tNotATransfer,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runTransactionAction(
      context,
      (token) => widget.service.deleteTransferMatch(
          accessToken: token, transactionId: widget.transactionId),
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    final updated = result?['transaction'];
    if (updated is Transaction) {
      Navigator.of(context).pop(updated);
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final transfer = widget.transfer;
    final account =
        transfer.otherAccountName ?? l.txnParityTransferOtherAccount;
    return SureSheet(
      title: l.dsTransfer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurePanel.rows(children: [
              SureListRow(title: l.s4tTransferWith(account)),
              if (transfer.status != null)
                SureListRow(
                  title: l.s4tStatus,
                  value: transfer.status == 'pending'
                      ? l.s4tTransferPending
                      : l.s4tTransferConfirmed,
                ),
            ]),
            const SizedBox(height: 16),
            SureButtonPanel(
              key: const ValueKey('transfer-not-a-transfer'),
              label: l.s4tNotATransfer,
              destructive: true,
              busy: _busy,
              onPressed: _unmatch,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorLine(context, _error!),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Mark as transfer": the matcher's candidates, then the accounts the other
/// side can be created in. With candidates (a transfer hint) it also offers
/// "Not a transfer", which stops the suggestions. Pops with the transaction
/// as the server has it after the write.
class MarkTransferSheet extends StatefulWidget {
  const MarkTransferSheet({
    super.key,
    required this.transactionId,
    required this.service,
  });

  final String transactionId;
  final TransactionActionsService service;

  @override
  State<MarkTransferSheet> createState() => _MarkTransferSheetState();
}

class _MarkTransferSheetState extends State<MarkTransferSheet> {
  List<TransferCandidate>? _candidates;
  List<TransferTargetAccount> _accounts = const [];
  bool _loading = false;
  bool _loadFailed = false;

  /// The row or button whose request is running.
  String? _busyKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final result = await runTransactionAction(
      context,
      (token) => widget.service.transferCandidates(
          accessToken: token, transactionId: widget.transactionId),
      onError: (_) {},
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null) {
        _loadFailed = true;
        return;
      }
      _candidates = result['candidates'] as List<TransferCandidate>;
      _accounts = result['accounts'] as List<TransferTargetAccount>;
    });
  }

  Future<void> _submit(
    String key,
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    if (_busyKey != null) return;
    setState(() {
      _busyKey = key;
      _error = null;
    });
    final result =
        await runTransactionAction(context, call, onError: (m) => _error = m);
    if (!mounted) return;
    final updated = result?['transaction'];
    if (result != null) {
      Navigator.of(context).pop(updated is Transaction ? updated : null);
      return;
    }
    setState(() => _busyKey = null);
  }

  void _matchExisting(TransferCandidate candidate) {
    final entryId = candidate.transaction.entryId;
    if (entryId == null) return;
    _submit(
      'existing-$entryId',
      (token) => widget.service.createTransferMatch(
        accessToken: token,
        transactionId: widget.transactionId,
        matchedEntryId: entryId,
      ),
    );
  }

  void _createIn(TransferTargetAccount account) {
    _submit(
      'new-${account.id}',
      (token) => widget.service.createTransferMatch(
        accessToken: token,
        transactionId: widget.transactionId,
        targetAccountId: account.id,
      ),
    );
  }

  Future<void> _dismissHint() async {
    if (_busyKey != null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await confirmTransactionAction(
      context,
      title: l.s4tNotATransferTitle,
      body: l.s4tNotATransferHintBody,
      action: l.s4tNotATransfer,
    );
    if (!confirmed || !mounted) return;
    _submit(
      'dismiss',
      (token) => widget.service.deleteTransferMatch(
          accessToken: token, transactionId: widget.transactionId),
    );
  }

  Widget _note(String text) {
    final palette = SureColors.of(context).palette;
    return SurePanel.rows(children: [
      SureListRow(title: text, titleColor: palette.textSecondary),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final candidates = _candidates;
    final busy = _busyKey != null;
    const headerPadding = EdgeInsets.fromLTRB(4, 12, 4, 6);

    final Widget body;
    if (_loadFailed) {
      body = SurePanel.rows(children: [
        SureListRow(
          title: l.s4tLoadFailed,
          titleColor: palette.destructive,
          trailing: TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(foregroundColor: palette.link),
            child: Text(l.commonTryAgain),
          ),
        ),
      ]);
    } else if (candidates == null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _spinner()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureSectionHeader(
              label: l.s4tTransferMatching, padding: headerPadding),
          if (candidates.isEmpty)
            _note(l.s4tTransferNoMatches)
          else
            SurePanel.rows(children: [
              for (final candidate in candidates)
                SureListRow(
                  key: ValueKey(
                      'transfer-candidate-${candidate.transaction.entryId}'),
                  title: candidate.transaction.name,
                  subtitle: [
                    _day(context, candidate.transaction.date),
                    if (candidate.accountName != null) candidate.accountName!,
                  ].join(' · '),
                  trailing:
                      _busyKey == 'existing-${candidate.transaction.entryId}'
                          ? _spinner()
                          : _amountText(context, candidate.transaction.amount,
                              size: 15),
                  onTap: busy ? null : () => _matchExisting(candidate),
                ),
            ]),
          SureSectionHeader(
              label: l.s4tTransferCreateIn, padding: headerPadding),
          if (_accounts.isEmpty)
            _note(l.s4tTransferNoAccounts)
          else
            SurePanel.rows(children: [
              for (final account in _accounts)
                SureListRow(
                  key: ValueKey('transfer-account-${account.id}'),
                  title: account.name,
                  trailing: _busyKey == 'new-${account.id}' ? _spinner() : null,
                  showChevron: true,
                  onTap: busy ? null : () => _createIn(account),
                ),
            ]),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            SureButtonPanel(
              key: const ValueKey('transfer-dismiss-hint'),
              label: l.s4tNotATransfer,
              destructive: true,
              busy: _busyKey == 'dismiss',
              onPressed: busy ? null : _dismissHint,
            ),
          ],
        ],
      );
    }

    return SureSheet(
      title: l.s4tMarkAsTransfer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorLine(context, _error!),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Status · Cleared": one tap moves the reconciled status one step. The
/// request isn't idempotent, so the row is disabled while it runs and a
/// failure is never retried on its own.
class TransactionReconcileRow extends StatefulWidget {
  const TransactionReconcileRow({
    super.key,
    required this.transaction,
    required this.service,
    required this.enabled,
    required this.onUpdated,
  });

  final Transaction transaction;
  final TransactionActionsService service;
  final bool enabled;
  final ValueChanged<Transaction> onUpdated;

  @override
  State<TransactionReconcileRow> createState() =>
      _TransactionReconcileRowState();
}

class _TransactionReconcileRowState extends State<TransactionReconcileRow> {
  bool _busy = false;
  String? _error;

  Future<void> _advance() async {
    final id = widget.transaction.id;
    if (_busy || id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runTransactionAction(
      context,
      (token) =>
          widget.service.reconcile(accessToken: token, transactionId: id),
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final updated = result?['transaction'];
    if (updated is! Transaction) return;
    SureHaptics.selection();
    widget.onUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canTap = widget.enabled && !_busy;
    final row = SureListRow(
      key: const ValueKey('transaction-reconcile-row'),
      title: l.s4tStatus,
      trailing: _busy
          ? _spinner()
          : Text(
              reconciledStatusLabel(l, widget.transaction.reconciledStatus),
              style: TextStyle(fontSize: 15, color: palette.link),
            ),
      enabled: widget.enabled || _busy,
      onTap: canTap ? _advance : null,
    );
    if (_error == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, _errorLine(context, _error!)],
    );
  }
}

/// The actions panel's "Mark as recurring": creates the series on the
/// server, then reads "Added to recurring" (or "Already recurring") with
/// "Open" when there is a series to open.
class TransactionMarkRecurringRow extends StatefulWidget {
  const TransactionMarkRecurringRow({
    super.key,
    required this.transactionId,
    required this.service,
    required this.enabled,
    required this.onMarked,
    required this.onOpen,
  });

  final String transactionId;
  final TransactionActionsService service;
  final bool enabled;

  /// A series now covers the transaction: the new one (201) or the one that
  /// already did (409), when the user can see it.
  final ValueChanged<RecurringTransaction?> onMarked;
  final ValueChanged<RecurringTransaction> onOpen;

  @override
  State<TransactionMarkRecurringRow> createState() =>
      _TransactionMarkRecurringRowState();
}

class _TransactionMarkRecurringRowState
    extends State<TransactionMarkRecurringRow> {
  bool _busy = false;
  String? _error;

  /// Null until marked; then whether the series already existed.
  bool? _alreadyExisted;
  RecurringTransaction? _series;

  Future<void> _mark() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Map<String, dynamic>? conflict;
    final result = await runTransactionAction(
      context,
      (token) async {
        final result = await widget.service.markAsRecurring(
            accessToken: token, transactionId: widget.transactionId);
        if (result['conflict'] == true) conflict = result;
        return result;
      },
      onError: (message) => _error = message,
    );
    if (!mounted) return;
    final outcome = result ?? conflict;
    setState(() {
      _busy = false;
      if (outcome == null) return;
      _error = null;
      _alreadyExisted = result == null;
      final series = outcome['recurring'];
      _series = series is RecurringTransaction ? series : null;
    });
    if (outcome == null) return;
    if (result != null) SureHaptics.success();
    widget.onMarked(_series);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final Widget row;
    if (_alreadyExisted != null) {
      final series = _series;
      row = SureListRow(
        key: const ValueKey('transaction-mark-recurring-row'),
        title: _alreadyExisted! ? l.s4tAlreadyRecurring : l.s4tAddedToRecurring,
        leading:
            SureIcon(SureIcons.circleCheck, size: 18, color: palette.success),
        trailing: series == null
            ? null
            : Text(
                l.s4tOpen,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.link,
                ),
              ),
        onTap: series == null ? null : () => widget.onOpen(series),
      );
    } else {
      row = SureListRow(
        key: const ValueKey('transaction-mark-recurring-row'),
        title: l.txnParityMarkRecurring,
        titleColor: palette.link,
        leading: SureIcon(SureIcons.repeat, size: 18, color: palette.link),
        trailing: _busy ? _spinner() : null,
        enabled: widget.enabled || _busy,
        onTap: widget.enabled && !_busy ? _mark : null,
      );
    }
    if (_error == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, _errorLine(context, _error!)],
    );
  }
}
