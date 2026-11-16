# frozen_string_literal: true

json.data do
  json.provider_connection_id @syncable.id
  json.provider @connection.key
  json.interval_minutes @sync_schedule&.interval_minutes
  json.next_run_at @sync_schedule&.next_run_at&.iso8601
  json.allowed_intervals SyncSchedule::INTERVALS
end
