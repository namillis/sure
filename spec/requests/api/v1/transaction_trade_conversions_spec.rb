# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_trade_conversions_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Trade Conversion', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-convert-trade@example.com',
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

  let(:'X-Api-Key') { api_key.plain_key }

  let(:account) do
    Account.create!(
      family: family,
      owner: user,
      name: 'Brokerage',
      balance: 1000,
      currency: 'USD',
      accountable: Investment.create!
    )
  end

  let(:security) do
    Security.create!(ticker: 'VTI', name: 'Vanguard Total Stock Market ETF', exchange_operating_mic: 'ARCX')
  end

  let!(:transaction) do
    account.entries.create!(
      name: 'VTI purchase',
      date: Date.current,
      amount: 100,
      currency: 'USD',
      entryable: Transaction.new
    ).transaction
  end

  let(:id) { transaction.id }

  path '/api/v1/transactions/{id}/convert_to_trade' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    get 'Get the defaults for converting a transaction to a trade' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Returns what the web "Convert to trade" form starts with. The trade is always ' \
                  'booked in the transaction\'s own account, which must be an investment account ' \
                  'or a crypto exchange. security_options lists the securities the account already ' \
                  'holds, with today\'s stored price when there is one. When ticker_search_available ' \
                  'is true, a typed ticker sent as custom_ticker is looked up through the ' \
                  'securities provider. Requires write access to the account, as on the web.'
      produces 'application/json'

      response '200', 'conversion defaults' do
        schema type: :object,
               required: %w[transaction_id date name amount amount_cents currency account defaults
                            investment_activity_labels ticker_search_available security_options],
               properties: {
                 transaction_id: { type: :string, format: :uuid },
                 date: { type: :string, format: :date },
                 name: { type: :string },
                 amount: { type: :string, description: 'Unsigned, formatted' },
                 amount_cents: { type: :integer, description: 'Unsigned, in minor units' },
                 currency: { type: :string },
                 account: {
                   type: :object,
                   properties: {
                     id: { type: :string, format: :uuid },
                     name: { type: :string },
                     account_type: { type: :string }
                   }
                 },
                 defaults: {
                   type: :object,
                   properties: {
                     investment_activity_label: { type: :string, enum: %w[Buy Sell],
                                                  description: 'Buy for money out, Sell for money in' },
                     security_id: { type: :string, nullable: true },
                     qty: { type: :string, nullable: true },
                     price: { type: :string, nullable: true }
                   }
                 },
                 investment_activity_labels: { type: :array, items: { type: :string } },
                 ticker_search_available: { type: :boolean },
                 security_options: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid },
                       ticker: { type: :string },
                       name: { type: :string, nullable: true },
                       exchange_operating_mic: { type: :string, nullable: true },
                       current_price: { type: :string, nullable: true },
                       current_price_cents: { type: :integer, nullable: true },
                       current_price_currency: { type: :string, nullable: true }
                     }
                   }
                 }
               }
        run_test!
      end

      response '422', 'the account cannot hold trades, or the transaction is already converted' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        before { transaction.entry.update!(excluded: true) }
        run_test!
      end
    end

    post 'Convert a transaction to a trade' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Creates a trade in the transaction\'s account with the transaction\'s date and ' \
                  'currency, and excludes the original transaction, as the web does. Identify the ' \
                  'security with security_id, ticker ("SYMBOL|EXCHANGE|PROVIDER") or custom_ticker. ' \
                  'Send qty or price; the other is inferred from the transaction amount. Without ' \
                  'investment_activity_label, money out is a Buy and money in is a Sell. Errors ' \
                  'return 422 with error set to the web\'s reason: not_investment_account, ' \
                  'already_converted, select_security, security_not_found, enter_ticker, ' \
                  'enter_qty_or_price, invalid_qty_or_price, or validation_failed.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[trade],
        properties: {
          trade: {
            type: :object,
            properties: {
              security_id: { type: :string, format: :uuid },
              ticker: { type: :string, description: 'Securities search id, SYMBOL|EXCHANGE|PROVIDER' },
              custom_ticker: { type: :string },
              exchange_operating_mic: { type: :string },
              qty: { type: :number },
              price: { type: :number },
              investment_activity_label: { type: :string, enum: %w[Buy Sell] },
              trade_name: { type: :string }
            }
          }
        }
      }

      let(:body) { { trade: { security_id: security.id, qty: 2 } } }

      response '201', 'trade created' do
        schema '$ref' => '#/components/schemas/Trade'
        run_test!
      end

      response '422', 'invalid security, quantity or price' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:body) { { trade: { security_id: security.id } } }
        run_test!
      end
    end
  end
end
