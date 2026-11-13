# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Rules (reorder)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-rules-reorder@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:rules) do
    %w[Coffee Groceries].map do |name|
      family.rules.create!(name: name, resource_type: 'transaction',
                           actions: [ Rule::Action.new(action_type: 'exclude_transaction') ])
    end
  end

  path '/api/v1/rules/reorder' do
    patch 'Reorder rules' do
      tags 'Rules'
      description 'Sets the run order of all the family\'s rules, top to bottom, as the web drag and drop does. ' \
                  'rule_ids lists every rule of the family exactly once, and the rules of a group next to each ' \
                  'other (a group moves as one block). A group with no rules stays after the item it follows now.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[rule_ids],
        properties: { rule_ids: { type: :array, items: { type: :string, format: :uuid } } }
      }

      let(:body) { { rule_ids: family.rules.ordered.pluck(:id).reverse } }

      response '200', 'rules reordered' do
        schema type: :object,
               required: %w[rules],
               properties: { rules: { type: :array, items: { '$ref' => '#/components/schemas/Rule' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '422', 'rule_ids are not exactly the family\'s rules, or split a group' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { rule_ids: [ rules.first.id ] } }

        run_test!
      end
    end
  end
end
