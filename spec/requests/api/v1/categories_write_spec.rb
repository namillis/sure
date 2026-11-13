# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Categories (update and delete)', type: :request do
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

  let!(:parent_category) do
    family.categories.create!(name: 'Food & Drink', color: '#f97316', lucide_icon: 'utensils')
  end

  let!(:subcategory) do
    family.categories.create!(name: 'Restaurants', color: '#f97316', lucide_icon: 'utensils', parent: parent_category)
  end

  let!(:other_category) do
    family.categories.create!(name: 'Coffee', color: '#22c55e', lucide_icon: 'coffee')
  end

  update_request_schema = {
    type: :object,
    required: %w[category],
    properties: {
      category: {
        type: :object,
        properties: {
          name: { type: :string, description: 'Category name (unique within family)' },
          color: { type: :string, description: 'Hex color code (e.g. #22c55e). Changing a parent color also recolors its subcategories.' },
          icon: { type: :string, description: 'Lucide icon name (e.g. "coffee"). Left unchanged when omitted or blank.' },
          parent_id: { type: :string, format: :uuid, nullable: true, description: 'Parent category ID in the same family, or empty/null to make it a root category. Categories support up to 2 levels; a category with subcategories cannot get a parent.' }
        }
      }
    }
  }

  path '/api/v1/categories/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Category ID'

    patch 'Update category' do
      tags 'Categories'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: update_request_schema

      let(:id) { other_category.id }

      response '200', 'category updated' do
        schema '$ref' => '#/components/schemas/CategoryDetail'

        let(:body) { { category: { name: 'Coffee Shops', color: '#6471eb', icon: 'coffee' } } }

        run_test!
      end

      response '200', 'category moved under a parent' do
        schema '$ref' => '#/components/schemas/CategoryDetail'

        let(:body) { { category: { parent_id: parent_category.id } } }

        run_test!
      end

      response '422', 'validation error - duplicate name, invalid color, parent outside the family, own parent or too deep nesting' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { category: { name: parent_category.name } } }

        run_test!
      end

      response '403', 'forbidden - api key missing read_write scope, or guest user' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }
        let(:body) { { category: { name: 'Anything' } } }

        run_test!
      end

      response '404', 'category not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }
        let(:body) { { category: { name: 'Anything' } } }

        run_test!
      end

      response '401', 'unauthorized - missing api key' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }
        let(:body) { { category: { name: 'Anything' } } }

        run_test!
      end
    end

    delete 'Delete category' do
      tags 'Categories'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description 'Deletes the category. Its transactions become uncategorized, or move to replacement_category_id when given. Its subcategories become root categories.'
      parameter name: :replacement_category_id, in: :query, required: false,
                description: 'Category (in the same family, not this one) to move this category\'s transactions to',
                schema: { type: :string, format: :uuid }

      let(:id) { parent_category.id }

      response '204', 'category deleted' do
        run_test!
      end

      response '204', 'category deleted and transactions moved to a replacement' do
        let(:replacement_category_id) { other_category.id }

        run_test!
      end

      response '422', 'replacement category is not another category in the family' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:replacement_category_id) { parent_category.id }

        run_test!
      end

      response '403', 'forbidden - api key missing read_write scope, or guest user' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { read_only_api_key.plain_key }

        run_test!
      end

      response '404', 'category not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end
  end
end
