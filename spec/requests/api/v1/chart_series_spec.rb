# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Chart Series', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(email: 'api-user@example.com', password: 'password123', password_confirmation: 'password123')
  end

  let(:api_key) do
    ApiKey.create!(user: user, name: 'API Docs Key', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let(:account) do
    family.accounts.create!(name: 'Checking', balance: 1000, currency: 'USD', accountable: Depository.new, owner: user)
  end

  period_description = "Period key (#{Period::PERIODS.keys.join(', ')}). Defaults to last_30_days. " \
                       'Ignored when start_date and end_date are given.'

  path '/api/v1/net_worth_series' do
    get 'Net worth chart series' do
      tags 'Charts'
      description 'The family net worth series the web dashboard draws, from the same cached query. Supports ' \
                  'If-None-Match: a matching ETag returns 304 with no body. Requires the read scope.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      parameter name: :period, in: :query, required: false, schema: { type: :string }, description: period_description
      parameter name: :start_date, in: :query, required: false, schema: { type: :string, format: :date }
      parameter name: :end_date, in: :query, required: false, schema: { type: :string, format: :date }

      response '200', 'series returned' do
        schema '$ref' => '#/components/schemas/ChartSeries'

        let(:period) { 'last_365_days' }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end

      response '422', 'invalid period or dates' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:period) { 'forever' }

        run_test!
      end
    end
  end

  path '/api/v1/accounts/{id}/balance_series' do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }

    get 'Account balance chart series' do
      tags 'Charts'
      description 'One account\'s balance series, as on the web account page (linked investment series ' \
                  'normalized). Disabled accounts are included. Supports If-None-Match. Requires the read scope.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      parameter name: :period, in: :query, required: false, schema: { type: :string }, description: period_description
      parameter name: :start_date, in: :query, required: false, schema: { type: :string, format: :date }
      parameter name: :end_date, in: :query, required: false, schema: { type: :string, format: :date }
      parameter name: :view, in: :query, required: false,
                schema: { type: :string, enum: %w[balance cash_balance holdings_balance] }

      let(:id) { account.id }

      response '200', 'series returned' do
        schema '$ref' => '#/components/schemas/ChartSeries'

        run_test!
      end

      response '404', 'account not found or not accessible' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'invalid view, period or dates' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:view) { 'gains' }

        run_test!
      end
    end
  end
end
