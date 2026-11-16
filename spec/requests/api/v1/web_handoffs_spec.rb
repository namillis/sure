# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Web Handoffs', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'web-handoffs@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      role: 'admin'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  path '/api/v1/web_handoffs' do
    post 'Create a web handoff' do
      tags 'Web Handoffs'
      description 'Returns a one-time URL, valid for 60 seconds, that opens a provider connect or reconnect page in a ' \
                  'web session for the API user, without another sign-in. The session can only reach the providers ' \
                  'page and the provider connection pages, lasts at most 30 minutes, and ends by sending the browser ' \
                  'to sureplus://connections/done?status=ok|cancelled|error. Needs read_write. Limited to 10 per user ' \
                  'per minute. Allowed paths: /settings/providers, /settings/providers/{provider}/connect_form, and ' \
                  'the GET new, edit, setup_accounts, select_accounts, select_existing_account, select_profiles, ' \
                  'select_bank, new_wallet and connect pages of the *_items provider routes.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[web_handoff],
        properties: {
          web_handoff: {
            type: :object,
            required: %w[path],
            properties: {
              path: { type: :string, example: '/plaid_items/new?region=us', description: 'A relative path on this server' }
            }
          }
        }
      }

      response '201', 'handoff created' do
        schema type: :object,
               required: %w[url expires_at],
               properties: {
                 url: { type: :string, description: 'Open once, in the app\'s auth sheet' },
                 expires_at: { type: :string, format: :'date-time' }
               }

        let(:body) { { web_handoff: { path: '/settings/providers' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }
        let(:body) { { web_handoff: { path: '/settings/providers' } } }

        run_test!
      end

      response '403', 'read-only credential or guest' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') do
          ApiKey.create!(user: user, name: 'Read Key', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'web').plain_key
        end
        let(:body) { { web_handoff: { path: '/settings/providers' } } }

        run_test!
      end

      response '422', 'path not allowed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { web_handoff: { path: '/settings/security' } } }

        run_test!
      end
    end
  end
end
