# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::ProviderConnectionManagement", type: :request do
  let(:family) do
    Family.create!(name: "API Family", currency: "USD", locale: "en", date_format: "%m-%d-%Y")
  end
  let(:user) do
    family.users.create!(
      email: "api-connections@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: "admin"
    )
  end
  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: "API Docs Key",
      key: key,
      scopes: %w[read_write],
      source: "web"
    )
  end
  let(:read_only_api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: "API Docs Read Key",
      key: key,
      scopes: %w[read],
      source: "mobile"
    )
  end
  let(:'X-Api-Key') { api_key.plain_key }
  let(:plaid_item) do
    family.plaid_items.create!(name: "Test Bank", plaid_id: "item_api_docs", access_token: "token_api_docs")
  end
  let(:id) { plaid_item.id }
  let(:provider) { "plaid" }

  before do
    allow_any_instance_of(PlaidItem).to receive(:request_transactions_refresh_later)
  end

  path "/api/v1/provider_connections/{id}/sync" do
    parameter name: :id, in: :path, type: :string, required: true, description: "Provider connection ID"
    parameter name: :provider, in: :query, type: :string, required: false,
              description: "The connection's provider key from the list (e.g. plaid). Needed only when two connections share an id."

    post "Queues a sync of one provider connection" do
      description "Queues a sync of one bank or broker connection, as the web's sync button does. " \
                  "A connection that is already syncing is not queued again. Plaid connections may be managed by their owner; " \
                  "every other provider requires a family admin."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "202", "sync queued" do
        schema "$ref" => "#/components/schemas/ProviderConnection"
        run_test!
      end

      response "401", "unauthorized" do
        let(:'X-Api-Key') { nil }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "403", "insufficient scope or not allowed to manage this connection" do
        let(:'X-Api-Key') { read_only_api_key.plain_key }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "404", "connection not found" do
        let(:id) { SecureRandom.uuid }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "422", "the provider cannot be synced from the API (e.g. FinanceKit, or a connection that needs a new login)" do
        let(:trade_republic_item) do
          family.trade_republic_items.create!(name: "Trade Republic", currency: "EUR", phone_number: "+491701234567")
        end
        let(:id) { trade_republic_item.id }
        let(:provider) { "trade_republic" }

        before { allow_any_instance_of(TradeRepublicItem).to receive(:ready_for_sync?).and_return(false) }

        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end

  path "/api/v1/provider_connections/{id}" do
    parameter name: :id, in: :path, type: :string, required: true, description: "Provider connection ID"
    parameter name: :provider, in: :query, type: :string, required: false,
              description: "The connection's provider key from the list (e.g. plaid). Needed only when two connections share an id."

    delete "Disconnects a provider connection" do
      description "Disconnects a bank or broker connection as the web does: unlinks its accounts where that provider's web flow does, " \
                  "then schedules the connection's deletion in the background, which also removes it on the provider's side. " \
                  "Accounts and their history stay. FinanceKit connections are disconnected through /api/v1/financekit/connections/{id}."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "202", "disconnect scheduled" do
        schema "$ref" => "#/components/schemas/ProviderConnection"
        run_test!
      end

      response "401", "unauthorized" do
        let(:'X-Api-Key') { nil }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "403", "insufficient scope or not allowed to manage this connection" do
        let(:'X-Api-Key') { read_only_api_key.plain_key }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "404", "connection not found" do
        let(:id) { SecureRandom.uuid }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "422", "accounts could not be unlinked, so the connection was kept" do
        let(:trade_republic_item) do
          family.trade_republic_items.create!(name: "Trade Republic", currency: "EUR", phone_number: "+491701234567")
        end
        let(:id) { trade_republic_item.id }
        let(:provider) { "trade_republic" }

        before do
          allow_any_instance_of(TradeRepublicItem).to receive(:unlink_all!).and_return([ { provider_account_id: "x", error: "failed" } ])
        end

        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end
end
