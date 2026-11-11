/// A `GET /api/v1/provider_connections` row, shaped like
/// `ProviderConnectionStatus#to_h`.
Map<String, dynamic> connectionJson({
  String id = 'c1',
  String provider = 'enable_banking',
  String status = 'good',
  bool requiresUpdate = false,
  bool pendingSetup = false,
  bool scheduledForDeletion = false,
  Map<String, dynamic>? latest,
  String? lastSyncedAt = '2026-11-11T10:00:00Z',
  String? institution = 'Example Bank',
  int unlinked = 0,
}) =>
    {
      'id': id,
      'provider': provider,
      'provider_type': 'EnableBankingItem',
      'name': 'Item name',
      'status': status,
      'requires_update': requiresUpdate,
      'credentials_configured': false,
      'scheduled_for_deletion': scheduledForDeletion,
      'pending_account_setup': pendingSetup,
      'institution': {'name': institution, 'domain': null, 'url': null},
      'accounts': {
        'total_count': 3,
        'linked_count': 3 - unlinked,
        'unlinked_count': unlinked,
      },
      'sync': {
        'syncing': false,
        'status_summary': '3 accounts synced',
        'last_synced_at': lastSyncedAt,
        'latest': latest,
      },
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-11-11T10:00:00Z',
    };
