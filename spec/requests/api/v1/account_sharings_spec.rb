# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Account Sharing (Sure+)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
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

  let(:account) do
    Account.create!(
      family: family, owner: user, name: 'Joint Checking', balance: 100, currency: 'USD',
      accountable: Depository.new
    )
  end

  let(:id) { account.id }

  sharing_schema = {
    type: :object,
    required: %w[account_id is_owner owner permission include_in_finances permissions members],
    properties: {
      account_id: { type: :string, format: :uuid },
      is_owner: { type: :boolean },
      owner: {
        type: :object, nullable: true,
        properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
      },
      permission: {
        type: :string, nullable: true, enum: [ 'full_control', 'read_write', 'read_only', nil ],
        description: "The caller's own share permission; null for the owner."
      },
      include_in_finances: {
        type: :boolean, nullable: true,
        description: "Whether the account counts in the caller's finances; null for the owner."
      },
      permissions: { type: :array, items: { type: :string } },
      members: {
        type: :array,
        description: 'Owner only; empty for anyone else.',
        items: {
          type: :object,
          required: %w[user_id name permission],
          properties: {
            user_id: { type: :string, format: :uuid },
            name: { type: :string },
            permission: { type: :string, enum: %w[none full_control read_write read_only] }
          }
        }
      }
    }
  }

  error_schema = { '$ref' => '#/components/schemas/ErrorResponse' }

  path '/api/v1/accounts/{id}/sharing' do
    parameter name: :id, in: :path, type: :string, required: true

    get 'Show who an account is shared with' do
      description 'Sure+ `accounts.sharing`. The web\'s sharing dialog. The owner gets every active family member ' \
                  'with a permission (`none` means not shared); a member the account is shared with gets their own ' \
                  'permission and `include_in_finances`.'
      tags 'Account Sharing (Sure+)'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'sharing shown' do
        schema sharing_schema
        run_test!
      end

      response '404', 'account not accessible' do
        schema error_schema
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch 'Change who an account is shared with' do
      description 'Sure+ `accounts.sharing`. Owner: `members` with a permission each (`none` unshares; new shares ' \
                  'count in the member\'s finances, as on the web). Members not listed are left alone. A member the ' \
                  'account is shared with may only send `include_in_finances`; sending `members` is 403. ' \
                  'Unknown permissions or users are 422.'
      tags 'Account Sharing (Sure+)'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[sharing],
        properties: {
          sharing: {
            type: :object,
            properties: {
              members: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[user_id permission],
                  properties: {
                    user_id: { type: :string, format: :uuid },
                    permission: { type: :string, enum: %w[none full_control read_write read_only] }
                  }
                }
              },
              include_in_finances: { type: :boolean }
            }
          }
        }
      }

      response '200', 'sharing updated' do
        schema sharing_schema
        let(:body) { { sharing: { members: [ { user_id: other_member.id, permission: 'read_only' } ] } } }
        run_test!
      end

      response '422', 'invalid permission or member' do
        schema error_schema
        let(:body) { { sharing: { members: [ { user_id: other_member.id, permission: 'owner' } ] } } }
        run_test!
      end
    end
  end
end
