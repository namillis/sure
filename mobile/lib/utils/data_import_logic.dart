/// Pure helpers for the CSV import wizard and the statement upload screen.
/// Free of Flutter and plugin types so they can be unit tested.
library;

/// `Import::MAX_CSV_SIZE` on the server.
const int maxCsvImportBytes = 10 * 1024 * 1024;

/// `AccountStatement::MAX_FILE_SIZE` on the server.
const int maxStatementBytes = 25 * 1024 * 1024;

/// `AccountStatement::ALLOWED_EXTENSION_CONTENT_TYPES` on the server: the
/// extension (without the dot) to the content type the app declares.
const Map<String, String> statementContentTypes = {
  'pdf': 'application/pdf',
  'csv': 'text/csv',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/// The lowercase extension of [filename] without the dot, or '' if none.
String fileExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}

/// Whether [filename] ends in one of [extensions] (lowercase, no dots).
bool hasAllowedExtension(String filename, Iterable<String> extensions) =>
    extensions.contains(fileExtension(filename));

/// Whether a file of [bytes] is over the server's [maxBytes] (or empty).
bool isUploadSizeAllowed(int bytes, int maxBytes) =>
    bytes > 0 && bytes <= maxBytes;

/// A short human size such as `512 B`, `12.3 KB` or `4.0 MB` (1024-based, as
/// the server's `megabyte` is).
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The CSV columns the wizard maps, with the `import_config_params` name the
/// server permits for each.
enum ImportColumn {
  date('date_col_label'),
  amount('amount_col_label'),
  name('name_col_label'),
  category('category_col_label'),
  tags('tags_col_label'),
  notes('notes_col_label');

  const ImportColumn(this.param);

  final String param;

  /// TransactionImport#required_column_keys.
  bool get required => this == ImportColumn.date || this == ImportColumn.amount;
}

String _normalize(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]'), '');

const Map<ImportColumn, List<String>> _synonyms = {
  ImportColumn.date: [
    'date', 'transactiondate', 'posteddate', 'postingdate', 'bookingdate',
    'valuedate', 'transdate', 'datum', 'bokföringsdag', 'transaktionsdag',
  ],
  ImportColumn.amount: [
    'amount', 'amt', 'transactionamount', 'value', 'belopp', 'sum', 'summa',
  ],
  ImportColumn.name: [
    'name', 'description', 'payee', 'merchant', 'title', 'text',
    'beskrivning', 'rubrik', 'mottagare',
  ],
  ImportColumn.category: ['category', 'categoryname', 'kategori'],
  ImportColumn.tags: ['tags', 'tag', 'labels', 'taggar'],
  ImportColumn.notes: ['notes', 'note', 'memo', 'comment', 'comments', 'anteckning'],
};

/// Prefills each [ImportColumn] with a header from [headers]: an exact
/// (case- and punctuation-insensitive) synonym first, then for date and
/// amount any header containing the word. Each header is used at most once.
Map<ImportColumn, String?> prefillColumnMapping(List<String> headers) {
  final result = <ImportColumn, String?>{
    for (final column in ImportColumn.values) column: null,
  };
  final used = <String>{};
  for (final column in ImportColumn.values) {
    final synonyms = _synonyms[column]!;
    for (final synonym in synonyms) {
      final match = headers.where((h) => !used.contains(h) && _normalize(h) == synonym);
      if (match.isNotEmpty) {
        result[column] = match.first;
        used.add(match.first);
        break;
      }
    }
  }
  for (final column in [ImportColumn.date, ImportColumn.amount]) {
    if (result[column] != null) continue;
    final word = column.name;
    final match = headers.where((h) => !used.contains(h) && _normalize(h).contains(word));
    if (match.isNotEmpty) {
      result[column] = match.first;
      used.add(match.first);
    }
  }
  return result;
}

/// Whether the mapping has the columns the server requires.
bool hasRequiredColumns(Map<ImportColumn, String?> mapping) => ImportColumn.values
    .where((c) => c.required)
    .every((c) => (mapping[c] ?? '').isNotEmpty);

/// `Family::DATE_FORMATS` plus `Import::CSV_ONLY_DATE_FORMATS`, the import's
/// default (`%m/%d/%Y`) first: (label, strftime value).
const List<(String, String)> importDateFormats = [
  ('MM/DD/YYYY', '%m/%d/%Y'),
  ('MM-DD-YYYY', '%m-%d-%Y'),
  ('DD.MM.YYYY', '%d.%m.%Y'),
  ('DD-MM-YYYY', '%d-%m-%Y'),
  ('YYYY-MM-DD', '%Y-%m-%d'),
  ('DD/MM/YYYY', '%d/%m/%Y'),
  ('YYYY/MM/DD', '%Y/%m/%d'),
  ('D/MM/YYYY', '%e/%m/%Y'),
  ('YYYY.MM.DD', '%Y.%m.%d'),
  ('YYYYMMDD', '%Y%m%d'),
  ('DD MMM YYYY', '%d %b %Y'),
  ('DD/MM/YY', '%d/%m/%y'),
];

/// `Import::NUMBER_FORMATS` keys; the first is the server default.
const List<String> importNumberFormats = ['1,234.56', '1.234,56', '1 234,56', '1,234'];

/// `Import::SIGNAGE_CONVENTIONS`; the first is the server default.
const List<String> importSignageConventions = ['inflows_positive', 'inflows_negative'];

/// `Import::SEPARATORS` values; the first is the server default.
const List<String> importColumnSeparators = [',', ';'];

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/// (regex, group index of day, month, year) for each strftime value.
final Map<String, (RegExp, int, int, int)> _datePatterns = {
  '%m/%d/%Y': (RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'), 2, 1, 3),
  '%m-%d-%Y': (RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$'), 2, 1, 3),
  '%d.%m.%Y': (RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$'), 1, 2, 3),
  '%d-%m-%Y': (RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$'), 1, 2, 3),
  '%Y-%m-%d': (RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$'), 3, 2, 1),
  '%d/%m/%Y': (RegExp(r'^(\d{2})/(\d{1,2})/(\d{4})$'), 1, 2, 3),
  '%Y/%m/%d': (RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$'), 3, 2, 1),
  '%e/%m/%Y': (RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'), 1, 2, 3),
  '%Y.%m.%d': (RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})$'), 3, 2, 1),
  '%Y%m%d': (RegExp(r'^(\d{4})(\d{2})(\d{2})$'), 3, 2, 1),
  '%d %b %Y': (RegExp(r'^(\d{1,2}) ([A-Za-z]{3}) (\d{4})$'), 1, 2, 3),
  '%d/%m/%y': (RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})$'), 1, 2, 3),
};

bool _matchesDate(String sample, String format) {
  final pattern = _datePatterns[format];
  if (pattern == null) return false;
  final (regex, dayGroup, monthGroup, _) = pattern;
  final match = regex.firstMatch(sample.trim());
  if (match == null) return false;
  final day = int.parse(match.group(dayGroup)!);
  final monthText = match.group(monthGroup)!;
  final month = int.tryParse(monthText) ??
      (_months.indexOf(monthText.toLowerCase()) + 1);
  return day >= 1 && day <= 31 && month >= 1 && month <= 12;
}

/// Whether [sample] fits the strftime [format] (one of [importDateFormats]).
bool dateMatchesFormat(String sample, String format) => _matchesDate(sample, format);

/// Whether [value] reads as a number in [numberFormat] (one of
/// [importNumberFormats]), ignoring currency symbols and spaces as the
/// server's `sanitize_number` does.
///
/// shortcut: approximates the server's parsing for the local preview; the
/// server's row validation is the source of truth after publish.
bool amountParses(String value, String numberFormat) {
  var text = value.trim();
  if (text.isEmpty) return false;
  final (separator, delimiter) = switch (numberFormat) {
    '1.234,56' => (',', '.'),
    '1 234,56' => (',', ' '),
    '1,234' => ('', ','),
    _ => ('.', ','),
  };
  if (text.startsWith('(') && text.endsWith(')')) {
    text = '-${text.substring(1, text.length - 1)}';
  }
  text = text.replaceAll(delimiter, '').replaceAll('\u00A0', '');
  if (separator.isNotEmpty) text = text.replaceAll(separator, '.');
  text = text.replaceAll(RegExp(r'[^0-9.\-+]'), '');
  return double.tryParse(text) != null;
}

/// The first of [importDateFormats] that every non-empty sample fits, or null.
/// Ambiguous samples (all days 12 or less) resolve to the earlier format, so
/// the user should still check the preview.
String? detectDateFormat(Iterable<String> samples) {
  final values = samples.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (values.isEmpty) return null;
  for (final (_, format) in importDateFormats) {
    if (values.every((v) => _matchesDate(v, format))) return format;
  }
  return null;
}

/// `;` when the header line has more semicolons than commas outside quotes,
/// else `,`.
String detectColumnSeparator(String content) {
  var commas = 0;
  var semicolons = 0;
  var quoted = false;
  for (final char in content.split('')) {
    if (char == '"') quoted = !quoted;
    if (quoted) continue;
    if (char == '\n' || char == '\r') break;
    if (char == ',') commas++;
    if (char == ';') semicolons++;
  }
  return semicolons > commas ? ';' : ',';
}

/// Parses up to [maxRecords] records (header included) of RFC 4180 CSV:
/// quoted fields, doubled quotes, CRLF or LF line ends, a leading BOM.
/// Blank lines are skipped.
List<List<String>> parseCsv(String content, {String separator = ',', int? maxRecords}) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = content.startsWith('\uFEFF') ? 1 : 0;

  void endRecord() {
    record.add(field.toString());
    field.clear();
    if (!(record.length == 1 && record.first.isEmpty)) records.add(record);
    record = <String>[];
  }

  while (i < content.length) {
    if (maxRecords != null && records.length >= maxRecords) return records;
    final char = content[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == separator) {
      record.add(field.toString());
      field.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') i++;
      endRecord();
    } else {
      field.write(char);
    }
    i++;
  }
  if (field.isNotEmpty || record.isNotEmpty) endRecord();
  if (maxRecords != null && records.length > maxRecords) {
    return records.sublist(0, maxRecords);
  }
  return records;
}

/// The values of [header] in [records] (first record is the header row), for
/// date-format detection and the local preview.
List<String> columnValues(List<List<String>> records, String header) {
  if (records.isEmpty) return const [];
  final index = records.first.indexOf(header);
  if (index < 0) return const [];
  return [
    for (final row in records.skip(1)) index < row.length ? row[index] : '',
  ];
}
