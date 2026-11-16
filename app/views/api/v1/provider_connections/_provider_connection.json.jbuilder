# frozen_string_literal: true

json.extract! provider_connection,
              :id,
              :provider,
              :provider_type,
              :name,
              :status,
              :requires_update,
              :credentials_configured,
              :scheduled_for_deletion,
              :pending_account_setup,
              :institution,
              :accounts,
              :sync,
              :created_at,
              :updated_at

json.partial! "api/v1/provider_connections/provider_connection_sure_plus_reconnect", provider_connection: provider_connection
