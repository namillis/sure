import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/activity_transaction.dart';

void main() {
  Map<String, dynamic> json({Object? category}) => {
        'id': 't1',
        'name': 'Whole Foods',
        'date': '2026-11-09',
        'amount': r'$54.20',
        'currency': 'USD',
        'classification': 'expense',
        'account': {
          'id': 'a1',
          'name': 'Checking',
          'account_type': 'depository'
        },
        'category': category,
      };

  test('reads the category color and Lucide icon', () {
    final row = ActivityTransaction.fromJson(json(category: {
      'id': 'c1',
      'name': 'Groceries',
      'color': '#407706',
      'icon': 'shopping-bag',
    }));
    expect(row.categoryColor, '#407706');
    expect(row.categoryIcon, 'shopping-bag');
  });

  test('no category leaves the icon null', () {
    final row = ActivityTransaction.fromJson(json());
    expect(row.categoryIcon, isNull);
  });

  test('withCategory replaces the icon', () {
    final row = ActivityTransaction.fromJson(json(category: {
      'id': 'c1',
      'name': 'Groceries',
      'color': '#407706',
      'icon': 'shopping-bag',
    })).withCategory(
        id: 'c2', name: 'Coffee', color: '#b45309', icon: 'coffee');
    expect(row.transaction.categoryName, 'Coffee');
    expect(row.categoryColor, '#b45309');
    expect(row.categoryIcon, 'coffee');
  });
}
