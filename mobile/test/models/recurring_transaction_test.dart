import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';

import '../support/recurring_fixtures.dart';

void main() {
  final list = {
    'cat_gym': Category(id: 'cat_gym', name: 'Fitness', icon: 'dumbbell'),
  };

  test('reads the embedded category (recurring.category)', () {
    final item = RecurringTransaction.fromJson(recurringJson(
      categoryId: 'cat_rent',
      category: {
        'id': 'cat_rent',
        'name': 'Housing',
        'color': '#4da568',
        'icon': 'house',
      },
    ));

    expect(item.category!.name, 'Housing');
    expect(item.category!.color, '#4da568');
    expect(item.category!.icon, 'house');
    expect(item.needsCategoryLookup, isFalse);
    expect(item.resolveCategory(list)!.id, 'cat_rent');
  });

  test('without an embedded category, looks the id up', () {
    final item =
        RecurringTransaction.fromJson(recurringJson(categoryId: 'cat_gym'));

    expect(item.category, isNull);
    expect(item.needsCategoryLookup, isTrue);
    expect(item.resolveCategory(list)!.name, 'Fitness');
  });

  test('a null category on an uncategorized item needs no lookup', () {
    final item =
        RecurringTransaction.fromJson(recurringJson(embedCategory: true));

    expect(item.category, isNull);
    expect(item.needsCategoryLookup, isFalse);
    expect(item.resolveCategory(list), isNull);
  });
}
