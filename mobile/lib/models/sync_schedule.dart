/// One connection's sync schedule from
/// `GET /api/v1/provider_connections/:id/sync_schedule` (Sure+
/// `settings.sync_schedule`).
class SyncSchedule {
  const SyncSchedule({
    this.intervalMinutes,
    this.nextRunAt,
    this.allowedIntervals = const [],
  });

  /// Null means the usual sync, with no extra schedule.
  final int? intervalMinutes;
  final DateTime? nextRunAt;

  /// The intervals the server accepts, in minutes.
  final List<int> allowedIntervals;

  factory SyncSchedule.fromJson(Map<String, dynamic> json) {
    final next = json['next_run_at'];
    final allowed = json['allowed_intervals'];
    return SyncSchedule(
      intervalMinutes: (json['interval_minutes'] as num?)?.toInt(),
      nextRunAt: next is String ? DateTime.tryParse(next) : null,
      allowedIntervals: allowed is List
          ? allowed.whereType<num>().map((n) => n.toInt()).toList()
          : const [],
    );
  }
}
