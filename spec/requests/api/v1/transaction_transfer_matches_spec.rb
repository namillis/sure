# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_transfer_matches_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Transfer Matches', type: :request do
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
      email: 'api-transfer-match-user@example.com',
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

  let(:checking) do
    Account.create!(family: family, owner: user, name: 'Checking Account', balance: 1000, currency: 'USD',
                    accountable: Depository.create!)
  end

  let(:savings) do
    Account.create!(family: family, owner: user, name: 'Savings Account', balance: 1000, currency: 'USD',
                    accountable: Depository.create!)
  end

  let!(:outflow) do
    checking.entries.create!(name: 'Move to savings', date: Date.current, amount: 100, currency: 'USD',
                             entryable: Transaction.new).transaction
  end

  let!(:inflow) do
    savings.entries.create!(name: 'From checking', date: Date.current, amount: -100, currency: 'USD',
                            entryable: Transaction.new)
  end

  let(:id) { outflow.id }

  account_ref = {
    type: :object,
    required: %w[id name],
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string }
    }
  }

  path '/api/v1/transactions/{id}/transfer_candidates' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    get 'List transfer match candidates' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'What the web\'s "match as transfer" dialog offers. `candidates` are existing opposite ' \
                  'transactions on accounts you can write to, likeliest first; pass a candidate\'s ' \
                  '`transaction.entry_id` as `matched_entry_id` to match it. `accounts` are the accounts ' \
                  '`method: "new"` can create the other side in. Requires the `read` scope.'
      produces 'application/json'

      response '200', 'candidates returned' do
        schema type: :object,
               required: %w[candidates accounts],
               properties: {
                 candidates: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[transaction account],
                     properties: {
                       transaction: { '$ref' => '#/components/schemas/Transaction' },
                       account: account_ref
                     }
                   }
                 },
                 accounts: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id name account_type currency],
                     properties: {
                       id: { type: :string, format: :uuid },
                       name: { type: :string },
                       account_type: { type: :string },
                       currency: { type: :string }
                     }
                   }
                 }
               }
        run_test!
      end

      response '404', 'transaction not found' do
        let(:id) { SecureRandom.uuid }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{id}/transfer_match' do
    parameter name: :id, in: :path, type: :string, description: 'Transaction ID'

    post 'Mark a transaction as a transfer' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Links the transaction into a confirmed transfer, as the web\'s "match as transfer" dialog ' \
                  'does. `method: "existing"` pairs it with `matched_entry_id` (an entry id from ' \
                  '`transfer_candidates`); `method: "new"` creates the opposite transaction in ' \
                  '`target_account_id`. Needs write access (owner or full control) to both accounts. ' \
                  'Returns 422 with a `reason` (not_a_candidate, already_linked, same_account, ' \
                  'split_transaction, excluded_transaction, invalid_transfer) when the pair is not valid. ' \
                  'Requires the `read_write` scope.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[transfer_match],
        properties: {
          transfer_match: {
            type: :object,
            required: %w[method],
            properties: {
              method: { type: :string, enum: %w[existing new] },
              matched_entry_id: { type: :string, format: :uuid, description: 'Entry id of the other side, for method existing' },
              target_account_id: { type: :string, format: :uuid, description: 'Account for the new other side, for method new' }
            }
          }
        }
      }

      let(:body) { { transfer_match: { method: 'existing', matched_entry_id: inflow.id } } }

      response '201', 'transfer created' do
        schema type: :object,
               required: %w[transfer inflow outflow],
               properties: {
                 transfer: { '$ref' => '#/components/schemas/TransferDecision' },
                 inflow: { '$ref' => '#/components/schemas/Transaction' },
                 outflow: { '$ref' => '#/components/schemas/Transaction' }
               }
        run_test!
      end

      response '422', 'the pair cannot form a transfer' do
        let(:body) { { transfer_match: { method: 'new', target_account_id: checking.id } } }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end

    delete 'Unmatch a transfer' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'When the transaction is part of a transfer, removes the transfer and records the pair as ' \
                  'rejected so automatic matching does not pair them again (the web\'s "Reject match"). ' \
                  'Otherwise records every pair the web\'s transfer hint suggests for it as rejected (the ' \
                  'web\'s "Not a transfer"). Returns the transaction. Requires the `read_write` scope.'
      produces 'application/json'

      response '200', 'unmatched' do
        before { Transfer::Matcher.new(outflow).match_with!(inflow.transaction) }
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end
    end
  end
end
