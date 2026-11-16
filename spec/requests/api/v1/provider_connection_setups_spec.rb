# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::ProviderConnectionSetups", type: :request do
  let(:family) do
    Family.create!(name: "API Family", currency: "USD", locale: "en", date_format: "%m-%d-%Y")
  end
  let(:user) do
    family.users.create!(
      email: "api-connection-setup@example.com",
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
  let(:'X-Api-Key') { api_key.plain_key }
  let(:simplefin_item) do
    family.simplefin_items.create!(name: "SimpleFIN", access_url: "https://user:pass@bridge.example.com/simplefin")
  end
  let!(:simplefin_account) do
    simplefin_item.simplefin_accounts.create!(
      name: "Everyday Checking", account_id: "sf_checking", account_type: "depository",
      currency: "USD", current_balance: 1234.56, org_data: { "name" => "First Bank" }
    )
  end
  let(:id) { simplefin_item.id }
  let(:provider) { "simplefin" }

  pending_account_schema = {
    type: :object,
    required: %w[id name balance balance_cents currency allowed_types],
    properties: {
      id: { type: :string, format: :uuid, description: "Provider account ID; send it back in complete_setup" },
      name: { type: :string },
      institution: { type: :string, nullable: true },
      balance: { type: :string, description: "Formatted balance as the provider reports it" },
      balance_cents: { type: :integer },
      currency: { type: :string },
      suggested_accountable_type: { type: :string, nullable: true, description: "What the web form preselects; null means it preselects Skip" },
      suggested_subtype: { type: :string, nullable: true },
      allowed_types: {
        type: :array,
        description: "The types the web setup form offers for this provider, with their subtypes",
        items: {
          type: :object,
          required: %w[accountable_type label subtypes],
          properties: {
            accountable_type: { type: :string, example: "Depository" },
            label: { type: :string },
            subtypes: {
              type: :array,
              items: {
                type: :object,
                required: %w[value label],
                properties: { value: { type: :string }, label: { type: :string } }
              }
            }
          }
        }
      }
    }
  }

  setup_response_schema = {
    allOf: [
      { "$ref" => "#/components/schemas/ProviderConnection" },
      {
        type: :object,
        required: %w[setup_required awaiting_accounts pending_accounts],
        properties: {
          setup_required: { type: :boolean, description: "Accounts are waiting for setup, or will be once the first sync finds them" },
          awaiting_accounts: { type: :boolean, description: "The first sync hasn't found any accounts yet; poll pending_accounts" },
          pending_accounts: { type: :array, items: pending_account_schema },
          created_account_ids: { type: :array, items: { type: :string, format: :uuid }, description: "Only on complete_setup" }
        }
      }
    ]
  }

  path "/api/v1/provider_connections" do
    post "Creates a token-based provider connection" do
      description "Creates a connection from the credentials the provider's web form takes, as that form does, " \
                  "and queues its first sync. Supported providers and their connection fields: " \
                  "simplefin (setup_token); lunchflow (api_key, base_url, name, sync_start_date); " \
                  "mercury and brex (token, base_url, name, sync_start_date); " \
                  "kraken, binance and coinspot (api_key, api_secret, name, sync_start_date); " \
                  "ibkr (query_id, token, name). Other providers return 422 provider_not_supported. " \
                  "Credentials are never returned. Family admins only."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[provider connection],
        properties: {
          provider: { type: :string, example: "simplefin" },
          connection: {
            type: :object,
            properties: {
              setup_token: { type: :string },
              api_key: { type: :string },
              api_secret: { type: :string },
              token: { type: :string },
              query_id: { type: :string },
              base_url: { type: :string },
              name: { type: :string },
              sync_start_date: { type: :string, format: :date }
            }
          }
        }
      }

      response "201", "connection created" do
        before do
          allow_any_instance_of(Provider::Simplefin).to receive(:claim_access_url)
            .and_return("https://user:pass@bridge.example.com/simplefin")
        end
        let(:body) { { provider: "simplefin", connection: { setup_token: Base64.strict_encode64("https://bridge.example.com/claim/abc") } } }
        schema setup_response_schema
        run_test!
      end

      response "401", "unauthorized" do
        let(:'X-Api-Key') { nil }
        let(:body) { { provider: "kraken", connection: { api_key: "k", api_secret: "s" } } }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "403", "insufficient scope, or not a family admin" do
        let(:'X-Api-Key') do
          ApiKey.create!(user: user, name: "Read", key: ApiKey.generate_secure_key, scopes: %w[read], source: "mobile").plain_key
        end
        let(:body) { { provider: "kraken", connection: { api_key: "k", api_secret: "s" } } }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end

      response "422", "invalid credentials (e.g. invalid_token, token_compromised, blank_token), validation_failed, or provider_not_supported" do
        let(:body) { { provider: "wise", connection: { token: "t" } } }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end

  path "/api/v1/provider_connections/{id}/pending_accounts" do
    parameter name: :id, in: :path, type: :string, required: true, description: "Provider connection ID"
    parameter name: :provider, in: :query, type: :string, required: false,
              description: "The connection's provider key from the list. Needed only when two connections share an id."

    get "Lists a connection's accounts waiting for setup" do
      description "The accounts the web's account setup page lists: the provider's accounts not yet linked to a Sure account. " \
                  "For Lunch Flow, Mercury and Brex this fetches the account list from the provider when none is stored yet, " \
                  "as that page does. Family admins only."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "pending accounts" do
        schema type: :object,
               required: %w[data awaiting_accounts],
               properties: {
                 data: { type: :array, items: pending_account_schema },
                 awaiting_accounts: { type: :boolean }
               }
        run_test!
      end

      response "404", "connection not found" do
        let(:id) { SecureRandom.uuid }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end

  path "/api/v1/provider_connections/{id}/complete_setup" do
    parameter name: :id, in: :path, type: :string, required: true, description: "Provider connection ID"
    parameter name: :provider, in: :query, type: :string, required: false,
              description: "The connection's provider key from the list. Needed only when two connections share an id."

    post "Creates Sure accounts for a connection's pending accounts" do
      description "Runs the web's complete_account_setup: each account with import true becomes a Sure account of the " \
                  "chosen type and subtype, and a sync is queued. import false skips it; accounts left out stay pending. " \
                  "accountable_type and subtype must come from that account's allowed_types; providers with one fixed " \
                  "type (Kraken, Binance, CoinSpot, IBKR) need neither. sync_start_date is accepted for SimpleFIN and " \
                  "Binance, whose web setup step sets it. The whole request is checked first, so a 422 changes nothing. " \
                  "Family admins only."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[accounts],
        properties: {
          sync_start_date: { type: :string, format: :date },
          accounts: {
            type: :array,
            items: {
              type: :object,
              required: %w[id],
              properties: {
                id: { type: :string, format: :uuid },
                import: { type: :boolean, default: true },
                accountable_type: { type: :string, example: "Depository" },
                subtype: { type: :string, nullable: true, example: "checking" }
              }
            }
          }
        }
      }

      response "200", "accounts created and a sync queued" do
        let(:body) { { accounts: [ { id: simplefin_account.id, import: true, accountable_type: "Depository", subtype: "checking" } ] } }
        schema setup_response_schema
        run_test!
      end

      response "422", "invalid_account_type, invalid_subtype, unknown_account, link_not_supported, invalid_sync_start_date or validation_failed" do
        let(:body) { { accounts: [ { id: simplefin_account.id, import: true, accountable_type: "Property" } ] } }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end
end
