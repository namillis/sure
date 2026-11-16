/// One of the signed-in user's API keys from `GET /api/v1/api_keys`
/// (Sure+ `settings.api_keys`). The full key is never part of this model:
/// the server returns it once, as `plain_key`, on create.
class ApiKey {
  const ApiKey({
    required this.id,
    required this.name,
    required this.scopes,
    required this.displayKey,
    this.current = false,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  final String id;
  final String name;

  /// `["read"]` or `["read_write"]`.
  final List<String> scopes;

  /// The masked key, e.g. `********a1b2`.
  final String displayKey;

  /// True for the key this app is signed in with.
  final bool current;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  bool get canWrite => scopes.contains('read_write');

  factory ApiKey.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    final scopes = json['scopes'];
    return ApiKey(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      scopes: scopes is List
          ? scopes.map((s) => s.toString()).toList()
          : scopes is String
              ? [scopes]
              : const [],
      displayKey: json['display_key']?.toString() ?? '',
      current: json['current'] == true,
      createdAt: date(json['created_at']),
      lastUsedAt: date(json['last_used_at']),
      expiresAt: date(json['expires_at']),
    );
  }
}
