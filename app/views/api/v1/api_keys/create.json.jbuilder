# frozen_string_literal: true

json.data do
  json.partial! "api/v1/api_keys/api_key", api_key: @managed_api_key, current_api_key_id: @api_key&.id
  json.plain_key @plain_key
end
