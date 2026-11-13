# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Rule Groups', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-rule-groups@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:rule_group) { family.rule_groups.create!(name: 'Food') }

  rule_group_schema = {
    type: :object,
    required: %w[id name position rules_count created_at updated_at],
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      position: { type: :integer, description: 'Place among the top-level items of the rules list; its rules follow it' },
      rules_count: { type: :integer },
      created_at: { type: :string, format: :'date-time' },
      updated_at: { type: :string, format: :'date-time' }
    }
  }

  rule_group_response = { type: :object, required: %w[data], properties: { data: rule_group_schema } }

  rule_group_input = {
    type: :object,
    required: %w[rule_group],
    properties: {
      rule_group: {
        type: :object,
        required: %w[name],
        properties: { name: { type: :string, description: 'Unique within the family, at most 100 characters' } }
      }
    }
  }

  path '/api/v1/rule_groups' do
    get 'List rule groups' do
      tags 'Rule Groups'
      description 'The family\'s rule groups in the order the rules page shows them.'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'rule groups listed' do
        schema type: :object, required: %w[data], properties: { data: { type: :array, items: rule_group_schema } }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end
    end

    post 'Create a rule group' do
      tags 'Rule Groups'
      description 'Adds an empty group at the end of the rules list. Guests cannot create groups.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: rule_group_input

      let(:body) { { rule_group: { name: 'Bills' } } }

      response '201', 'rule group created' do
        schema rule_group_response

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { rule_group: { name: 'Food' } } }

        run_test!
      end
    end
  end

  path '/api/v1/rule_groups/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Rule group ID'

    let(:id) { rule_group.id }

    patch 'Rename a rule group' do
      tags 'Rule Groups'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: rule_group_input

      let(:body) { { rule_group: { name: 'Eating out' } } }

      response '200', 'rule group updated' do
        schema rule_group_response

        run_test!
      end

      response '404', 'rule group not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { rule_group: { name: '' } } }

        run_test!
      end
    end

    delete 'Delete a rule group' do
      tags 'Rule Groups'
      description 'Deletes the group. Its rules are kept, in the same place in the run order, without a group.'
      security [ { apiKeyAuth: [] } ]

      response '204', 'rule group deleted' do
        run_test!
      end

      response '404', 'rule group not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end
end
