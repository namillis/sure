# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_recurring_marks_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Mark As Recurring', type: :request do
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
      email: 'api-mark-recurring-user@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let(:account) do
    Account.create!(family: family, owner: user, name: 'Checking Account', balance: 1000, currency: 'USD',
                    accountable: Depository.create!)
  end

  let!(:transaction) do
    account.entries.create!(name: 'Streaming service', date: Date.current, amount: 15, currency: 'USD',
                            entryable: Transaction.new).transaction
  end

  let(:id) { transaction.id }

  path '/api/v1/transactions/{id}/mark_as_recurring' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    post 'Mark a transaction as recurring' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Creates a manual recurring transaction from this transaction, as the web\'s ' \
                  '"Mark as recurring" does. Returns 409 with the existing recurring transaction when one ' \
                  'already covers this transaction or holds the same pattern (an ended one included); ' \
                  '`recurring_transaction` is null when you cannot see it. Needs write access (owner or ' \
                  'full control) to the account. Requires the `read_write` scope.'
      produces 'application/json'

      response '201', 'recurring transaction created' do
        schema '$ref' => '#/components/schemas/RecurringTransaction'
        run_test!
      end

      response '409', 'a recurring transaction already exists' do
        before { RecurringTransaction.create_from_transaction(transaction) }
        schema type: :object,
               required: %w[error message recurring_transaction],
               properties: {
                 error: { type: :string },
                 message: { type: :string },
                 errors: { type: :array, items: { type: :string } },
                 recurring_transaction: { '$ref' => '#/components/schemas/RecurringTransaction', nullable: true }
               }
        run_test!
      end
    end
  end
end
