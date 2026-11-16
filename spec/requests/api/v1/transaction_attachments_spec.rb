# frozen_string_literal: true

require 'swagger_helper'

# Documentation only. Behavioral coverage lives in
# test/controllers/api/v1/transaction_attachments_controller_test.rb, per
# docs/llm-guides/api-endpoint-consistency.md.
RSpec.describe 'API V1 Transaction Attachments', type: :request do
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
      email: 'api-attachments-user@example.com',
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

  let!(:transaction) do
    entry = account.entries.create!(
      name: 'Hardware store',
      date: Date.current,
      amount: 42,
      currency: 'USD',
      entryable: Transaction.new
    )
    entry.transaction
  end

  let(:transaction_id) { transaction.id }

  let(:existing_attachment) do
    transaction.attachments.attach(io: StringIO.new('%PDF-1.4 receipt'), filename: 'receipt.pdf', content_type: 'application/pdf')
    transaction.attachments.first
  end

  def upload(content: '%PDF-1.4 receipt', content_type: 'application/pdf', filename: 'receipt.pdf')
    Rack::Test::UploadedFile.new(StringIO.new(content), content_type, original_filename: filename)
  end

  path '/api/v1/transactions/{transaction_id}/attachments' do
    parameter name: :transaction_id, in: :path, type: :string, format: :uuid, required: true

    post 'Attach a file to a transaction' do
      description 'Uploads a receipt or other file, with the same rules as the web: JPEG, PNG, GIF, WebP or PDF ' \
                  "(#{Transaction::ALLOWED_CONTENT_TYPES.join(', ')}), at most #{Transaction::MAX_ATTACHMENT_SIZE / 1.megabyte} MB, " \
                  "and at most #{Transaction::MAX_ATTACHMENTS_PER_TRANSACTION} files per transaction. The type is detected " \
                  'from the file content, so HEIC photos are rejected; convert them to JPEG first. Needs owner, ' \
                  'full_control or read_write access to the account.'
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      consumes 'multipart/form-data'
      produces 'application/json'

      parameter name: :file, in: :formData, required: true,
                description: 'The file to attach',
                schema: {
                  type: :object,
                  required: [ 'file' ],
                  properties: { file: { type: :string, format: :binary } }
                }

      response '201', 'attachment stored' do
        schema '$ref' => '#/components/schemas/TransactionAttachment'
        let(:file) { upload }
        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') { nil }
        let(:file) { upload }
        run_test!
      end

      response '403', 'API key without write scope, or a read_only share' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') do
          ApiKey.create!(user: user, name: 'Read Key', key: ApiKey.generate_secure_key, scopes: %w[read], source: 'mobile').plain_key
        end
        let(:file) { upload }
        run_test!
      end

      response '404', 'transaction not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:transaction_id) { SecureRandom.uuid }
        let(:file) { upload }
        run_test!
      end

      response '422', 'disallowed type, too large, too many attachments, or no file' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:file) { upload(content: 'plain text', content_type: 'text/plain', filename: 'notes.txt') }
        run_test!
      end
    end
  end

  path '/api/v1/transactions/{transaction_id}/attachments/{id}' do
    parameter name: :transaction_id, in: :path, type: :string, format: :uuid, required: true
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete 'Delete an attachment' do
      description 'Deletes the file. Needs owner or full_control access to the account; a read_write share can add files but not delete them, as on the web.'
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '204', 'attachment deleted' do
        let(:id) { existing_attachment.id }
        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') { nil }
        let(:id) { existing_attachment.id }
        run_test!
      end

      response '404', 'attachment not found on this transaction' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  path '/api/v1/attachments/{id}' do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true
    parameter name: :disposition, in: :query, required: false,
              description: 'attachment to ask for a download; inline (default) otherwise',
              schema: { type: :string, enum: %w[inline attachment] }

    get 'Download an attachment' do
      description 'Streams the file. This is the url in each transaction attachment. It needs the same credentials ' \
                  'as any other call; any share of the account may download.'
      tags 'Transactions'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'the file' do
        # Streamed with the file's own content type; only the error responses are JSON.
        metadata[:response][:content] = {
          'application/octet-stream' => { schema: { type: :string, format: :binary } }
        }
        let(:id) { existing_attachment.id }
        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') { nil }
        let(:id) { existing_attachment.id }
        run_test!
      end

      response '404', 'attachment not found, or on an account the caller cannot see' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end
end
