# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Merchants (update and delete)', type: :request do
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
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: ApiKey.generate_secure_key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:read_only_api_key) do
    ApiKey.create!(
      user: user,
      name: 'API Docs Read Key',
      key: ApiKey.generate_secure_key,
      scopes: %w[read],
      source: 'mobile'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:family_merchant) { family.merchants.create!(name: 'Coffee Shop') }
  let!(:other_family_merchant) { family.merchants.create!(name: 'Bakery') }

  let(:provider_merchant) do
    merchant = ProviderMerchant.create!(name: 'Netflix', source: 'plaid')
    account = Account.create!(
      family: family,
      owner: user,
      name: 'Checking Account',
      balance: 1000,
      currency: 'USD',
      accountable: Depository.create!
    )
    account.entries.create!(
      name: 'Netflix',
      date: Date.current,
      amount: 15.49,
      currency: 'USD',
      entryable: Transaction.new(merchant: merchant)
    )
    merchant
  end

  update_request_schema = {
    type: :object,
    required: %w[merchant],
    properties: {
      merchant: {
        type: :object,
        properties: {
          name: { type: :string, description: 'Merchant name (unique within family)' },
          color: { type: :string, description: 'Hex color code (e.g. #4da568). An invalid or blank color is replaced with a random palette color, as on the web.' },
          website_url: { type: :string, nullable: true, description: 'Merchant website, used to fetch a logo when Brandfetch is configured' }
        }
      }
    }
  }

  path '/api/v1/merchants/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Merchant ID'

    patch 'Update family merchant' do
      tags 'Merchants'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description 'Updates one of the family\'s own merchants (type FamilyMerchant). Provider merchants are read-only and return 403.'
      parameter name: :body, in: :body, required: true, schema: update_request_schema

      let(:id) { family_merchant.id }

      response '200', 'merchant updated' do
        schema '$ref' => '#/components/schemas/MerchantDetail'

        let(:body) { { merchant: { name: 'Coffee House', color: '#4da568', website_url: 'coffeehouse.example' } } }

        run_test!
      end

      response '422', 'validation error - blank or duplicate name' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { merchant: { name: other_family_merchant.name } } }

        run_test!
      end

      response '403', 'forbidden - provider merchant, api key missing read_write scope, or guest user' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { provider_merchant.id }
        let(:body) { { merchant: { name: 'Mine' } } }

        run_test!
      end

      response '404', 'merchant not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }
        let(:body) { { merchant: { name: 'Mine' } } }

        run_test!
      end

      response '401', 'unauthorized - missing api key' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }
        let(:body) { { merchant: { name: 'Mine' } } }

        run_test!
      end
    end

    delete 'Delete family merchant' do
      tags 'Merchants'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description 'Deletes one of the family\'s own merchants; its transactions keep no merchant. Provider merchants are read-only and return 403.'

      let(:id) { family_merchant.id }

      response '204', 'merchant deleted' do
        run_test!
      end

      response '403', 'forbidden - provider merchant, api key missing read_write scope, or guest user' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }

        run_test!
      end

      response '404', 'merchant not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end
end
