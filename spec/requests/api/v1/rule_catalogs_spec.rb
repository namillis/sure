# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Rule Catalog', type: :request do
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
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  option_schema = {
    type: :object,
    required: %w[value label],
    properties: {
      value: { type: :string },
      label: { type: :string }
    }
  }

  path '/api/v1/rules/catalog' do
    get 'List the conditions and actions a rule can use' do
      tags 'Rules'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description <<~DESC
        Built from the server's rule registry, as the web rule form renders it. Labels are localized
        as on the web: the `locale` param, else the user's locale, else Accept-Language, else the family's.

        `options` lists `{ value, label }` for select and multi_select types, including categories,
        merchants, tags and accounts scoped as the web form scopes them; it is null for every other type.
        `available` is false for an action a new rule cannot pick right now (the AI actions without a
        provider); existing rules may still carry it.

        Split action (`value_type: split`): `value` is a JSON string
        `{"splits":[{"name":"Rent","type":"percentage","share":"60","category_id":"<uuid>|null",
        "merchant_id":"<uuid>|null","tag_ids":["<uuid>"]}, ...]}` with 2 to 20 rows. `type` is
        `fixed` (an amount, at most 4 decimals) or `percentage` (of what is left after the fixed rows;
        percentages must total 100 within 0.01). `share` is a number or numeric string. `name` is required, at most 255 characters. Shares
        must be positive. Category, merchant and tags must belong to the family. A config with only
        fixed rows needs an ANDed `transaction_amount` `=` condition whose value the shares sum to.
        A split must be the rule's only action. Writes may instead send
        `split_rows: [{ type, name, share, category_id, merchant_id, tag_ids }]` and the server builds `value`.
      DESC
      parameter name: :resource_type, in: :query, required: false,
                description: 'Rule resource type (default: transaction)',
                schema: { type: :string, enum: %w[transaction] }
      parameter name: :locale, in: :query, required: false, type: :string,
                description: 'Locale for labels, overriding the user, Accept-Language and family locale'

      response '200', 'catalog listed' do
        schema type: :object,
               required: %w[resource_type ai_available conditions actions],
               properties: {
                 resource_type: { type: :string },
                 ai_available: { type: :boolean, description: 'Whether any AI action is offered for new rules' },
                 conditions: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[key label type operators options],
                     properties: {
                       key: { type: :string },
                       label: { type: :string },
                       type: { type: :string, enum: %w[text number select] },
                       operators: {
                         type: :array,
                         items: {
                           type: :object,
                           required: %w[key label requires_value],
                           properties: {
                             key: { type: :string },
                             label: { type: :string },
                             requires_value: { type: :boolean }
                           }
                         }
                       },
                       options: { type: :array, nullable: true, items: option_schema },
                       number_step: { type: :number, nullable: true }
                     }
                   }
                 },
                 actions: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[key label value_type options requires_ai available],
                     properties: {
                       key: { type: :string },
                       label: { type: :string },
                       value_type: { type: :string, enum: %w[select multi_select function text split] },
                       options: { type: :array, nullable: true, items: option_schema },
                       requires_ai: { type: :boolean },
                       available: { type: :boolean }
                     }
                   }
                 }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '422', 'unsupported resource type' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:resource_type) { 'account' }

        run_test!
      end
    end
  end
end
