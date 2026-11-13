# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Budget writes', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      display_key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:read_only_api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'Read Only Docs Key',
      key: key,
      display_key: key,
      scopes: %w[read],
      source: 'mobile'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }
  let!(:budget) do
    family.budgets.create!(
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      budgeted_spending: 3000,
      expected_income: 5000,
      currency: 'USD'
    )
  end

  path '/api/v1/budgets/{id}' do
    parameter name: :id, in: :path, required: true, description: 'Budget ID',
              schema: { type: :string, format: :uuid }

    patch 'Update a budget' do
      tags 'Budgets'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description 'Sets the monthly spending budget and expected income. Omitted fields are left unchanged. ' \
                  'A personal budget shared read-only returns 403.'

      let(:id) { budget.id }

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          budget: {
            type: :object,
            properties: {
              budgeted_spending: { type: :number, minimum: 0, description: 'Total monthly spending budget' },
              expected_income: { type: :number, minimum: 0, description: 'Expected monthly income' }
            }
          }
        }
      }
      let(:body) { { budget: { budgeted_spending: 3500, expected_income: 6000 } } }

      response '200', 'budget updated' do
        schema '$ref' => '#/components/schemas/Budget'

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['budgeted_spending_cents']).to eq(350_000)
          expect(data['expected_income_cents']).to eq(600_000)
        end
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '403', 'forbidden - requires read_write scope' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }

        run_test!
      end

      response '404', 'budget not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { budget: { budgeted_spending: -1 } } }

        run_test!
      end
    end
  end
end
