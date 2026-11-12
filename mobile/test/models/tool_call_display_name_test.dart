import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/tool_call.dart';

ToolCall _call(String name) => ToolCall(
      id: '1',
      functionName: name,
      functionArguments: const {},
      createdAt: DateTime(2026, 11, 11),
    );

void main() {
  test('tool names read as plain labels', () {
    expect(_call('get_income_statement').displayName, 'Income statement');
    expect(_call('get_accounts').displayName, 'Accounts');
    expect(_call('search_transactions').displayName, 'Transactions');
    expect(_call('import_bank_statement').displayName, 'Import bank statement');
    expect(_call('compare-periods').displayName, 'Compare periods');
  });

  test('a bare prefix or empty name falls back to the raw name', () {
    expect(_call('get_').displayName, 'Get');
    expect(_call('').displayName, '');
  });
}
