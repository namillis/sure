# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_locks_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Locks', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y',
                   manual_reconciliation: true)
  end

  let(:user) do
    family.users.create!(
      email: 'api-locks-user@example.com',
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
    Account.create!(
      family: family,
      owner: user,
      name: 'Cash Wallet',
      balance: 200,
      currency: 'USD',
      accountable: Depository.create!
    )
  end

  let!(:transaction) do
    entry = account.entries.create!(name: 'Coffee', date: Date.current, amount: 4, currency: 'USD',
                                    user_modified: true, locked_attributes: { 'name' => Time.current.iso8601 },
                                    entryable: Transaction.new)
    entry.transaction
  end

  let(:id) { transaction.id }

  path '/api/v1/transactions/{id}/unlock' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    post 'Let bank sync update a transaction again' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Removes the sync protection a user edit or an import put on the transaction ' \
                  '(sync_locked and locked_attributes). The next bank sync may then overwrite the user\'s ' \
                  'changes. Returns the transaction. Needs owner or full-control access to the account.'
      produces 'application/json'

      response '200', 'unlocked' do
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end

      response '403', 'read-only key, or no write access to the account' do
        let(:'X-Api-Key') do
          ApiKey.create!(user: user, name: 'Read key', key: ApiKey.generate_secure_key, scopes: %w[read],
                         source: 'mobile').plain_key
        end
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{id}/reconcile' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    patch 'Advance the reconciled status' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Reconciling means ticking a transaction off against a bank or card statement, the ' \
                  'way you would in a paper checkbook. It is only for accounts without bank sync, and only ' \
                  'when the family has turned on manual reconciliation (the transaction\'s reconcilable is ' \
                  'true). Each call moves reconciled_status one step: unreconciled ("Not yet checked against ' \
                  'a statement") to cleared ("Seen on a statement, not fully reconciled yet") to reconciled ' \
                  '("Statement period fully reconciled") and back to unreconciled. The web labels the control ' \
                  'with the current status: Unreconciled, Cleared or Reconciled. Takes no body, like the web. ' \
                  'Returns the transaction. Needs owner or full-control access to the account.'
      produces 'application/json'

      response '200', 'status advanced' do
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end

      response '422', 'manual reconciliation is off (reconciliation_disabled), the account has bank sync ' \
                      '(not_manual_account), or the update failed (reconcile_failed)' do
        before { family.update!(manual_reconciliation: false) }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end
end
