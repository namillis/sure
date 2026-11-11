import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/category.dart' as models;
import 'sure_chip.dart';

class CategoryFilter extends StatelessWidget {
  final List<models.Category> availableCategories;
  final Set<String> selectedCategoryIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  const CategoryFilter({
    super.key,
    required this.availableCategories,
    required this.selectedCategoryIds,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (availableCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    final isAllSelected = selectedCategoryIds.isEmpty;

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "All" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SureChip(
              label: l.commonAll,
              selected: isAllSelected,
              onSelected: (_) => onSelectionChanged({}),
            ),
          ),

          // Category chips
          ...availableCategories.map((category) {
            final isSelected =
                selectedCategoryIds.contains(category.id) && !isAllSelected;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SureChip(
                label: category.displayName,
                selected: isSelected,
                onSelected: (_) {
                  final newSelection = Set<String>.from(selectedCategoryIds);
                  if (isSelected) {
                    newSelection.remove(category.id);
                  } else {
                    if (isAllSelected) {
                      newSelection.clear();
                    }
                    newSelection.add(category.id);
                  }
                  if (newSelection.length == availableCategories.length) {
                    onSelectionChanged({});
                  } else {
                    onSelectionChanged(newSelection);
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
