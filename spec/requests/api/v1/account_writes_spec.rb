# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Account writes', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(email: 'api-user@example.com', password: 'password123', password_confirmation: 'password123')
  end

  let(:api_key) do
    ApiKey.create!(user: user, name: 'API Docs Key', key: ApiKey.generate_secure_key, scopes: %w[read_write], source: 'web')
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:checking_account) do
    Account.create!(family: family, owner: user, name: 'Checking', balance: 1500, currency: 'USD', accountable: Depository.create!)
  end

  account_write_schema = {
    type: :object,
    properties: {
      accountable_type: {
        type: :string,
        enum: Accountable::TYPES + Accountable::TYPES.map(&:underscore),
        description: 'Account type, as the class name (CreditCard) or as account_type in responses (credit_card). Required on create; on update it may only repeat the current type'
      },
      name: { type: :string },
      balance: { type: :number, description: 'Current balance. Not allowed on linked accounts' },
      currency: { type: :string, description: "Defaults to the family currency on create. Not allowed on linked accounts" },
      subtype: { type: :string, nullable: true, description: "The type's subtype (e.g. checking, savings, mortgage, brokerage)" },
      opening_balance_date: { type: :string, format: :date, description: 'Create only. Defaults to two years ago; a loan with initial_balance opens on its start_date' },
      institution_name: { type: :string, nullable: true },
      institution_domain: { type: :string, nullable: true },
      notes: { type: :string, nullable: true },
      exclude_from_reports: { type: :boolean, description: 'Not used for Property' },
      enable_category_matcher: { type: :boolean, description: 'Not used for Property' },
      accountable_attributes: {
        type: :object,
        description: "Fields of the account's type. CreditCard: available_credit, minimum_payment, apr, annual_fee, expiration_date, " \
                     'statement_close_day, due_day. Loan: subtype, rate_type, interest_rate, term_months, initial_balance, start_date, ' \
                     'down_payment, insurance_rate, insurance_rate_type, day_count_convention, principal_only_transfers, ' \
                     'rate_changes [{effective_date (YYYY-MM-DD), rate (0-100)}] replaces the whole list ([] clears it, ' \
                     'leaving it out keeps it). Investment: subtype. Crypto: subtype, tax_treatment. ' \
                     'Property: subtype, year_built, area_value, area_unit, address_attributes {line1, line2, locality, region, ' \
                     'country, postal_code}. Vehicle: make, model, year, mileage_value, mileage_unit, initial_balance, ' \
                     'initial_balance_shown, purchase_date (the last three not on linked accounts). Depository, OtherAsset, ' \
                     'OtherLiability: none. Other keys are ignored',
        additionalProperties: true
      }
    }
  }

  path '/api/v1/accounts' do
    post 'Create a manual account' do
      tags 'Accounts'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { account: account_write_schema.merge(required: %w[accountable_type name balance]) },
        required: %w[account]
      }

      response '201', 'account created' do
        schema '$ref' => '#/components/schemas/AccountDetail'

        let(:body) do
          {
            account: {
              accountable_type: 'Loan', name: 'Mortgage', balance: 250_000, currency: 'USD',
              accountable_attributes: { subtype: 'mortgage', interest_rate: 6.1, term_months: 360, rate_type: 'fixed' }
            }
          }
        end

        run_test!
      end

      response '201', 'property created with address' do
        schema '$ref' => '#/components/schemas/AccountDetail'

        let(:body) do
          {
            account: {
              accountable_type: 'Property', name: 'Home', balance: 450_000,
              accountable_attributes: {
                subtype: 'single_family_home', year_built: 1995,
                address_attributes: { line1: '1 Main St', locality: 'Springfield', region: 'IL', postal_code: '62701', country: 'US' }
              }
            }
          }
        end

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { 'invalid' }
        let(:body) { { account: { accountable_type: 'Depository', name: 'X', balance: 1 } } }

        run_test!
      end

      response '403', 'read-only key' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:api_key) do
          ApiKey.create!(user: user, name: 'Read Key', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'web')
        end
        let(:body) { { account: { accountable_type: 'Depository', name: 'X', balance: 1 } } }

        run_test!
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { account: { accountable_type: 'Depository', name: '', balance: 1 } } }

        run_test!
      end
    end
  end

  path '/api/v1/accounts/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Account ID'

    patch 'Update an account' do
      tags 'Accounts'
      description 'Owner or full-control share only. Linked (provider-synced) accounts reject balance, currency and ' \
                  "a vehicle's initial_balance, initial_balance_shown and purchase_date; accountable_type cannot change"
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { account: account_write_schema },
        required: %w[account]
      }

      let(:id) { checking_account.id }

      response '200', 'account updated' do
        schema '$ref' => '#/components/schemas/AccountDetail'

        let(:body) { { account: { name: 'Everyday Checking', balance: 1800, subtype: 'checking' } } }

        run_test!
      end

      response '200', 'loan rate changes and insurance updated' do
        schema '$ref' => '#/components/schemas/AccountDetail'

        let(:id) do
          Account.create!(family: family, owner: user, name: 'Mortgage', balance: 250_000, currency: 'USD',
            accountable: Loan.create!(rate_type: 'variable', interest_rate: 4.5, term_months: 360,
              start_date: Date.new(2020, 1, 1))).id
        end
        let(:body) do
          { account: { accountable_attributes: {
            insurance_rate: 0.25, insurance_rate_type: 'decreasing_life',
            rate_changes: [ { effective_date: '2023-06-01', rate: 5.125 } ]
          } } }
        end

        run_test!
      end

      response '403', 'read-only share' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:other_user) do
          family.users.create!(email: 'owner@example.com', password: 'password123', password_confirmation: 'password123')
        end
        let(:id) do
          account = Account.create!(family: family, owner: other_user, name: 'Theirs', balance: 1, currency: 'USD', accountable: Depository.create!)
          account.share_with!(user, permission: 'read_only')
          account.id
        end
        let(:body) { { account: { name: 'Mine now' } } }

        run_test!
      end

      response '404', 'account not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }
        let(:body) { { account: { name: 'X' } } }

        run_test!
      end

      response '422', 'accountable_type cannot change' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { account: { accountable_type: 'Loan' } } }

        run_test!
      end
    end

    delete 'Delete a manual account' do
      tags 'Accounts'
      description 'Schedules the same background deletion as the web. Owner or full-control share only; linked accounts must be disconnected first'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      let(:id) { checking_account.id }

      response '202', 'deletion scheduled' do
        schema type: :object,
               required: %w[id message],
               properties: {
                 id: { type: :string, format: :uuid },
                 message: { type: :string }
               }

        run_test!
      end

      response '404', 'account not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end
end
