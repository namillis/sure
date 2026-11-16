/// A file attached to a transaction (Sure+ `transactions.attachments`): a
/// receipt photo or a PDF. [url] streams the file and needs the API auth
/// headers; it is not a public link.
class TransactionAttachment {
  const TransactionAttachment({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.byteSize,
    required this.url,
    this.createdAt,
  });

  final String id;
  final String filename;
  final String contentType;
  final int byteSize;
  final String url;
  final DateTime? createdAt;

  bool get isImage => contentType.toLowerCase().startsWith('image/');
  bool get isPdf => contentType.toLowerCase() == 'application/pdf';

  /// Null when [json] has no id.
  static TransactionAttachment? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final size = json['byte_size'];
    return TransactionAttachment(
      id: id,
      filename: json['filename']?.toString() ?? '',
      contentType: json['content_type']?.toString() ?? '',
      byteSize: size is num ? size.toInt() : int.tryParse('$size') ?? 0,
      url: json['url']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  /// The `attachments` array, or null when the server didn't send one.
  static List<TransactionAttachment>? listFromJson(Object? json) {
    if (json is! List) return null;
    return List.unmodifiable(
        json.map(TransactionAttachment.fromJson).whereType<TransactionAttachment>());
  }
}
