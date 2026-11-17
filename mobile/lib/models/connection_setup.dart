/// One entry of `GET /api/v1/provider_connections/available`
/// (`ProviderConnectionCatalog.available_for` on the server).
class AvailableConnection {
  const AvailableConnection({
    required this.provider,
    required this.key,
    required this.name,
    required this.connectPath,
    required this.kind,
  });

  /// Provider key, e.g. `plaid`, `simplefin`.
  final String provider;

  /// Unique per entry: `plaid_us` and `plaid_eu` are separate entries.
  final String key;
  final String name;

  /// A server-relative path the web handoff accepts.
  final String connectPath;

  /// `token` (native create) or `web` (handoff).
  final String kind;

  bool get isToken => kind == 'token';

  factory AvailableConnection.fromJson(Map<String, dynamic> json) =>
      AvailableConnection(
        provider: json['provider']?.toString() ?? '',
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        connectPath: json['connect_path']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'web',
      );
}

/// A subtype choice of an [AllowedAccountType].
class AccountSubtypeOption {
  const AccountSubtypeOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// An account type a pending account may be imported as, with its subtypes.
class AllowedAccountType {
  const AllowedAccountType({
    required this.accountableType,
    required this.label,
    this.subtypes = const [],
  });

  final String accountableType;
  final String label;
  final List<AccountSubtypeOption> subtypes;

  factory AllowedAccountType.fromJson(Map<String, dynamic> json) =>
      AllowedAccountType(
        accountableType: json['accountable_type']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        subtypes: [
          for (final s in (json['subtypes'] as List<dynamic>? ?? const []))
            if (s is Map)
              AccountSubtypeOption(
                value: s['value']?.toString() ?? '',
                label: s['label']?.toString() ?? '',
              ),
        ],
      );
}

/// One provider account waiting for setup, from
/// `GET /api/v1/provider_connections/:id/pending_accounts`.
class PendingAccount {
  const PendingAccount({
    required this.id,
    required this.name,
    this.institution,
    required this.balance,
    this.balanceCents,
    required this.currency,
    this.suggestedAccountableType,
    this.suggestedSubtype,
    this.allowedTypes = const [],
  });

  final String id;
  final String name;
  final String? institution;

  /// Formatted by the server, e.g. `$1,234.56`.
  final String balance;
  final int? balanceCents;
  final String currency;
  final String? suggestedAccountableType;
  final String? suggestedSubtype;
  final List<AllowedAccountType> allowedTypes;

  factory PendingAccount.fromJson(Map<String, dynamic> json) => PendingAccount(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        institution: json['institution']?.toString(),
        balance: json['balance']?.toString() ?? '',
        balanceCents: json['balance_cents'] is num
            ? (json['balance_cents'] as num).toInt()
            : null,
        currency: json['currency']?.toString() ?? '',
        suggestedAccountableType: json['suggested_accountable_type']?.toString(),
        suggestedSubtype: json['suggested_subtype']?.toString(),
        allowedTypes: [
          for (final t in (json['allowed_types'] as List<dynamic>? ?? const []))
            if (t is Map) AllowedAccountType.fromJson(t.cast<String, dynamic>()),
        ],
      );
}
