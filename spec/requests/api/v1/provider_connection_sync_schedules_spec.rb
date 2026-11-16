# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Provider Connection Sync Schedules', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-sync-schedules@example.com',
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

  let(:mercury_item) { family.mercury_items.create!(name: 'Mercury', token: 'docs-token') }
  let(:id) { mercury_item.id }
  let(:provider) { 'mercury' }

  sync_schedule_response = {
    type: :object,
    required: %w[data],
    properties: {
      data: {
        type: :object,
        required: %w[provider_connection_id provider interval_minutes next_run_at allowed_intervals],
        properties: {
          provider_connection_id: { type: :string, format: :uuid },
          provider: { type: :string, description: 'Provider key, as in GET /api/v1/provider_connections' },
          interval_minutes: { type: :integer, nullable: true, description: 'Null when the connection only takes part in the daily family sync' },
          next_run_at: { type: :string, format: :'date-time', nullable: true },
          allowed_intervals: { type: :array, items: { type: :integer }, description: 'Intervals the server accepts, in minutes' }
        }
      }
    }
  }

  path '/api/v1/provider_connections/{id}/sync_schedule' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Provider connection ID'
    parameter name: :provider, in: :query, type: :string, required: false,
      description: 'Provider key; needed only when two connections share an id'

    get 'Show a connection\'s sync schedule' do
      tags 'Provider Connections'
      description 'How often this connection syncs on its own on top of the daily family sync. Only people who can ' \
                  'manage the connection (admins, or the owning member for per-connection providers) may see it.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'sync schedule shown' do
        schema sync_schedule_response

        run_test!
      end

      response '404', 'connection not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end

    patch 'Set a connection\'s sync schedule' do
      tags 'Provider Connections'
      description 'Sets the interval, or removes the schedule when interval_minutes is null.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[sync_schedule],
        properties: {
          sync_schedule: {
            type: :object,
            required: %w[interval_minutes],
            properties: {
              interval_minutes: { type: :integer, nullable: true, description: 'One of allowed_intervals, or null' }
            }
          }
        }
      }

      let(:body) { { sync_schedule: { interval_minutes: 60 } } }

      response '200', 'sync schedule updated' do
        schema sync_schedule_response

        run_test!
      end

      response '422', 'interval not allowed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { sync_schedule: { interval_minutes: 45 } } }

        run_test!
      end
    end
  end
end
