import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import 'ds/ds.dart';

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

/// A searchable Sure sheet picker for merchants and tags.
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
    return showSureSheet<Set<String>>(
      context: context,
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
    SureHaptics.selection();
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
    final filtered = _filtered;
    final showCreate = _canOfferCreate && widget.onCreate != null;
    final showUnavailable = _canOfferCreate &&
        widget.onCreate == null &&
        widget.createUnavailableNote != null;

    final Widget list;
    if (widget.loading && _options.isEmpty) {
      list = const Center(child: CircularProgressIndicator());
    } else {
      list = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (showCreate)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurePanel.rows(
                children: [
                  PickerCreateRow(
                    label: l.txnDetailCreateOption(_query.trim()),
                    creating: _creating,
                    onTap: _create,
                  ),
                ],
              ),
            ),
          if (showUnavailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                widget.createUnavailableNote!,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
          if (filtered.isEmpty && !showCreate)
            SureEmptyState(
              icon: SureIcons.search,
              title: l.txnDetailPickerEmpty,
            )
          else
            SurePanel.rows(
              children: [
                for (final option in filtered)
                  PickerOptionRow(
                    label: option.label,
                    selected: _selected.contains(option.id),
                    onTap: () => _toggle(option.id),
                  ),
              ],
            ),
        ],
      );
    }

    return SureSheet(
      title: widget.title,
      scrollable: false,
      actionLabel: l.txnDetailDone,
      onAction: widget.multiSelect
          ? () => Navigator.of(context).pop(_selected)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SureSearchField(
              controller: _searchController,
              hintText: l.txnDetailSearchHint,
              onChanged: (value) => setState(() {
                _query = value;
                _createError = null;
              }),
              onSubmitted: _onSubmitted,
            ),
          ),
          if (_createError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _createError!,
                style: TextStyle(fontSize: 13, color: palette.destructive),
              ),
            ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

/// A picker row: optional [leading] (a category dot), the label, and a check
/// mark when [selected].
class PickerOptionRow extends StatelessWidget {
  const PickerOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      selected: selected,
      child: SureListRow(
        title: label,
        leading: leading,
        onTap: onTap,
        trailing: selected
            ? SureIcon(SureIcons.check, size: 18, color: palette.link)
            : const SizedBox(width: 18),
      ),
    );
  }
}

/// The "Create “name”" row at the top of a picker's results.
class PickerCreateRow extends StatelessWidget {
  const PickerCreateRow({
    super.key,
    required this.label,
    required this.creating,
    required this.onTap,
  });

  final String label;
  final bool creating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return SureListRow(
      title: label,
      titleColor: palette.link,
      leading: SizedBox.square(
        dimension: 18,
        child: creating
            ? const CircularProgressIndicator(strokeWidth: 2)
            : SureIcon(SureIcons.plus, size: 18, color: palette.link),
      ),
      onTap: creating ? null : onTap,
    );
  }
}
