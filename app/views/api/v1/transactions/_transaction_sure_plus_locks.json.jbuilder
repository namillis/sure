# frozen_string_literal: true

entry = transaction.entry

# The web's "Protected from sync" panel and its unlock button. An excluded
# entry is protected too, but the web shows no panel for it and unlock would
# not include it again.
json.sync_locked(entry.protected_from_sync? && !entry.excluded?)
json.locked_attributes entry.locked_fields_with_timestamps do |field, locked_at|
  json.field field
  json.locked_at(locked_at.respond_to?(:iso8601) ? locked_at.iso8601 : locked_at)
end

json.reconciled_status entry.reconciled_status
json.reconcilable api_reconcilable_account_ids.include?(entry.account_id)
