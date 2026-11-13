import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/budget.dart';
import 'package:sure_mobile/services/budgets_service.dart';

import '../support/budget_fixtures.dart';

void main() {
  group('BudgetsService writes (Sure+ budgets.write)', () {
    late List<http.Request> requests;

    BudgetsService serviceReturning(int status, Object body) {
      requests = [];
      return BudgetsService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), status);
        }),
      );
    }

    test('PATCHes a budget with only the given fields', () async {
      final service = serviceReturning(200, budgetJson(budgetedCents: 350050));
      final result = await service.updateBudget(
        accessToken: 'token',
        id: 'budget_oct',
        budgetedSpending: '3500.50',
      );

      expect(result['success'], isTrue);
      expect((result['budget'] as Budget).budgetedSpendingCents, 350050);
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/budgets/budget_oct');
      expect(jsonDecode(request.body), {
        'budget': {'budgeted_spending': '3500.50'},
      });
    });

    test('PATCHes a budget category amount and rollover', () async {
      final service = serviceReturning(
        200,
        budgetCategoryJson(
          id: 'bc_food',
          categoryId: 'cat_food',
          name: 'Food',
          budgetedCents: 65000,
        ),
      );
      final result = await service.updateBudgetCategory(
        accessToken: 'token',
        id: 'bc_food',
        budgetedSpending: '650',
        rolloverEnabled: true,
      );

      expect(result['success'], isTrue);
      final bc = result['budget_category'] as BudgetCategory;
      expect(bc.budgetedSpendingCents, 65000);
      expect(bc.hasRolloverSetting, isTrue);
      expect(requests.single.url.path, '/api/v1/budget_categories/bc_food');
      expect(jsonDecode(requests.single.body), {
        'budget_category': {'budgeted_spending': '650', 'rollover_enabled': true},
      });
    });

    test('a shared read-only budget is a forbidden failure', () async {
      final service = serviceReturning(403, {
        'error': 'forbidden',
        'message': 'This budget is shared with you read-only',
      });
      final result = await service.updateBudget(
        accessToken: 'token',
        id: 'budget_oct',
        expectedIncome: '6000',
      );

      expect(result['success'], isFalse);
      expect(result['code'], 'forbidden');
      expect(result['error'], 'This budget is shared with you read-only');
    });

    test('a read-only sign-in is insufficient_scope', () async {
      final service = serviceReturning(403, {
        'error': 'insufficient_scope',
        'message': "This action requires the 'read_write' scope",
      });
      final result = await service.updateBudgetCategory(
        accessToken: 'token',
        id: 'bc_food',
        budgetedSpending: '1',
      );

      expect(result['code'], 'insufficient_scope');
    });

    test('a 422 carries the server message', () async {
      final service = serviceReturning(422, {
        'error': 'validation_failed',
        'message': 'budgeted_spending must be a number greater than or equal to 0',
        'errors': ['budgeted_spending must be a number greater than or equal to 0'],
      });
      final result = await service.updateBudgetCategory(
        accessToken: 'token',
        id: 'bc_food',
        budgetedSpending: 'abc',
      );

      expect(result['code'], 'validation_failed');
      expect(
        result['error'],
        'budgeted_spending must be a number greater than or equal to 0',
      );
    });

    test('a 401 is unauthorized', () async {
      final service = serviceReturning(401, {'error': 'unauthorized'});
      final result = await service.updateBudget(
        accessToken: 'token',
        id: 'budget_oct',
        budgetedSpending: '1',
      );

      expect(result['error'], 'unauthorized');
      expect(result.containsKey('code'), isFalse);
    });
  });
}
