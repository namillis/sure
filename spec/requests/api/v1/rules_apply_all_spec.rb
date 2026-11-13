# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Rules (apply all)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-rules-apply-all@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:rule) do
    family.rules.create!(name: 'Coffee', resource_type: 'transaction',
                         actions: [ Rule::Action.new(action_type: 'exclude_transaction') ])
  end

  path '/api/v1/rules/apply_all' do
    post 'Apply all rules to existing transactions' do
      tags 'Rules'
      description 'Runs every rule of the family, active or not, top to bottom, as the web "Apply all" does. ' \
                  'Without confirm: true it changes nothing and returns what the web confirmation shows. ' \
                  'With it, the run is queued (202); each rule\'s run then appears in GET /api/v1/rule_runs.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { confirm: { type: :boolean } }
      }

      let(:body) { { confirm: true } }

      response '202', 'rules queued' do
        schema type: :object,
               required: %w[data],
               properties: {
                 data: {
                   type: :object,
                   required: %w[status rule_count],
                   properties: {
                     status: { type: :string, enum: %w[queued] },
                     rule_count: { type: :integer }
                   }
                 }
               }

        run_test!
      end

      response '422', 'confirmation required' do
        schema type: :object,
               required: %w[error confirmation],
               properties: {
                 error: { type: :string, enum: %w[confirmation_required] },
                 message: { type: :string },
                 errors: { type: :array, items: { type: :string } },
                 confirmation: {
                   type: :object,
                   required: %w[rule_count affected_resource_count auto_categorize],
                   properties: {
                     rule_count: { type: :integer },
                     affected_resource_count: { type: :integer, description: 'Unique transactions any rule matches' },
                     auto_categorize: { type: :boolean },
                     ai_model: { type: :string, nullable: true },
                     estimated_ai_cost: { type: :number, nullable: true }
                   }
                 }
               }

        let(:body) { {} }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end
    end
  end
end
