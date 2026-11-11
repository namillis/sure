import 'package:flutter/material.dart';

import '../models/offline_transaction.dart';
import '../services/transaction_split_service.dart';
import '../services/transactions_service.dart';
import '../widgets/ds/ds.dart';
import 'transaction_edit_screen.dart';

/// Opens the transaction sheet for [transaction]: the [TransactionEditScreen]
/// in a Sure sheet with Cancel and a bold Save.
///
/// Resolves to `true` when anything was saved, split or deleted (also when
/// the sheet was then dragged away), so the caller can reload; otherwise null.
Future<bool?> showTransactionSheet(
  BuildContext context, {
  required OfflineTransaction transaction,
  TransactionsService? transactionsService,
  TransactionSplitService? splitService,
}) async {
  var changed = false;
  final result = await showSureSheet<bool>(
    context: context,
    builder: (_) => TransactionEditScreen(
      transaction: transaction,
      asSheet: true,
      onChanged: () => changed = true,
      transactionsService: transactionsService,
      splitService: splitService,
    ),
  );
  return result ?? (changed ? true : null);
}
