# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Household Members (Sure+)', type: :request do
  let(:family) do
    Family.create!(name: 'API Family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y')
  end

  let(:user) do
    family.users.create!(
      email: 'api-admin@example.com',
      first_name: 'Ada',
      last_name: 'Admin',
      role: 'admin',
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

  let!(:pending_invitation) do
    family.invitations.create!(email: 'pending@example.com', role: 'member', inviter: user)
  end

  invitation_schema = {
    type: :object,
    required: %w[id email role created_at expires_at],
    properties: {
      id: { type: :string, format: :uuid },
      email: { type: :string },
      role: { type: :string, enum: %w[admin member guest] },
      created_at: { type: :string, format: 'date-time' },
      expires_at: { type: :string, format: 'date-time' }
    }
  }

  error_schema = { '$ref' => '#/components/schemas/ErrorResponse' }

  path '/api/v1/family/members' do
    get 'List household members and pending invitations' do
      description 'Sure+ `household.members`. The members and pending invitations Settings > Profile shows. ' \
                  'Invitation tokens and accept links are never returned. `avatar_url` is a short-lived signed URL, ' \
                  'or null when there is no avatar or the storage service is public. `invitations_enabled` is false ' \
                  'on a self-hosted server closed to sign-ups. `invitation_delivery` is `link_only` on self-hosted ' \
                  'servers, which send no invitation email; the admin shares the link from the web.'
      tags 'Household (Sure+)'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'members listed' do
        schema type: :object,
               required: %w[members pending_invitations can_manage_invitations invitations_enabled invitation_delivery],
               properties: {
                 members: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id name email role avatar_url is_current_user],
                     properties: {
                       id: { type: :string, format: :uuid },
                       name: { type: :string },
                       email: { type: :string },
                       role: { type: :string, enum: %w[guest member admin super_admin] },
                       avatar_url: { type: :string, nullable: true },
                       is_current_user: { type: :boolean }
                     }
                   }
                 },
                 pending_invitations: { type: :array, items: invitation_schema },
                 can_manage_invitations: { type: :boolean },
                 invitations_enabled: { type: :boolean },
                 invitation_delivery: { type: :string, enum: %w[email link_only] }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        schema error_schema
        let(:'X-Api-Key') { nil }
        run_test!
      end
    end
  end

  path '/api/v1/invitations' do
    post 'Invite someone to the household' do
      description 'Sure+ `household.members`. Admins only, as on the web. Sends the web\'s invitation email ' \
                  '(managed servers only). 422 `validation_failed` for a bad email or role, an existing member, ' \
                  'an existing pending invitation or the admin\'s own email; 422 `invitations_disabled` when the ' \
                  'self-hosted server is closed to sign-ups.'
      tags 'Household (Sure+)'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[invitation],
        properties: {
          invitation: {
            type: :object,
            required: %w[email role],
            properties: {
              email: { type: :string },
              role: { type: :string, enum: %w[admin member guest] }
            }
          }
        }
      }

      response '201', 'invitation created' do
        schema type: :object,
               required: invitation_schema[:required] + %w[delivery],
               properties: invitation_schema[:properties].merge(delivery: { type: :string, enum: %w[email link_only] })
        let(:body) { { invitation: { email: 'new@example.com', role: 'member' } } }
        run_test!
      end

      response '422', 'invalid, duplicate or disabled' do
        schema error_schema
        let(:body) { { invitation: { email: 'pending@example.com', role: 'member' } } }
        run_test!
      end
    end
  end

  path '/api/v1/invitations/bulk' do
    post 'Invite several people at once' do
      description 'Sure+ `household.members`. The web\'s bulk invite: members and guests only (no admin), at most ' \
                  '50 addresses. `emails` is an array or the web\'s comma/space separated string. Each address gets ' \
                  'a result: `sent`, `link_only` (self-hosted, no email) or `invalid` with `detail`.'
      tags 'Household (Sure+)'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[bulk_invitation],
        properties: {
          bulk_invitation: {
            type: :object,
            required: %w[emails role],
            properties: {
              emails: { oneOf: [ { type: :array, items: { type: :string } }, { type: :string } ] },
              role: { type: :string, enum: %w[member guest] }
            }
          }
        }
      }

      response '200', 'batch processed' do
        schema type: :object,
               required: %w[sent link_only invalid results],
               properties: {
                 sent: { type: :integer },
                 link_only: { type: :integer },
                 invalid: { type: :integer },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       email: { type: :string },
                       status: { type: :string, enum: %w[sent link_only invalid] },
                       detail: { type: :string, nullable: true }
                     }
                   }
                 }
               }
        let(:body) { { bulk_invitation: { emails: %w[a@example.com b@example.com], role: 'member' } } }
        run_test!
      end

      response '422', 'bad role, empty or too many' do
        schema error_schema
        let(:body) { { bulk_invitation: { emails: %w[a@example.com], role: 'admin' } } }
        run_test!
      end
    end
  end

  path '/api/v1/invitations/{id}' do
    parameter name: :id, in: :path, type: :string, required: true

    delete 'Revoke an invitation' do
      description 'Sure+ `household.members`. Admins only.'
      tags 'Household (Sure+)'
      security [ { apiKeyAuth: [] } ]

      response '204', 'invitation revoked' do
        let(:id) { pending_invitation.id }
        run_test!
      end

      response '404', 'not found' do
        schema error_schema
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end
end
