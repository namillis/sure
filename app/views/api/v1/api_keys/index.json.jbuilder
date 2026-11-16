# frozen_string_literal: true

json.data @api_keys do |api_key|
  json.partial! "api/v1/api_keys/api_key", api_key: api_key, current_api_key_id: @api_key&.id
end
