import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/category.dart' as models;
import '../models/merchant.dart';
import '../models/transaction_tag.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/tags_provider.dart';
import '../services/metadata_create_service.dart';
import 'category_picker_sheet.dart';
import 'metadata_picker_sheet.dart';

/// Category, merchant and tag pickers for the transaction editors. Each
/// offers "Create" while [online], refreshes its provider after a create, and
/// returns the chosen options (id and label), or null when dismissed.
class TransactionMetadataPickers {
  TransactionMetadataPickers({MetadataCreateService? service})
      : _service = service ?? MetadataCreateService();

  final MetadataCreateService _service;

  Future<PickerOption?> pickCategory(
    BuildContext context, {
    required bool online,
    String? selectedId,
    List<PickerOption> extraOptions = const [],
  }) {
    final l = AppLocalizations.of(context);
    final provider = context.read<CategoriesProvider>();
    final onCreate = _creator(
      context,
      (token, name) async {
        final result =
            await _service.createCategory(accessToken: token, name: name);
        if (result['success'] != true) return result;
        final category = result['category'] as models.Category;
        provider.clear();
        provider.fetchCategories(accessToken: token);
        return {
          'success': true,
          'option': PickerOption(id: category.id, label: category.displayName),
        };
      },
    );
    return CategoryPickerSheet.show(
      context,
      categories: provider.categories,
      extraOptions: extraOptions,
      selectedId: selectedId,
      loading: provider.isLoading,
      onCreate: online ? onCreate : null,
      createUnavailableNote: online ? null : l.txnDetailCreateOffline,
    );
  }

  Future<PickerOption?> pickMerchant(
    BuildContext context, {
    required bool online,
    String? selectedId,
    List<PickerOption> extraOptions = const [],
  }) async {
    final l = AppLocalizations.of(context);
    final provider = context.read<MerchantsProvider>();
    final options = _merge(
      provider.merchants
          .map((Merchant m) => PickerOption(id: m.id, label: m.name)),
      extraOptions,
    );
    final picked = await _show(
      context,
      title: l.txnDetailChooseMerchant,
      options: options,
      selected: {if (selectedId != null) selectedId},
      loading: provider.isLoading,
      online: online,
      create: (token, name) async {
        final result =
            await _service.createMerchant(accessToken: token, name: name);
        if (result['success'] != true) return result;
        final merchant = result['merchant'] as Merchant;
        provider.fetchMerchants(accessToken: token, forceRefresh: true);
        return {
          'success': true,
          'option': PickerOption(id: merchant.id, label: merchant.name),
        };
      },
    );
    return picked?.firstOrNull;
  }

  Future<List<PickerOption>?> pickTags(
    BuildContext context, {
    required bool online,
    required Set<String> selectedIds,
    List<PickerOption> extraOptions = const [],
  }) {
    final l = AppLocalizations.of(context);
    final provider = context.read<TagsProvider>();
    final options = _merge(
      provider.tags
          .map((TransactionTag t) => PickerOption(id: t.id, label: t.name)),
      extraOptions,
    );
    return _show(
      context,
      title: l.txnDetailChooseTags,
      options: options,
      selected: selectedIds,
      multiSelect: true,
      loading: provider.isLoading,
      online: online,
      create: (token, name) async {
        final result = await _service.createTag(accessToken: token, name: name);
        if (result['success'] != true) return result;
        final tag = result['tag'] as TransactionTag;
        provider.fetchTags(accessToken: token, forceRefresh: true);
        return {
          'success': true,
          'option': PickerOption(id: tag.id, label: tag.name),
        };
      },
    );
  }

  List<PickerOption> _merge(
    Iterable<PickerOption> fromProvider,
    List<PickerOption> extra,
  ) {
    final options = fromProvider.toList();
    final ids = options.map((o) => o.id).toSet();
    options.addAll(extra.where((o) => ids.add(o.id)));
    return options;
  }

  Future<List<PickerOption>?> _show(
    BuildContext context, {
    required String title,
    required List<PickerOption> options,
    required Set<String> selected,
    required bool loading,
    required bool online,
    required Future<Map<String, dynamic>> Function(String token, String name)
        create,
    bool multiSelect = false,
  }) async {
    final l = AppLocalizations.of(context);
    final known = {for (final option in options) option.id: option};
    final onCreate = _creator(context, create, onCreated: (option) {
      known[option.id] = option;
    });

    final ids = await MetadataPickerSheet.show(
      context,
      title: title,
      options: options,
      initialSelection: selected,
      multiSelect: multiSelect,
      loading: loading,
      onCreate: online ? onCreate : null,
      createUnavailableNote: online ? null : l.txnDetailCreateOffline,
    );
    if (ids == null) return null;
    return [
      for (final id in ids)
        if (known[id] != null) known[id]!,
    ];
  }

  /// Wraps a create call in the picker's contract: a fresh token, and a
  /// [PickerCreateException] with a readable message on failure.
  PickerCreate _creator(
    BuildContext context,
    Future<Map<String, dynamic>> Function(String token, String name) create, {
    void Function(PickerOption option)? onCreated,
  }) {
    final l = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    return (String name) async {
      final token = await auth.getValidAccessToken();
      if (token == null) {
        throw PickerCreateException(l.transactionEditSessionExpired);
      }
      final result = await create(token, name);
      if (result['success'] != true) {
        throw PickerCreateException(
          result['error'] == 'unauthorized'
              ? l.transactionEditSessionExpired
              : result['error']?.toString() ?? l.txnDetailCreateFailed,
        );
      }
      final option = result['option'] as PickerOption;
      onCreated?.call(option);
      return option;
    };
  }
}
