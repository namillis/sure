# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_duplicates_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Duplicates', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-duplicates-user@example.com',
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
      name: 'Checking Account',
      balance: 1000,
      currency: 'USD',
      accountable: Depository.create!
    )
  end

  let!(:posted_entry) do
    account.entries.create!(name: 'STARBUCKS CORP', date: Date.current, amount: 12, currency: 'USD',
                            entryable: Transaction.new)
  end

  let!(:pending_transaction) do
    entry = account.entries.create!(name: 'Starbucks', date: 2.days.ago.to_date, amount: 12, currency: 'USD',
                                    entryable: Transaction.new(extra: { 'simplefin' => { 'pending' => true } }))
    entry.transaction
  end

  let(:suggest_duplicate) do
    pending_transaction.update!(extra: pending_transaction.extra.merge(
      'potential_posted_match' => {
        'entry_id' => posted_entry.id, 'reason' => 'fuzzy_amount_match', 'posted_amount' => '12.0',
        'confidence' => 'medium', 'detected_at' => Date.current.to_s
      }
    ))
  end

  let(:id) { pending_transaction.id }

  path '/api/v1/transactions/{id}/merge_duplicate' do
    parameter name: :id, in: :path, type: :string, description: 'Pending transaction ID'

    post 'Merge a pending transaction into its suggested duplicate' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'For a pending transaction whose duplicate_suspected is true: confirms that it and ' \
                  'duplicate_candidate are the same purchase. The pending transaction is deleted and the ' \
                  'posted one is kept. Unless the posted transaction was already locked against sync, it ' \
                  'takes the pending date and category; it keeps its own name and merchant, gains the pending ' \
                  'notes, tags and attachments, and is then locked against sync changes. Returns the surviving ' \
                  'posted transaction. Needs owner or full-control access to the account.'
      produces 'application/json'

      response '200', 'merged; the surviving posted transaction' do
        before { suggest_duplicate }
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end

      response '422', 'not pending (not_pending), no suggestion (no_duplicate), or the merge was refused (merge_failed)' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{id}/dismiss_duplicate' do
    parameter name: :id, in: :path, type: :string, description: 'Pending transaction ID'

    post 'Keep both transactions' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Says the suggested duplicate is a different purchase. The suggestion is hidden ' \
                  '(duplicate_suspected becomes false) and both transactions stay. Returns the transaction. ' \
                  'Needs owner or full-control access to the account.'
      produces 'application/json'

      response '200', 'suggestion dismissed' do
        before { suggest_duplicate }
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end

      response '422', 'no suggestion to dismiss (no_duplicate)' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{id}/pending_merge_candidates' do
    parameter name: :id, in: :path, type: :string, description: 'Pending transaction ID'
    parameter name: :offset, in: :query, type: :integer, required: false,
              description: 'Number of candidates to skip. Pages are 10 long.'

    get 'List posted transactions a pending one can be merged into' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'The recent posted transactions in the same account and currency, newest first, that ' \
                  'the user can pick when the bank booked a pending transaction under a different amount ' \
                  'or name. Pass a candidate\'s entry_id to pending_merge.'
      produces 'application/json'

      response '200', 'candidates listed' do
        schema type: :object,
               required: %w[candidates pagination],
               properties: {
                 candidates: { type: :array, items: { '$ref' => '#/components/schemas/Transaction' } },
                 pagination: {
                   type: :object,
                   required: %w[offset limit has_more],
                   properties: {
                     offset: { type: :integer },
                     limit: { type: :integer },
                     has_more: { type: :boolean }
                   }
                 }
               }
        run_test!
      end

      response '422', 'the transaction is not pending (not_pending)' do
        let(:id) { posted_entry.entryable_id }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{id}/pending_merge' do
    parameter name: :id, in: :path, type: :string, description: 'Pending transaction ID'

    post 'Merge a pending transaction into a chosen posted transaction' do
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      description 'Merges the pending transaction into a posted one the user picked from ' \
                  'pending_merge_candidates, with the same result as merge_duplicate. Returns the surviving ' \
                  'posted transaction. Needs owner, full-control or read-write access to the account, as on ' \
                  'the web.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[pending_merge],
        properties: {
          pending_merge: {
            type: :object,
            required: %w[posted_entry_id],
            properties: {
              posted_entry_id: { type: :string, format: :uuid, description: 'entry_id of a pending_merge_candidates item' }
            }
          }
        }
      }

      let(:body) { { pending_merge: { posted_entry_id: posted_entry.id } } }

      response '200', 'merged; the surviving posted transaction' do
        schema '$ref' => '#/components/schemas/Transaction'
        run_test!
      end

      response '422', 'missing posted_entry_id (validation_failed), not a candidate (invalid_posted_entry), ' \
                      'not pending (not_pending) or the merge was refused (merge_failed)' do
        let(:body) { { pending_merge: { posted_entry_id: pending_transaction.entry.id } } }
        schema '$ref' => '#/components/schemas/ErrorResponse'
        run_test!
      end
    end
  end
end
