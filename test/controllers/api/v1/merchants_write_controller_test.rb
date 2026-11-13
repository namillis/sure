# frozen_string_literal: true

require "test_helper"

class Api::V1::MerchantsWriteControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.api_keys.active.destroy_all

    @merchant = merchants(:netflix)
    @other_family_merchant = families(:empty).merchants.create!(name: "Elsewhere")
  end

  test "update requires authentication" do
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: "Renamed" } }
    assert_response :unauthorized
  end

  test "update rejects api key without read_write scope" do
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: "Renamed" } }, headers: api_headers(read_only_api_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
    assert_equal "Netflix", @merchant.reload.name
  end

  test "update rejects guests" do
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: "Renamed" } }, headers: api_headers(create_api_key(family_guest, %w[read_write]))
    assert_response :forbidden
    assert_equal "Netflix", @merchant.reload.name
  end

  test "update changes name, color and website" do
    patch "/api/v1/merchants/#{@merchant.id}",
      params: { merchant: { name: "Netflix Inc", color: "#4da568", website_url: "netflix.com" } },
      headers: api_headers(read_write_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @merchant.id, body["id"]
    assert_equal "Netflix Inc", body["name"]
    assert_equal "FamilyMerchant", body["type"]
    assert_equal "#4da568", body["color"]
    assert_equal "netflix.com", body["website_url"]
    assert_equal "Netflix Inc", @merchant.reload.name
  end

  test "family members who are not admins can update family merchants, like the web" do
    member_key = create_api_key(users(:family_member), %w[read_write])
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: "Renamed" } }, headers: api_headers(member_key)
    assert_response :success
  end

  test "update returns 422 for a duplicate name" do
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: merchants(:amazon).name } }, headers: api_headers(read_write_api_key)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_kind_of Array, body["errors"]
    assert_match(/Name/, body["message"])
  end

  test "update returns 422 for a blank name" do
    patch "/api/v1/merchants/#{@merchant.id}", params: { merchant: { name: "" } }, headers: api_headers(read_write_api_key)
    assert_response :unprocessable_entity
    assert_equal "Netflix", @merchant.reload.name
  end

  test "update returns 400 when the merchant payload is missing" do
    patch "/api/v1/merchants/#{@merchant.id}", params: {}, headers: api_headers(read_write_api_key)
    assert_response :bad_request
  end

  test "update returns 403 for a provider merchant on the family's transactions" do
    provider_merchant = assign_provider_merchant

    patch "/api/v1/merchants/#{provider_merchant.id}", params: { merchant: { name: "Mine" } }, headers: api_headers(read_write_api_key)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error"]
    assert_match(/Provider merchants are read-only/, body["message"])
    assert_equal "Coffee Co", provider_merchant.reload.name
  end

  test "update returns 404 for a provider merchant the user's accounts don't use" do
    provider_merchant = ProviderMerchant.create!(name: "Coffee Co", source: "plaid")

    patch "/api/v1/merchants/#{provider_merchant.id}", params: { merchant: { name: "Mine" } }, headers: api_headers(read_write_api_key)
    assert_response :not_found
  end

  test "update returns 404 for another family's merchant" do
    patch "/api/v1/merchants/#{@other_family_merchant.id}", params: { merchant: { name: "Mine" } }, headers: api_headers(read_write_api_key)

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]
    assert_equal "Elsewhere", @other_family_merchant.reload.name
  end

  test "destroy requires authentication" do
    delete "/api/v1/merchants/#{@merchant.id}"
    assert_response :unauthorized
  end

  test "destroy rejects api key without read_write scope" do
    assert_no_difference "Merchant.count" do
      delete "/api/v1/merchants/#{@merchant.id}", headers: api_headers(read_only_api_key)
    end
    assert_response :forbidden
  end

  test "destroy rejects guests" do
    assert_no_difference "Merchant.count" do
      delete "/api/v1/merchants/#{@merchant.id}", headers: api_headers(create_api_key(family_guest, %w[read_write]))
    end
    assert_response :forbidden
  end

  test "destroy removes the family merchant and clears it from transactions" do
    merchant = merchants(:amazon)
    transaction = transactions(:one)
    assert_equal merchant.id, transaction.merchant_id

    delete "/api/v1/merchants/#{merchant.id}", headers: api_headers(read_write_api_key)

    assert_response :no_content
    assert_not Merchant.exists?(merchant.id)
    assert_nil transaction.reload.merchant_id
  end

  test "destroy returns 403 for a provider merchant and keeps it linked" do
    provider_merchant = assign_provider_merchant

    assert_no_difference "Merchant.count" do
      delete "/api/v1/merchants/#{provider_merchant.id}", headers: api_headers(read_write_api_key)
    end

    assert_response :forbidden
    assert_equal provider_merchant.id, @provider_transaction.reload.merchant_id
  end

  test "destroy returns 404 for another family's merchant" do
    assert_no_difference "Merchant.count" do
      delete "/api/v1/merchants/#{@other_family_merchant.id}", headers: api_headers(read_write_api_key)
    end
    assert_response :not_found
  end

  private

    def assign_provider_merchant
      provider_merchant = ProviderMerchant.create!(name: "Coffee Co", source: "plaid")
      @provider_transaction = Transaction.joins(entry: :account).merge(@user.accessible_accounts).first
      @provider_transaction.update!(merchant: provider_merchant)
      provider_merchant
    end

    def read_write_api_key
      @read_write_api_key ||= create_api_key(@user, %w[read_write])
    end

    def read_only_api_key
      @read_only_api_key ||= create_api_key(@user, %w[read], source: "mobile")
    end

    def create_api_key(user, scopes, source: "web")
      user.api_keys.active.where(source: source).destroy_all
      ApiKey.create!(user: user, name: "Test #{scopes.join} Key", key: ApiKey.generate_secure_key, scopes: scopes, source: source)
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
