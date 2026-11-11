/// One bank or broker connection from `GET /api/v1/provider_connections`
/// (`ProviderConnectionStatus#to_h` on the server).
class ProviderConnection {
  const ProviderConnection({
    required this.id,
    required this.provider,
    required this.name,
    this.status,
    this.requiresUpdate = false,
    this.scheduledForDeletion = false,
    this.pendingAccountSetup = false,
    this.institutionName,
    this.totalAccounts = 0,
    this.linkedAccounts = 0,
    this.unlinkedAccounts = 0,
    this.syncing = false,
    this.lastSyncedAt,
    this.latestSyncStatus,
    this.syncErrorMessage,
  });

  final String id;

  /// Provider key, e.g. `plaid`, `simplefin`, `enable_banking`.
  final String provider;
  final String name;

  /// The provider item's own status, e.g. `good` or `requires_update`. The
  /// values differ per provider, so only `requires_update` is interpreted.
  final String? status;
  final bool requiresUpdate;
  final bool scheduledForDeletion;
  final bool pendingAccountSetup;
  final String? institutionName;
  final int totalAccounts;
  final int linkedAccounts;
  final int unlinkedAccounts;
  final bool syncing;

  /// When the newest completed sync finished.
  final DateTime? lastSyncedAt;

  /// Status of the newest sync, completed or not.
  final String? latestSyncStatus;

  /// Server text when the newest sync failed or went stale.
  final String? syncErrorMessage;

  /// The institution name when the server knows one, else the item name.
  String get displayName {
    final institution = institutionName?.trim() ?? '';
    return institution.isNotEmpty ? institution : name;
  }

  /// `enable_banking` -> `Enable banking`, matching the server's `humanize`.
  String get providerLabel {
    final words = provider.replaceAll('_', ' ').trim();
    if (words.isEmpty) return provider;
    return words[0].toUpperCase() + words.substring(1);
  }

  bool get needsReconnect => requiresUpdate || status == 'requires_update';

  bool get hasSyncError => syncErrorMessage != null;

  /// Something only the web can fix: a login to renew, a failed sync, or
  /// accounts waiting to be linked.
  bool get needsAttention =>
      !scheduledForDeletion &&
      (needsReconnect || hasSyncError || pendingAccountSetup);

  factory ProviderConnection.fromJson(Map<String, dynamic> json) {
    final institution = _map(json['institution']);
    final accounts = _map(json['accounts']);
    final sync = _map(json['sync']);
    final latest = _map(sync['latest']);
    final error = _map(latest['error']);
    final errorMessage = error['present'] == true
        ? (error['message']?.toString().trim() ?? '')
        : null;

    return ProviderConnection(
      id: json['id'].toString(),
      provider: json['provider']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString(),
      requiresUpdate: json['requires_update'] == true,
      scheduledForDeletion: json['scheduled_for_deletion'] == true,
      pendingAccountSetup: json['pending_account_setup'] == true,
      institutionName: institution['name']?.toString(),
      totalAccounts: _int(accounts['total_count']),
      linkedAccounts: _int(accounts['linked_count']),
      unlinkedAccounts: _int(accounts['unlinked_count']),
      syncing: sync['syncing'] == true,
      lastSyncedAt: _date(sync['last_synced_at']),
      latestSyncStatus: latest['status']?.toString(),
      syncErrorMessage: errorMessage,
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
