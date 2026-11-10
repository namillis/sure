import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/utils/split_math.dart';

void main() {
  group('SplitMath.toUnits / fromUnits', () {
    test('parses canonical decimals into ten-thousandths', () {
      expect(SplitMath.toUnits('100'), 1000000);
      expect(SplitMath.toUnits('12.5'), 125000);
      expect(SplitMath.toUnits('-0.0001'), -1);
      expect(SplitMath.toUnits('33.3300'), 333300);
    });

    test('rejects more than four decimals and non-numbers', () {
      expect(SplitMath.toUnits('1.00001'), isNull);
      expect(SplitMath.toUnits('abc'), isNull);
      expect(SplitMath.toUnits(''), isNull);
      expect(SplitMath.toUnits(null), isNull);
    });

    test('round-trips without trailing zeros', () {
      expect(SplitMath.fromUnits(125000), '12.5');
      expect(SplitMath.fromUnits(-1), '-0.0001');
      expect(SplitMath.fromUnits(1000000), '100');
      expect(SplitMath.fromUnits(0), '0');
    });
  });

  group('SplitMath.check', () {
    test('balances to the cent where doubles would not', () {
      // 0.1 + 0.2 != 0.3 in floating point; exact units make it balance.
      final check = SplitMath.check(
        parentServerUnits: SplitMath.toUnits('0.3')!,
        typedParts: [SplitMath.toUnits('0.1'), SplitMath.toUnits('0.2')],
      );
      expect(check.remainingUnits, 0);
      expect(check.isValid, isTrue);
    });

    test('reports what is left and what is over', () {
      final under = SplitMath.check(
        parentServerUnits: 1000000,
        typedParts: [300000, 600000],
      );
      expect(under.remainingUnits, 100000);
      expect(under.isValid, isFalse);

      final over = SplitMath.check(
        parentServerUnits: 1000000,
        typedParts: [600000, 600000],
      );
      expect(over.remainingUnits, -200000);
      expect(over.isValid, isFalse);
    });

    test('a one-cent gap is not balanced', () {
      final check = SplitMath.check(
        parentServerUnits: SplitMath.toUnits('100')!,
        typedParts: [SplitMath.toUnits('33.33'), SplitMath.toUnits('66.66')],
      );
      expect(check.remainingUnits, 100);
      expect(check.balanced, isFalse);
    });

    test('an income parent is matched by positive typed parts', () {
      final check = SplitMath.check(
        parentServerUnits: -500000,
        typedParts: [200000, 300000],
      );
      expect(check.isValid, isTrue);
    });

    test('a negative part offsets the others', () {
      final check = SplitMath.check(
        parentServerUnits: 500000,
        typedParts: [700000, -200000],
      );
      expect(check.isValid, isTrue);
    });

    test('flags empty and zero rows and needs two rows', () {
      final check = SplitMath.check(
        parentServerUnits: 500000,
        typedParts: [500000, null, 0],
      );
      expect(check.invalidRows, [1, 2]);
      expect(check.balanced, isTrue);
      expect(check.isValid, isFalse);

      final single = SplitMath.check(
        parentServerUnits: 500000,
        typedParts: [500000],
      );
      expect(single.hasEnoughRows, isFalse);
      expect(single.isValid, isFalse);
    });
  });

  group('sign conversion', () {
    test('typed parts take the parent direction on the way out', () {
      expect(SplitMath.toServerUnits(200000, parentServerUnits: 500000), 200000);
      expect(
          SplitMath.toServerUnits(200000, parentServerUnits: -500000), -200000);
      expect(SplitMath.toServerUnits(-1, parentServerUnits: -500000), 1);
    });

    test('stored children read back as typed', () {
      expect(
          SplitMath.toTypedUnits(-200000, parentServerUnits: -500000), 200000);
      expect(SplitMath.toTypedUnits(200000, parentServerUnits: 500000), 200000);
    });
  });

  group('parseTyped and toEditText', () {
    test('reads locale input through AmountParser', () {
      expect(SplitMath.parseTyped('1,234.50', locale: 'en_US'), 12345000);
      expect(SplitMath.parseTyped('12,5', locale: 'sv'), 125000);
      expect(SplitMath.parseTyped('-3', locale: 'en_US'), -30000);
      expect(SplitMath.parseTyped('', locale: 'en_US'), isNull);
      expect(SplitMath.parseTyped('1.23456', locale: 'en_US'), isNull);
    });

    test('prefills with the locale decimal separator and reads it back', () {
      expect(SplitMath.toEditText(12345000, locale: 'en_US'), '1234.50');
      expect(SplitMath.toEditText(12345000, locale: 'sv'), '1234,50');
      expect(SplitMath.toEditText(123456, locale: 'en_US'), '12.3456');
      expect(SplitMath.toEditText(12340, locale: 'en_US'), '1.234');
      for (final locale in ['en_US', 'sv']) {
        for (final units in [12340, 123456, 12345000, 10000]) {
          expect(
            SplitMath.parseTyped(
              SplitMath.toEditText(units, locale: locale),
              locale: locale,
            ),
            units,
            reason: '$units in $locale',
          );
        }
      }
    });
  });
}
