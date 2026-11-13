# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Budget allocations', type: :request do
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

  let(:groceries) { family.categories.create!(name: 'Groceries', color: '#4da568') }
  let(:dining) { family.categories.create!(name: 'Dining', color: '#e99537') }

  let!(:budget) do
    family.budgets.create!(
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      budgeted_spending: 3000,
      expected_income: 5000,
      currency: 'USD'
    )
  end

  let!(:groceries_budget_category) { budget.budget_categories.create!(category: groceries, budgeted_spending: 400, currency: 'USD') }
  let!(:dining_budget_category) { budget.budget_categories.create!(category: dining, budgeted_spending: 100, currency: 'USD') }

  owner_parameter = {
    name: :owner, in: :query, required: false,
    description: 'Whose budget: omit for your own (the household budget when personal budgets are off), ' \
                 '"household", or the user id of a member who shared their budget with you',
    schema: { type: :string }
  }

  path '/api/v1/budgets' do
    post 'Open a budget month' do
      tags 'Budgets'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description 'Creates the budget row for a month the way opening it on the web does, with a row for every ' \
                  'category. Returns 201 when it was created and 200 when it already existed. Another member\'s ' \
                  'month is only returned if it already exists; it is never created on their behalf.'
      parameter owner_parameter

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[budget],
        properties: {
          budget: {
            type: :object,
            required: %w[month],
            properties: {
              month: { type: :string, example: '2026-12', description: 'Month as YYYY-MM' }
            }
          }
        }
      }
      let(:body) { { budget: { month: 2.months.from_now.strftime('%Y-%m') } } }

      response '201', 'budget month created' do
        schema '$ref' => '#/components/schemas/Budget'

        run_test!
      end

      response '200', 'budget month already existed' do
        schema '$ref' => '#/components/schemas/Budget'

        let(:body) { { budget: { month: budget.start_date.strftime('%Y-%m') } } }

        run_test!
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

      response '422', 'malformed month, or outside the range budgets can be set up for' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { budget: { month: 'december' } } }

        run_test!
      end
    end
  end

  path '/api/v1/budgets/{month_year}/copy_previous' do
    parameter name: :month_year, in: :path, required: true,
              description: 'Month in the web\'s budget URL format, e.g. nov-2026 (case-insensitive)',
              schema: { type: :string }

    post 'Copy the previous month into a budget' do
      tags 'Budgets'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description 'Copies spending budget, expected income, category allocations and rollover choices from the ' \
                  'most recent earlier month that was set up, creating the month first if needed.'
      parameter owner_parameter

      let(:month_year) { Budget.date_to_param(1.month.from_now.to_date) }

      response '201', 'budget copied' do
        schema '$ref' => '#/components/schemas/Budget'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '403', 'forbidden - requires read_write scope, or the budget is shared read-only' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }

        run_test!
      end

      response '404', 'malformed month or budget not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:month_year) { '2026-11' }

        run_test!
      end

      response '409', 'already_set_up: the month already has amounts set' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:month_year) { Budget.date_to_param(budget.start_date) }

        run_test!
      end

      response '422', 'no_source: no earlier month has been set up' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:month_year) { Budget.date_to_param(3.months.ago.to_date) }

        run_test!
      end
    end
  end

  path '/api/v1/budgets/{budget_id}/budget_categories/move' do
    parameter name: :budget_id, in: :path, required: true, description: 'Budget ID',
              schema: { type: :string, format: :uuid }

    post 'Move allocation between budget categories' do
      tags 'Budget Categories'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description 'Moves part of one category\'s allocation to another in the same budget, as the web\'s move ' \
                  'does. Returns both updated rows and the budget. 422 carries a `reason`: non_positive_amount, ' \
                  'insufficient_funds, different_budgets, same_category, parent_child or uncategorized.'

      let(:budget_id) { budget.id }

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[move],
        properties: {
          move: {
            type: :object,
            required: %w[from_id to_id amount],
            properties: {
              from_id: { type: :string, format: :uuid, description: 'Budget category to take from' },
              to_id: { type: :string, format: :uuid, description: 'Budget category to give to' },
              amount: { type: :number, exclusiveMinimum: 0, example: 50 }
            }
          }
        }
      }
      let(:body) { { move: { from_id: groceries_budget_category.id, to_id: dining_budget_category.id, amount: '50' } } }

      response '200', 'allocation moved' do
        schema type: :object,
               required: %w[from to budget],
               properties: {
                 from: { '$ref' => '#/components/schemas/BudgetCategory' },
                 to: { '$ref' => '#/components/schemas/BudgetCategory' },
                 budget: { '$ref' => '#/components/schemas/Budget' }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '403', 'forbidden - requires read_write scope, or the budget is shared read-only' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }

        run_test!
      end

      response '404', 'budget or budget category not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:budget_id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'invalid move' do
        schema type: :object,
               required: %w[error message reason],
               properties: {
                 error: { type: :string, example: 'validation_failed' },
                 message: { type: :string },
                 errors: { type: :array, items: { type: :string } },
                 reason: { type: :string, example: 'insufficient_funds' }
               }

        let(:body) { { move: { from_id: dining_budget_category.id, to_id: groceries_budget_category.id, amount: 500 } } }

        run_test!
      end
    end
  end
end
