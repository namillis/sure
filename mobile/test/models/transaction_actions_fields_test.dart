import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/transaction.dart';

void main() {
  test('parses the round 4b action fields', () {
    final t = Transaction.fromJson({
      'id': 't1',
      'account': {'id': 'a1'},
      'name': 'Coffee',
      'date': '2026-11-06',
      'amount': '\$4.50',
      'currency': 'USD',
      'transfer': {
        'id': 'tr1',
        'status': 'pending',
        'other_account': {'id': 'a2', 'name': 'Savings'},
      },
      'pending': true,
      'duplicate_suspected': true,
      'duplicate_confidence': 'high',
      'duplicate_candidate': {
        'id': 't2',
        'entry_id': 'e2',
        'date': '2026-11-07',
        'name': 'Coffee posted',
        'amount': '\$4.50',
        'amount_cents': 450,
        'signed_amount_cents': -450,
        'currency': 'USD',
      },
      'sync_locked': true,
      'locked_attributes': [
        {'field': 'name', 'locked_at': '2026-11-01T10:00:00Z'},
        {'field': '', 'locked_at': null},
        'junk',
      ],
      'reconciled_status': 'cleared',
      'reconcilable': true,
    });

    expect(t.transfer!.status, 'pending');
    expect(t.pending, isTrue);
    expect(t.duplicateSuspected, isTrue);
    expect(t.duplicateConfidence, 'high');
    expect(t.duplicateCandidate!.entryId, 'e2');
    expect(t.duplicateCandidate!.name, 'Coffee posted');
    expect(t.duplicateCandidate!.signedAmountCents, -450);
    expect(t.syncLocked, isTrue);
    expect(t.lockedAttributes.map((a) => a.field), ['name']);
    expect(t.lockedAttributes.single.lockedAt, '2026-11-01T10:00:00Z');
    expect(t.reconciledStatus, 'cleared');
    expect(t.reconcilable, isTrue);
  });

  test('an older server leaves them null or empty', () {
    final t = Transaction.fromJson({
      'id': 't1',
      'account': {'id': 'a1'},
      'name': 'Coffee',
      'date': '2026-11-06',
      'amount': '\$4.50',
      'currency': 'USD',
      'transfer': {'id': 'tr1'},
    });

    expect(t.transfer!.status, isNull);
    expect(t.pending, isNull);
    expect(t.duplicateSuspected, isNull);
    expect(t.duplicateCandidate, isNull);
    expect(t.syncLocked, isNull);
    expect(t.lockedAttributes, isEmpty);
    expect(t.reconciledStatus, isNull);
    expect(t.reconcilable, isNull);
  });
}
