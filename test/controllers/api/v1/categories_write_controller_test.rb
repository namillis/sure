# frozen_string_literal: true

require "test_helper"

class Api::V1::CategoriesWriteControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.api_keys.active.destroy_all

    @family = @user.family
    @category = categories(:food_and_drink)
    @subcategory = categories(:subcategory)
    @root = categories(:one)
    @other_family_category = families(:empty).categories.create!(name: "Elsewhere", color: "#22c55e", lucide_icon: "coffee")
  end

  test "update requires authentication" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: "Renamed" } }
    assert_response :unauthorized
  end

  test "update rejects api key without read_write scope" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: "Renamed" } }, headers: api_headers(read_only_api_key)
    assert_response :forbidden
    assert_equal "Test", @root.reload.name
  end

  test "update rejects guests" do
    guest_key = create_api_key(family_guest, %w[read_write])
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: "Renamed" } }, headers: api_headers(guest_key)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
  end

  test "update changes name, color and icon" do
    patch "/api/v1/categories/#{@root.id}",
      params: { category: { name: "Renamed", color: "#22c55e", icon: "coffee" } },
      headers: api_headers(read_write_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @root.id, body["id"]
    assert_equal "Renamed", body["name"]
    assert_equal "#22c55e", body["color"]
    assert_equal "coffee", body["icon"]
    assert_equal "coffee", @root.reload.lucide_icon
  end

  test "update keeps the icon when icon is omitted" do
    original_icon = @root.lucide_icon
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: "Renamed" } }, headers: api_headers(read_write_api_key)

    assert_response :success
    assert_equal original_icon, @root.reload.lucide_icon
  end

  test "update moves a category under a parent and back to the root" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { parent_id: @category.id } }, headers: api_headers(read_write_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @category.id, body.dig("parent", "id")
    assert_equal @category.color, body["color"]

    patch "/api/v1/categories/#{@root.id}", params: { category: { parent_id: "" } }, headers: api_headers(read_write_api_key)

    assert_response :success
    assert_nil JSON.parse(response.body)["parent"]
    assert_nil @root.reload.parent_id
  end

  test "update color on a parent propagates to subcategories" do
    patch "/api/v1/categories/#{@category.id}", params: { category: { color: "#22c55e" } }, headers: api_headers(read_write_api_key)

    assert_response :success
    assert_equal "#22c55e", @subcategory.reload.color
  end

  test "update returns 422 for a duplicate name" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: @category.name } }, headers: api_headers(read_write_api_key)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "unprocessable_entity", body["error"]
    assert_match(/Name/, body["message"])
  end

  test "update returns 422 for an invalid color" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { color: "blue" } }, headers: api_headers(read_write_api_key)

    assert_response :unprocessable_entity
    assert_equal "unprocessable_entity", JSON.parse(response.body)["error"]
  end

  test "update returns 422 when the parent belongs to another family" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { parent_id: @other_family_category.id } }, headers: api_headers(read_write_api_key)

    assert_response :unprocessable_entity
    assert_equal "Parent must be a category in your family", JSON.parse(response.body)["message"]
    assert_nil @root.reload.parent_id
  end

  test "update returns 422 when the category is its own parent" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { parent_id: @root.id } }, headers: api_headers(read_write_api_key)

    assert_response :unprocessable_entity
    assert_nil @root.reload.parent_id
  end

  test "update returns 422 when nesting would exceed two levels" do
    patch "/api/v1/categories/#{@root.id}", params: { category: { parent_id: @subcategory.id } }, headers: api_headers(read_write_api_key)
    assert_response :unprocessable_entity

    patch "/api/v1/categories/#{@category.id}", params: { category: { parent_id: @root.id } }, headers: api_headers(read_write_api_key)
    assert_response :unprocessable_entity
    assert_nil @category.reload.parent_id
  end

  test "update returns 404 for another family's category" do
    patch "/api/v1/categories/#{@other_family_category.id}", params: { category: { name: "Mine" } }, headers: api_headers(read_write_api_key)

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]
    assert_equal "Elsewhere", @other_family_category.reload.name
  end

  test "update returns 400 when the category payload is missing" do
    patch "/api/v1/categories/#{@root.id}", params: {}, headers: api_headers(read_write_api_key)
    assert_response :bad_request
  end

  test "update is allowed while categories are locked, like the web" do
    @family.update!(categories_locked: true)
    patch "/api/v1/categories/#{@root.id}", params: { category: { name: "Renamed" } }, headers: api_headers(read_write_api_key)
    assert_response :success
  end

  test "destroy requires authentication" do
    delete "/api/v1/categories/#{@root.id}"
    assert_response :unauthorized
  end

  test "destroy rejects api key without read_write scope" do
    assert_no_difference "Category.count" do
      delete "/api/v1/categories/#{@root.id}", headers: api_headers(read_only_api_key)
    end
    assert_response :forbidden
  end

  test "destroy rejects guests" do
    guest_key = create_api_key(family_guest, %w[read_write])
    assert_no_difference "Category.count" do
      delete "/api/v1/categories/#{@root.id}", headers: api_headers(guest_key)
    end
    assert_response :forbidden
  end

  test "destroy removes the category and uncategorizes its transactions" do
    transaction = transactions(:one)
    assert_equal @category.id, transaction.category_id

    delete "/api/v1/categories/#{@category.id}", headers: api_headers(read_write_api_key)

    assert_response :no_content
    assert_not Category.exists?(@category.id)
    assert_nil transaction.reload.category_id
    assert_nil @subcategory.reload.parent_id
  end

  test "destroy moves transactions to a replacement category" do
    transaction = transactions(:one)

    delete "/api/v1/categories/#{@category.id}", params: { replacement_category_id: @root.id }, headers: api_headers(read_write_api_key)

    assert_response :no_content
    assert_equal @root.id, transaction.reload.category_id
  end

  test "destroy returns 422 for a replacement outside the family or the category itself" do
    [ @other_family_category.id, @category.id ].each do |replacement_id|
      assert_no_difference "Category.count" do
        delete "/api/v1/categories/#{@category.id}", params: { replacement_category_id: replacement_id }, headers: api_headers(read_write_api_key)
      end
      assert_response :unprocessable_entity
    end
  end

  test "destroy returns 404 for another family's category" do
    assert_no_difference "Category.count" do
      delete "/api/v1/categories/#{@other_family_category.id}", headers: api_headers(read_write_api_key)
    end
    assert_response :not_found
  end

  private

    def read_write_api_key
      @read_write_api_key ||= create_api_key(@user, %w[read_write])
    end

    def read_only_api_key
      @read_only_api_key ||= create_api_key(@user, %w[read], source: "mobile")
    end

    def create_api_key(user, scopes, source: "web")
      ApiKey.create!(user: user, name: "Test #{scopes.join} Key", key: ApiKey.generate_secure_key, scopes: scopes, source: source)
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
