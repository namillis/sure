# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::AvailableProviderConnections", type: :request do
  let(:family) do
    Family.create!(name: "API Family", currency: "USD", locale: "en", date_format: "%m-%d-%Y")
  end
  let(:user) do
    family.users.create!(email: "available-connections@example.com", password: "password123",
      password_confirmation: "password123", role: "admin")
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

  path "/api/v1/provider_connections/available" do
    get "Lists the connections the user may add" do
      description "The providers this server lets the user connect, as /settings/providers and the Plaid link page " \
                  "offer them: every provider panel for admins, plus Plaid when the instance has Plaid credentials " \
                  "(members get Plaid only, guests nothing). connect_path is a web handoff path. kind is token when " \
                  "the app can create the connection natively from a token or API key, otherwise web."
      tags "Provider Connections"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "available connections listed" do
        schema type: :object,
               required: %w[data],
               properties: {
                 data: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[provider key name connect_path kind],
                     properties: {
                       provider: { type: :string, description: "Matches provider on GET /api/v1/provider_connections" },
                       key: { type: :string, description: "Unique per entry, e.g. plaid_us and plaid_eu" },
                       name: { type: :string },
                       connect_path: { type: :string, example: "/settings/providers/simplefin/connect_form" },
                       kind: { type: :string, enum: %w[web token] }
                     }
                   }
                 }
               }
        run_test!
      end

      response "401", "unauthorized" do
        let(:'X-Api-Key') { nil }
        schema "$ref" => "#/components/schemas/ErrorResponse"
        run_test!
      end
    end
  end
end
