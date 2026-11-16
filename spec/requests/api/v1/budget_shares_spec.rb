# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Budget Sharing (Sure+)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y', personal_budgets: true)
  end

  let(:user) do
    family.users.create!(
      email: 'api-owner@example.com', first_name: 'Olive', last_name: 'Owner', role: 'admin',
      password: 'password123', password_confirmation: 'password123'
    )
  end

  let!(:other_member) do
    family.users.create!(
      email: 'api-member@example.com', first_name: 'Max', last_name: 'Member', role: 'member',
      password: 'password123', password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  shares_schema = {
    type: :object,
    required: %w[personal_budgets permissions members],
    properties: {
      personal_budgets: {
        type: :boolean,
        description: 'Whether the family uses personal budgets; the web only shows budget sharing when it does.'
      },
      permissions: { type: :array, items: { type: :string } },
      members: {
        type: :array,
        items: {
          type: :object,
          required: %w[user_id name permission],
          properties: {
            user_id: { type: :string, format: :uuid },
            name: { type: :string },
            permission: { type: :string, enum: %w[none read_only read_write] }
          }
        }
      }
    }
  }

  path '/api/v1/budget_shares' do
    get "Show who can see the caller's personal budget" do
      description 'Sure+ `budgets.sharing`. The budget sharing section of Settings > Preferences: every other ' \
                  'active family member and the access the caller grants them (`none` means not shared).'
      tags 'Budget Sharing (Sure+)'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'shares shown' do
        schema shares_schema
        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') { nil }
        run_test!
      end
    end

    patch "Change who can see the caller's personal budget" do
      description 'Sure+ `budgets.sharing`. Same as the web form: one permission per member, `none` revokes. ' \
                  'Members not listed are left alone. Unknown permissions or users are 422.'
      tags 'Budget Sharing (Sure+)'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[budget_shares],
        properties: {
          budget_shares: {
            type: :object,
            required: %w[members],
            properties: {
              members: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[user_id permission],
                  properties: {
                    user_id: { type: :string, format: :uuid },
                    permission: { type: :string, enum: %w[none read_only read_write] }
                  }
                }
              }
            }
          }
        }
      }

      response '200', 'shares updated' do
        schema shares_schema
        let(:body) { { budget_shares: { members: [ { user_id: other_member.id, permission: 'read_only' } ] } } }
        run_test!
      end

      response '422', 'invalid permission or member' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:body) { { budget_shares: { members: [ { user_id: other_member.id, permission: 'full_control' } ] } } }
        run_test!
      end
    end
  end
end
