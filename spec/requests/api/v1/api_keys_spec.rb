# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 API Keys', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-keys@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:other_key) do
    ApiKey.create!(user: user, name: 'Shortcuts', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'web')
  end

  api_key_schema = {
    type: :object,
    required: %w[id name scopes display_key current created_at last_used_at expires_at],
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      scopes: { type: :array, items: { type: :string, enum: %w[read read_write] } },
      display_key: { type: :string, description: 'Masked key: asterisks and the last four characters' },
      current: { type: :boolean, description: 'Whether this key authenticated the request' },
      created_at: { type: :string, format: :'date-time' },
      last_used_at: { type: :string, format: :'date-time', nullable: true },
      expires_at: { type: :string, format: :'date-time', nullable: true }
    }
  }

  path '/api/v1/api_keys' do
    get 'List API keys' do
      tags 'API Keys'
      description 'The signed-in user\'s active API keys, newest first. Keys are masked; the full key is only in the create response.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'API keys listed' do
        schema type: :object, required: %w[data], properties: { data: { type: :array, items: api_key_schema } }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end
    end

    post 'Create an API key' do
      tags 'API Keys'
      description 'Creates a key for the signed-in user and returns it in full once, in plain_key. Needs read_write. ' \
                  'Limited to 10 keys per user per hour.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[api_key],
        properties: {
          api_key: {
            type: :object,
            required: %w[name scopes],
            properties: {
              name: { type: :string, description: 'Unique among the user\'s active keys' },
              scopes: { type: :array, items: { type: :string, enum: %w[read read_write] }, description: 'Exactly one scope' }
            }
          }
        }
      }

      let(:body) { { api_key: { name: 'Widget', scopes: %w[read] } } }

      response '201', 'API key created' do
        schema type: :object, required: %w[data], properties: {
          data: api_key_schema.merge(
            required: api_key_schema[:required] + %w[plain_key],
            properties: api_key_schema[:properties].merge(plain_key: { type: :string, description: 'The full key, shown only here' })
          )
        }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { api_key: { name: 'Shortcuts', scopes: %w[admin] } } }

        run_test!
      end
    end
  end

  path '/api/v1/api_keys/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'API key ID'

    delete 'Revoke an API key' do
      tags 'API Keys'
      description 'Revokes one of the user\'s keys. The key authenticating the request cannot be revoked (422 cannot_revoke_current_key).'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      let(:id) { other_key.id }

      response '204', 'API key revoked' do
        run_test!
      end

      response '404', 'API key not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'cannot revoke the current key' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { api_key.id }

        run_test!
      end
    end
  end
end
