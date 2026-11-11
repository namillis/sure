import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/widgets/category_picker_sheet.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/metadata_picker_sheet.dart';

import '../support/ds_harness.dart';

final _food = Category(
  id: 'food',
  name: 'Food & Dining',
  color: '#eb5429',
  icon: 'utensils',
  subcategoriesCount: 2,
);
final _categories = [
  Category(id: 'rent', name: 'Rent', color: '#4da568', icon: 'house'),
  Category(
    id: 'groceries',
    name: 'Groceries',
    color: '#eb5429',
    icon: 'shopping-cart',
    parent: Category(id: 'food', name: 'Food & Dining'),
  ),
  _food,
  Category(
    id: 'coffee',
    name: 'Coffee',
    color: '#e99537',
    icon: 'coffee',
    parent: Category(id: 'food', name: 'Food & Dining'),
  ),
  Category(id: 'income', name: 'Income', color: '#1570ef'),
];

Future<void> _openPicker(WidgetTester tester, {String? selectedId}) async {
  await pumpDs(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => CategoryPickerSheet.show(
          context,
          categories: _categories,
          selectedId: selectedId,
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('groupCategoriesForPicker', () {
    test('puts loose top-level categories first, then one section per parent',
        () {
      final sections = groupCategoriesForPicker(_categories);
      expect(sections.map((s) => s.header), [null, 'Food & Dining']);
      expect(sections[0].entries.map((e) => e.name), ['Income', 'Rent']);
      expect(
        sections[1].entries.map((e) => e.name),
        ['Food & Dining', 'Coffee', 'Groceries'],
      );
    });

    test('search matches the full path and drops empty sections', () {
      final byParent = groupCategoriesForPicker(_categories, query: 'food');
      expect(byParent.single.header, 'Food & Dining');
      expect(byParent.single.entries, hasLength(3));

      final byChild = groupCategoriesForPicker(_categories, query: 'COFF');
      expect(byChild.single.entries.single.id, 'coffee');

      expect(groupCategoriesForPicker(_categories, query: 'zzz'), isEmpty);
    });

    test('offers extra options the list lacks, once', () {
      final sections = groupCategoriesForPicker(
        _categories,
        extra: const [
          PickerOption(id: 'rent', label: 'Rent'),
          PickerOption(id: 'old', label: 'Archived'),
        ],
      );
      expect(
        sections.first.entries.map((e) => e.id),
        ['old', 'income', 'rent'],
      );
    });
  });

  testWidgets('shows the title, Done, search, parent headers and dots',
      (tester) async {
    await _openPicker(tester, selectedId: 'coffee');

    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Search categories'), findsOneWidget);
    expect(
      find.widgetWithText(SureSectionHeader, 'Food & Dining'),
      findsOneWidget,
    );
    final dots = tester.widgetList<SureCategoryIcon>(
      find.byType(SureCategoryIcon),
    );
    expect(dots, hasLength(5));
    expect(dots.every((d) => d.size == SureCategoryIcon.dotSize), isTrue);

    // Only the selected row has the check mark.
    final checks = find.byWidgetPredicate(
      (w) => w is SureIcon && w.name == SureIcons.check,
    );
    expect(checks, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category-coffee')),
        matching: checks,
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a row picks it', (tester) async {
    PickerOption? picked;
    await pumpDs(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await CategoryPickerSheet.show(
              context,
              categories: _categories,
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(picked?.id, 'groceries');
    expect(picked?.label, 'Food & Dining > Groceries');
  });

  testWidgets('no matches shows the empty state', (tester) async {
    await _openPicker(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.byType(SureEmptyState), findsOneWidget);
    expect(find.text('No categories match'), findsOneWidget);
    expect(find.text('Try a different search.'), findsOneWidget);
  });

  testWidgets('a query that names nothing offers Create when online',
      (tester) async {
    PickerOption? picked;
    await pumpDs(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await CategoryPickerSheet.show(
              context,
              categories: _categories,
              onCreate: (name) async => PickerOption(id: 'new', label: name),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pets');
    await tester.pump();
    await tester.tap(find.text('Create “Pets”'));
    await tester.pumpAndSettle();

    expect(picked?.id, 'new');
    expect(picked?.label, 'Pets');
  });

  for (final brightness in brightnesses) {
    testWidgets('renders at 320 px ($brightness)', (tester) async {
      await pumpDs(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => CategoryPickerSheet.show(
              context,
              categories: [
                ..._categories,
                Category(
                  id: 'long',
                  name: 'A very long category name that should ellipsize',
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
        width: 320,
        brightness: brightness,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  group('MetadataPickerSheet', () {
    testWidgets('multi-select toggles check marks and returns them on Done',
        (tester) async {
      Set<String>? picked;
      await pumpDs(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await MetadataPickerSheet.show(
                context,
                title: 'Choose tags',
                options: const [
                  PickerOption(id: 't1', label: 'Work'),
                  PickerOption(id: 't2', label: 'Travel'),
                ],
                initialSelection: const {'t1'},
                multiSelect: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work'));
      await tester.tap(find.text('Travel'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(picked, {'t2'});
    });

    testWidgets('no matches shows the empty state', (tester) async {
      await pumpDs(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => MetadataPickerSheet.show(
              context,
              title: 'Choose merchant',
              options: const [PickerOption(id: 'm1', label: 'Blue Bottle')],
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
    });
  });
}
