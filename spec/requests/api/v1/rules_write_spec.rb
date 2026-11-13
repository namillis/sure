# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Rules (write)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-rules-writer@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Write Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:read_only_api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Read Key', key: key, scopes: %w[read], source: 'mobile')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:rule) do
    family.rules.build(name: 'Coffee cleanup', resource_type: 'transaction', active: false).tap do |rule|
      rule.conditions.build(condition_type: 'transaction_name', operator: 'like', value: 'coffee')
      rule.actions.build(action_type: 'set_transaction_name', value: 'Coffee')
      rule.save!
    end
  end

  condition_input = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid, description: 'Saved condition to update; omit to add one' },
      condition_type: { type: :string, example: 'transaction_name' },
      operator: { type: :string, example: 'like' },
      value: { type: :string, nullable: true },
      _destroy: { type: :boolean }
    }
  }

  rule_input = {
    type: :object,
    required: %w[rule],
    properties: {
      rule: {
        type: :object,
        description: 'Same shape GET /api/v1/rules/{id} returns. A conditions or actions list that is sent ' \
                     'replaces the saved one (saved entries left out are removed); an omitted list is kept.',
        properties: {
          name: { type: :string, nullable: true },
          resource_type: { type: :string, enum: %w[transaction], description: 'Defaults to transaction on create' },
          active: { type: :boolean },
          effective_date: { type: :string, format: :date, nullable: true },
          stop_processing: { type: :boolean },
          rule_group_id: { type: :string, format: :uuid, nullable: true },
          new_rule_group_name: { type: :string, description: 'Puts the rule in this group, created if the family has none by that name' },
          conditions: {
            type: :array,
            items: condition_input.deep_merge(
              properties: {
                sub_conditions: { type: :array, items: condition_input, description: 'For a compound condition' }
              }
            )
          },
          actions: {
            type: :array,
            items: {
              type: :object,
              properties: {
                id: { type: :string, format: :uuid },
                action_type: { type: :string, example: 'set_transaction_category' },
                value: {
                  oneOf: [ { type: :string }, { type: :array, items: { type: :string } } ],
                  nullable: true
                },
                _destroy: { type: :boolean }
              }
            }
          }
        }
      }
    }
  }

  saved_rule_response = {
    type: :object,
    required: %w[data warnings],
    properties: {
      data: { '$ref' => '#/components/schemas/Rule' },
      warnings: { type: :array, items: { type: :string } }
    }
  }

  path '/api/v1/rules' do
    post 'Create a rule' do
      tags 'Rules'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: rule_input

      let(:body) do
        {
          rule: {
            name: 'Groceries',
            conditions: [
              { condition_type: 'transaction_name', operator: 'like', value: 'market' },
              {
                condition_type: 'compound',
                operator: 'or',
                sub_conditions: [
                  { condition_type: 'transaction_amount', operator: '>', value: '20' },
                  { condition_type: 'transaction_amount', operator: '<', value: '5' }
                ]
              }
            ],
            actions: [ { action_type: 'set_transaction_name', value: 'Groceries' } ]
          }
        }
      end

      response '201', 'rule created' do
        schema saved_rule_response

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

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { rule: { name: 'No actions', actions: [] } } }

        run_test!
      end
    end
  end

  path '/api/v1/rules/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Rule ID'

    let(:id) { rule.id }

    patch 'Update a rule' do
      tags 'Rules'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: rule_input

      let(:body) do
        {
          rule: {
            name: 'Latte cleanup',
            conditions: [
              { id: rule.conditions.first.id, condition_type: 'transaction_name', operator: 'like', value: 'latte' }
            ]
          }
        }
      end

      response '200', 'rule updated' do
        schema saved_rule_response

        run_test!
      end

      response '404', 'rule not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { rule: { actions: [] } } }

        run_test!
      end
    end

    delete 'Delete a rule' do
      tags 'Rules'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '204', 'rule deleted' do
        run_test!
      end

      response '404', 'rule not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end

  path '/api/v1/rules/{id}/apply' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Rule ID'

    let(:id) { rule.id }

    post 'Apply a rule to existing transactions' do
      tags 'Rules'
      description 'Switches the rule on and runs it now on the transactions it matches (the active rules above it ' \
                  'run first, as in the web "Apply"). Without confirm: true it changes nothing and returns ' \
                  'the details the web confirmation shows, including the AI cost estimate for auto-categorize.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { confirm: { type: :boolean } }
      }

      let(:body) { { confirm: true } }

      response '201', 'rule applied' do
        schema '$ref' => '#/components/schemas/RuleRunResponse'

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
                   required: %w[affected_resource_count resource_type active_rules_above_count auto_categorize],
                   properties: {
                     affected_resource_count: { type: :integer },
                     resource_type: { type: :string },
                     active_rules_above_count: { type: :integer },
                     auto_categorize: { type: :boolean },
                     ai_model: { type: :string, nullable: true },
                     estimated_ai_cost: { type: :number, nullable: true }
                   }
                 }
               }

        let(:body) { {} }

        run_test!
      end

      response '409', 'rules already running for the family' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        before { allow_any_instance_of(Rule::Runner).to receive(:run).and_raise(Rule::Runner::LockBusy) }

        run_test!
      end

      response '404', 'rule not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end
end
