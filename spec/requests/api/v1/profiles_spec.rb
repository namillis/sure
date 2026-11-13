# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Profile', type: :request do
  profile_schema = {
    type: :object,
    required: %w[id email first_name last_name role theme default_period can_edit_family family],
    properties: {
      id: { type: :string, format: :uuid },
      email: { type: :string },
      first_name: { type: :string, nullable: true },
      last_name: { type: :string, nullable: true },
      display_name: { type: :string },
      role: { type: :string, enum: %w[guest member admin super_admin] },
      locale: { type: :string, nullable: true, description: 'User language; null follows the household locale' },
      theme: { type: :string, enum: %w[light dark system] },
      default_period: { type: :string, example: 'last_30_days' },
      can_edit_family: { type: :boolean, description: 'Whether family fields can be changed through PATCH' },
      family: {
        type: :object,
        required: %w[id name currency country timezone date_format locale],
        properties: {
          id: { type: :string, format: :uuid },
          name: { type: :string, nullable: true },
          currency: { type: :string, example: 'USD' },
          country: { type: :string, nullable: true, example: 'US' },
          timezone: { type: :string, nullable: true, example: 'America/New_York' },
          date_format: { type: :string, example: '%m-%d-%Y' },
          locale: { type: :string, example: 'en' }
        }
      },
      created_at: { type: :string, format: 'date-time' },
      updated_at: { type: :string, format: 'date-time' }
    }
  }

  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y',
      country: 'US',
      timezone: 'America/New_York'
    )
  end

  let(:role) { :admin }

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Ada',
      last_name: 'Lovelace',
      role: role
    )
  end

  let(:scopes) { %w[read_write] }

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      display_key: key,
      scopes: scopes,
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/users/me' do
    get 'Retrieve the current user profile' do
      description 'Returns the signed-in user\'s profile and display preferences, plus the household preferences ' \
                  'that PATCH can change. Requires the read scope.'
      tags 'Users'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'profile retrieved' do
        schema profile_schema

        let(:scopes) { %w[read] }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end
    end

    patch 'Update the current user profile' do
      description 'Updates the signed-in user\'s name, language, theme and default period. Household fields in ' \
                  '`family_attributes` require the admin role. Email, password, MFA and profile image are not ' \
                  'accepted here. Requires the read_write scope.'
      tags 'Users'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :profile_params, in: :body, required: true, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            properties: {
              first_name: { type: :string },
              last_name: { type: :string },
              locale: { type: :string, nullable: true, example: 'en' },
              theme: { type: :string, enum: %w[light dark system] },
              default_period: { type: :string, example: 'last_90_days' },
              family_attributes: {
                type: :object,
                description: 'Admin only',
                properties: {
                  currency: { type: :string, example: 'EUR' },
                  country: { type: :string, example: 'FR' },
                  timezone: { type: :string, example: 'Europe/Paris' },
                  date_format: { type: :string, example: '%d.%m.%Y' },
                  locale: { type: :string, example: 'fr' }
                }
              }
            }
          }
        }
      }

      let(:profile_params) do
        { user: { first_name: 'Augusta', theme: 'dark', family_attributes: { currency: 'EUR', timezone: 'Europe/Paris' } } }
      end

      response '200', 'profile updated' do
        schema profile_schema

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body['first_name']).to eq('Augusta')
          expect(body['theme']).to eq('dark')
          expect(body.dig('family', 'currency')).to eq('EUR')
        end
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid-key' }

        run_test!
      end

      response '403', 'read-only key, or a non-admin changing family fields' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:role) { :member }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:profile_params) { { user: { default_period: 'forever' } } }

        run_test!
      end
    end
  end
end
