# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Budget Category writes', type: :request do
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
  let!(:category) { family.categories.create!(name: 'Groceries', color: '#22c55e') }
  let!(:budget) do
    family.budgets.create!(
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      budgeted_spending: 3000,
      expected_income: 5000,
      currency: 'USD'
    )
  end
  let!(:budget_category) do
    budget.budget_categories.create!(
      category: category,
      budgeted_spending: 500,
      currency: 'USD'
    )
  end

  path '/api/v1/budget_categories/{id}' do
    parameter name: :id, in: :path, required: true, description: 'Budget category ID',
              schema: { type: :string, format: :uuid }

    patch 'Update a budget category' do
      tags 'Budget Categories'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description 'Sets a category allocation and/or its rollover toggle. Omitted fields are left unchanged; ' \
                  'an empty or null budgeted_spending clears the allocation to 0. A subcategory change also ' \
                  'updates its parent total, a rollover change applies to later months, and the rollover ' \
                  'carry is recomputed. A personal budget shared read-only returns 403.'

      let(:id) { budget_category.id }

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          budget_category: {
            type: :object,
            properties: {
              budgeted_spending: { type: :number, minimum: 0, nullable: true, description: 'Monthly allocation for the category' },
              rollover_enabled: { type: :boolean, description: 'Carry unspent allocation into the next month' }
            }
          }
        }
      }
      let(:body) { { budget_category: { budgeted_spending: 650, rollover_enabled: true } } }

      response '200', 'budget category updated' do
        schema '$ref' => '#/components/schemas/BudgetCategory'

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['budgeted_spending_cents']).to eq(65_000)
          expect(data['rollover_enabled']).to be(true)
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

      response '404', 'budget category not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { budget_category: { rollover_enabled: 'maybe' } } }

        run_test!
      end
    end
  end
end
