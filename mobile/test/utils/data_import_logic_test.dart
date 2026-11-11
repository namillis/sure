import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/utils/data_import_logic.dart';

void main() {
  test('size checks follow the server limits', () {
    expect(isUploadSizeAllowed(10 * 1024 * 1024, maxCsvImportBytes), true);
    expect(isUploadSizeAllowed(10 * 1024 * 1024 + 1, maxCsvImportBytes), false);
    expect(isUploadSizeAllowed(0, maxCsvImportBytes), false);
    expect(isUploadSizeAllowed(25 * 1024 * 1024, maxStatementBytes), true);
    expect(formatByteSize(512), '512 B');
    expect(formatByteSize(1536), '1.5 KB');
    expect(formatByteSize(4 * 1024 * 1024), '4.0 MB');
  });

  test('extensions are case-insensitive', () {
    expect(fileExtension('Bank.CSV'), 'csv');
    expect(fileExtension('noext'), '');
    expect(hasAllowedExtension('a.Xlsx', statementContentTypes.keys), true);
    expect(hasAllowedExtension('a.png', statementContentTypes.keys), false);
  });

  test('prefill maps common headers and uses each once', () {
    final mapping = prefillColumnMapping(
        ['Posted Date', 'Description', 'Amount', 'Category', 'Memo']);
    expect(mapping[ImportColumn.date], 'Posted Date');
    expect(mapping[ImportColumn.amount], 'Amount');
    expect(mapping[ImportColumn.name], 'Description');
    expect(mapping[ImportColumn.category], 'Category');
    expect(mapping[ImportColumn.notes], 'Memo');
    expect(mapping[ImportColumn.tags], isNull);
    expect(hasRequiredColumns(mapping), true);

    final swedish = prefillColumnMapping(['Bokföringsdag', 'Belopp', 'Rubrik']);
    expect(swedish[ImportColumn.date], 'Bokföringsdag');
    expect(swedish[ImportColumn.amount], 'Belopp');
    expect(swedish[ImportColumn.name], 'Rubrik');

    final fuzzy = prefillColumnMapping(['Txn date (UTC)', 'Debit amount']);
    expect(fuzzy[ImportColumn.date], 'Txn date (UTC)');
    expect(fuzzy[ImportColumn.amount], 'Debit amount');

    expect(hasRequiredColumns(prefillColumnMapping(['Foo', 'Amount'])), false);
  });

  test('detects date formats and separators', () {
    expect(detectDateFormat(['2026-11-01', '2026-10-31']), '%Y-%m-%d');
    expect(detectDateFormat(['13/01/2026', '02/02/2026']), '%d/%m/%Y');
    expect(detectDateFormat(['01/13/2026']), '%m/%d/%Y');
    expect(detectDateFormat(['01.11.2026']), '%d.%m.%Y');
    expect(detectDateFormat(['01 Nov 2026']), '%d %b %Y');
    expect(detectDateFormat(['nonsense']), isNull);
    expect(detectColumnSeparator('Datum;Belopp;"a,b"\n1;2;3'), ';');
    expect(detectColumnSeparator('Date,Amount\n'), ',');
  });

  test('parseCsv handles quotes, CRLF, BOM and limits', () {
    final records = parseCsv(
        '\uFEFFDate,Name,Amount\r\n11/01/2026,"Coffee, ""large""",-4.50\r\n\r\n11/02/2026,Tea,-2\r\n');
    expect(records, [
      ['Date', 'Name', 'Amount'],
      ['11/01/2026', 'Coffee, "large"', '-4.50'],
      ['11/02/2026', 'Tea', '-2'],
    ]);
    expect(parseCsv('a;b\n1;2\n3;4', separator: ';', maxRecords: 2), [
      ['a', 'b'],
      ['1', '2'],
    ]);
    expect(columnValues(records, 'Name'), ['Coffee, "large"', 'Tea']);
    expect(columnValues(records, 'Missing'), isEmpty);
  });
}
