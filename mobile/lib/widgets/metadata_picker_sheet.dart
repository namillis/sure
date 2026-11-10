import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import 'sure_text_field.dart';

/// One choice in a [MetadataPickerSheet].
class PickerOption {
  const PickerOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Creates an option named [name]. Returns the new option, or throws a
/// [PickerCreateException] whose message is shown under the search field.
typedef PickerCreate = Future<PickerOption> Function(String name);

class PickerCreateException implements Exception {
  const PickerCreateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A searchable bottom-sheet picker for categories, merchants and tags.
///
/// Single-select pops with the chosen id as soon as a row is tapped;
/// multi-select toggles rows and pops with the whole set on Done. Either way
/// the result is a `Set<String>`, or null when dismissed. With [onCreate],
/// a query that matches no option offers a "Create" row; without it,
/// [createUnavailableNote] (if any) explains why.
class MetadataPickerSheet extends StatefulWidget {
  const MetadataPickerSheet({
    super.key,
    required this.title,
    required this.options,
    this.initialSelection = const {},
    this.multiSelect = false,
    this.onCreate,
    this.createUnavailableNote,
    this.loading = false,
  });

  final String title;
  final List<PickerOption> options;
  final Set<String> initialSelection;
  final bool multiSelect;
  final PickerCreate? onCreate;
  final String? createUnavailableNote;
  final bool loading;

  static Future<Set<String>?> show(
    BuildContext context, {
    required String title,
    required List<PickerOption> options,
    Set<String> initialSelection = const {},
    bool multiSelect = false,
    PickerCreate? onCreate,
    String? createUnavailableNote,
    bool loading = false,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MetadataPickerSheet(
        title: title,
        options: options,
        initialSelection: initialSelection,
        multiSelect: multiSelect,
        onCreate: onCreate,
        createUnavailableNote: createUnavailableNote,
        loading: loading,
      ),
    );
  }

  @override
  State<MetadataPickerSheet> createState() => _MetadataPickerSheetState();
}

class _MetadataPickerSheetState extends State<MetadataPickerSheet> {
  final _searchController = TextEditingController();
  late final List<PickerOption> _options = [...widget.options];
  late final Set<String> _selected = {...widget.initialSelection};
  String _query = '';
  bool _creating = false;
  String? _createError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PickerOption> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _options;
    return _options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
  }

  bool get _canOfferCreate {
    final query = _query.trim().toLowerCase();
    return query.isNotEmpty &&
        !_options.any((option) => option.label.trim().toLowerCase() == query);
  }

  void _toggle(String id) {
    if (!widget.multiSelect) {
      Navigator.of(context).pop({id});
      return;
    }
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _create() async {
    final create = widget.onCreate;
    final name = _query.trim();
    if (create == null || name.isEmpty || _creating) return;

    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      final option = await create(name);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _options.add(option);
        _searchController.clear();
        _query = '';
      });
      _toggle(option.id);
    } on PickerCreateException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _createError = e.message;
      });
    }
  }

  void _onSubmitted(String _) {
    final matches = _filtered;
    if (matches.length == 1) {
      _toggle(matches.first.id);
    } else if (matches.isEmpty && _canOfferCreate && widget.onCreate != null) {
      _create();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final filtered = _filtered;
    final showCreate = _canOfferCreate && widget.onCreate != null;
    final showUnavailable = _canOfferCreate &&
        widget.onCreate == null &&
        widget.createUnavailableNote != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SureSpacing.xl,
                SureSpacing.lg,
                SureSpacing.md,
                SureSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: theme.textTheme.titleLarge),
                  ),
                  if (widget.multiSelect)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text(l.txnDetailDone),
                    )
                  else
                    IconButton(
                      tooltip: l.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SureSpacing.xl),
              child: SureTextField(
                controller: _searchController,
                hint: l.txnDetailSearchHint,
                prefixIcon: const Icon(Icons.search),
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() {
                  _query = value;
                  _createError = null;
                }),
                onFieldSubmitted: _onSubmitted,
              ),
            ),
            if (_createError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SureSpacing.xl,
                  SureSpacing.md,
                  SureSpacing.xl,
                  0,
                ),
                child: Text(
                  _createError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.destructive),
                ),
              ),
            const SizedBox(height: SureSpacing.md),
            Expanded(
              child: widget.loading && _options.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (showCreate)
                          ListTile(
                            minTileHeight: 48,
                            leading: _creating
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add),
                            title: Text(l.txnDetailCreateOption(_query.trim())),
                            onTap: _creating ? null : _create,
                          ),
                        if (showUnavailable)
                          Padding(
                            padding: const EdgeInsets.all(SureSpacing.xl),
                            child: Text(
                              widget.createUnavailableNote!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ),
                        if (filtered.isEmpty && !showCreate)
                          Padding(
                            padding: const EdgeInsets.all(SureSpacing.xl),
                            child: Text(
                              l.txnDetailPickerEmpty,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ),
                        for (final option in filtered)
                          _optionTile(option),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(PickerOption option) {
    final selected = _selected.contains(option.id);
    return ListTile(
      minTileHeight: 48,
      title: Text(option.label),
      selected: selected,
      // The check mark (not just the tint) shows selection.
      trailing: widget.multiSelect
          ? Checkbox(value: selected, onChanged: (_) => _toggle(option.id))
          : (selected ? const Icon(Icons.check) : null),
      onTap: () => _toggle(option.id),
    );
  }
}
