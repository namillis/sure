import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/category.dart' as models;
import '../theme/sure_colors.dart';
import 'ds/ds.dart';
import 'metadata_picker_sheet.dart';

/// One row of the category picker.
class CategoryPickerEntry {
  const CategoryPickerEntry({
    required this.id,
    required this.name,
    this.searchText,
    this.color,
    this.icon,
  });

  final String id;
  final String name;

  /// What a search matches against: the full path ("Food > Groceries"), so
  /// searching a parent's name also finds its subcategories.
  final String? searchText;
  final String? color;
  final String? icon;
}

/// A run of picker rows, under a parent category's name or (for top-level
/// categories without subcategories) under no header.
class CategoryPickerSection {
  const CategoryPickerSection({this.header, required this.entries});

  final String? header;
  final List<CategoryPickerEntry> entries;
}

/// Groups [categories] for the picker: first one headerless section of the
/// top-level categories that have no subcategories (plus any [extra] option
/// the list doesn't have), then one section per parent, headed by its name,
/// holding the parent itself and then its subcategories. Everything is sorted
/// by name, and a non-empty [query] keeps only matching rows (and drops
/// sections left empty).
List<CategoryPickerSection> groupCategoriesForPicker(
  List<models.Category> categories, {
  List<PickerOption> extra = const [],
  String query = '',
}) {
  int byName(CategoryPickerEntry a, CategoryPickerEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  CategoryPickerEntry entry(models.Category c) => CategoryPickerEntry(
        id: c.id,
        name: c.name,
        searchText: c.displayName,
        color: c.color,
        icon: c.icon,
      );

  final byId = {for (final c in categories) c.id: c};
  final childrenOf = <String, List<models.Category>>{};
  final parentNames = <String, String>{};
  for (final c in categories) {
    final parent = c.parent;
    if (parent == null) continue;
    childrenOf.putIfAbsent(parent.id, () => []).add(c);
    parentNames[parent.id] = byId[parent.id]?.name ?? parent.name;
  }

  final loose = <CategoryPickerEntry>[
    for (final c in categories)
      if (c.parent == null && !childrenOf.containsKey(c.id)) entry(c),
    for (final option in extra)
      if (!byId.containsKey(option.id))
        CategoryPickerEntry(id: option.id, name: option.label),
  ]..sort(byName);

  final groups = <CategoryPickerSection>[
    for (final parentId in childrenOf.keys)
      CategoryPickerSection(
        header: parentNames[parentId],
        entries: [
          if (byId[parentId] != null) entry(byId[parentId]!),
          ...(childrenOf[parentId]!.map(entry).toList()..sort(byName)),
        ],
      ),
  ]..sort((a, b) => a.header!.toLowerCase().compareTo(b.header!.toLowerCase()));

  final q = query.trim().toLowerCase();
  bool matches(CategoryPickerEntry e) =>
      q.isEmpty || (e.searchText ?? e.name).toLowerCase().contains(q);

  return [
    for (final section in [
      CategoryPickerSection(entries: loose),
      ...groups,
    ])
      if (section.entries.where(matches).isNotEmpty)
        CategoryPickerSection(
          header: section.header,
          entries: section.entries.where(matches).toList(),
        ),
  ];
}

/// The category picker sheet: "Category" title with Done, a search field,
/// categories grouped under their parents, a 16 px category dot per row and a
/// check on the selected one. Tapping a row picks it and closes the sheet.
///
/// With [onCreate], a query that names no category offers a "Create" row;
/// without it, [createUnavailableNote] (if any) explains why.
class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.categories,
    this.extraOptions = const [],
    this.selectedId,
    this.loading = false,
    this.onCreate,
    this.createUnavailableNote,
  });

  final List<models.Category> categories;

  /// Options to offer that the category list may lack (the current category
  /// while the list is still loading).
  final List<PickerOption> extraOptions;
  final String? selectedId;
  final bool loading;
  final PickerCreate? onCreate;
  final String? createUnavailableNote;

  /// Shows the picker. Resolves to the picked category, or null when
  /// dismissed.
  static Future<PickerOption?> show(
    BuildContext context, {
    required List<models.Category> categories,
    List<PickerOption> extraOptions = const [],
    String? selectedId,
    bool loading = false,
    PickerCreate? onCreate,
    String? createUnavailableNote,
  }) {
    return showSureSheet<PickerOption>(
      context: context,
      builder: (_) => CategoryPickerSheet(
        categories: categories,
        extraOptions: extraOptions,
        selectedId: selectedId,
        loading: loading,
        onCreate: onCreate,
        createUnavailableNote: createUnavailableNote,
      ),
    );
  }

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final _searchController = TextEditingController();
  late final List<models.Category> _categories = [...widget.categories];
  late final List<PickerOption> _extra = [...widget.extraOptions];
  String _query = '';
  bool _creating = false;
  String? _createError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _canOfferCreate {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return false;
    return !_categories.any((c) => c.name.trim().toLowerCase() == query) &&
        !_extra.any((o) => o.label.trim().toLowerCase() == query);
  }

  PickerOption? _optionFor(String? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return PickerOption(id: c.id, label: c.displayName);
    }
    for (final o in _extra) {
      if (o.id == id) return o;
    }
    return null;
  }

  void _pick(String id) => Navigator.of(context).pop(_optionFor(id));

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
      Navigator.of(context).pop(option);
    } on PickerCreateException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _createError = e.message;
      });
    }
  }

  void _onSubmitted(List<CategoryPickerSection> sections) {
    final entries = [for (final s in sections) ...s.entries];
    if (entries.length == 1) {
      _pick(entries.first.id);
    } else if (entries.isEmpty && _canOfferCreate && widget.onCreate != null) {
      _create();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final sections =
        groupCategoriesForPicker(_categories, extra: _extra, query: _query);
    final showCreate = _canOfferCreate && widget.onCreate != null;
    final showUnavailable = _canOfferCreate &&
        widget.onCreate == null &&
        widget.createUnavailableNote != null;
    final searching = _query.trim().isNotEmpty;

    final Widget list;
    if (widget.loading && _categories.isEmpty && _extra.isEmpty) {
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
          if (sections.isEmpty && !showCreate)
            SureEmptyState(
              icon: searching ? SureIcons.search : SureIcons.shapes,
              title: searching ? l.dstNoCategoryMatches : l.dstNoCategories,
              body: searching ? l.dstNoCategoryMatchesBody : null,
            ),
          for (var i = 0; i < sections.length; i++) ...[
            if (sections[i].header != null)
              SureSectionHeader(
                label: sections[i].header!,
                padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 16, 4, 6),
              )
            else if (i > 0)
              const SizedBox(height: 16),
            SurePanel.rows(
              dividerIndent: _dotRowDividerIndent,
              children: [
                for (final entry in sections[i].entries)
                  PickerOptionRow(
                    key: ValueKey('category-${entry.id}'),
                    label: entry.name,
                    selected: entry.id == widget.selectedId,
                    leading: SureCategoryIcon(
                      name: entry.name,
                      color: entry.color,
                      icon: entry.icon,
                      size: SureCategoryIcon.dotSize,
                    ),
                    onTap: () => _pick(entry.id),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return SureSheet(
      title: l.transactionEditCategoryLabel,
      scrollable: false,
      actionLabel: l.dsDone,
      onAction: () => Navigator.of(context).pop(_optionFor(widget.selectedId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SureSearchField(
              controller: _searchController,
              hintText: l.dstSearchCategories,
              onChanged: (value) => setState(() {
                _query = value;
                _createError = null;
              }),
              onSubmitted: (_) => _onSubmitted(sections),
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

  /// 14 px row padding + 16 px dot + 12 px gap.
  static const double _dotRowDividerIndent = 42;
}
