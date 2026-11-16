# frozen_string_literal: true

json.partial! "api/v1/provider_connections/provider_connection", provider_connection: @provider_connection
json.setup_required @setup.setup_required?
json.awaiting_accounts @setup.awaiting_accounts?
json.pending_accounts @setup.pending_accounts
json.created_account_ids @created_accounts.map(&:id) if @created_accounts
