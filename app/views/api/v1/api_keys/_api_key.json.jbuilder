# frozen_string_literal: true

json.id api_key.id
json.name api_key.name
json.scopes api_key.scopes
json.display_key "#{"*" * 8}#{api_key.plain_key.to_s.last(4)}"
json.current api_key.id == current_api_key_id
json.created_at api_key.created_at.iso8601
json.last_used_at api_key.last_used_at&.iso8601
json.expires_at api_key.expires_at&.iso8601
