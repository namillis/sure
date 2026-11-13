# frozen_string_literal: true

require "test_helper"

class Api::V1::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @family = @admin.family
    @family.update!(currency: "USD", country: "US", timezone: "America/New_York", date_format: "%m-%d-%Y", locale: "en")
    [ @admin, @member ].each { |user| user.api_keys.active.destroy_all }

    @admin_key = create_key(@admin, [ "read_write" ])
    @read_only_key = create_key(@admin, [ "read" ])
    @member_key = create_key(@member, [ "read_write" ])
  end

  test "show requires authentication" do
    get "/api/v1/users/me"
    assert_response :unauthorized
  end

  test "show returns the current user and family preferences" do
    get "/api/v1/users/me", headers: api_headers(@read_only_key)

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal @admin.id, body["id"]
    assert_equal @admin.email, body["email"]
    assert_equal "Bob", body["first_name"]
    assert_equal "Dylan", body["last_name"]
    assert_equal "admin", body["role"]
    assert_equal @admin.theme, body["theme"]
    assert_equal @admin.default_period, body["default_period"]
    assert_equal true, body["can_edit_family"]
    assert_equal({ "id" => @family.id, "name" => @family.name, "currency" => "USD", "country" => "US",
                   "timezone" => "America/New_York", "date_format" => "%m-%d-%Y", "locale" => "en" }, body["family"])
  end

  test "show reports non-admins cannot edit family" do
    get "/api/v1/users/me", headers: api_headers(@member_key)

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal @member.id, body["id"]
    assert_equal false, body["can_edit_family"]
  end

  test "update requires authentication" do
    patch "/api/v1/users/me", params: { user: { first_name: "X" } }, as: :json
    assert_response :unauthorized
  end

  test "update rejects read-only key" do
    patch "/api/v1/users/me", params: { user: { first_name: "X" } }, headers: api_headers(@read_only_key), as: :json

    assert_response :forbidden
    assert_equal "Bob", @admin.reload.first_name
  end

  test "update changes user fields" do
    patch "/api/v1/users/me",
          params: { user: { first_name: "Robert", last_name: "Zimmerman", locale: "fr", theme: "dark", default_period: "last_90_days" } },
          headers: api_headers(@admin_key), as: :json

    assert_response :ok
    @admin.reload
    assert_equal [ "Robert", "Zimmerman", "fr", "dark", "last_90_days" ],
                 [ @admin.first_name, @admin.last_name, @admin.locale, @admin.theme, @admin.default_period ]
    body = JSON.parse(response.body)
    assert_equal "Robert", body["first_name"]
    assert_equal "dark", body["theme"]
  end

  test "admin updates family fields" do
    patch "/api/v1/users/me",
          params: { user: { family_attributes: { currency: "EUR", country: "FR", timezone: "Europe/Paris", date_format: "%d.%m.%Y", locale: "fr" } } },
          headers: api_headers(@admin_key), as: :json

    assert_response :ok
    @family.reload
    assert_equal [ "EUR", "FR", "Europe/Paris", "%d.%m.%Y", "fr" ],
                 [ @family.currency, @family.country, @family.timezone, @family.date_format, @family.locale ]
    assert_equal "EUR", JSON.parse(response.body).dig("family", "currency")
  end

  test "member can update own fields" do
    patch "/api/v1/users/me", params: { user: { first_name: "Jake" } }, headers: api_headers(@member_key), as: :json

    assert_response :ok
    assert_equal "Jake", @member.reload.first_name
  end

  test "member cannot update family fields" do
    patch "/api/v1/users/me",
          params: { user: { first_name: "Jake", family_attributes: { currency: "EUR" } } },
          headers: api_headers(@member_key), as: :json

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
    assert_equal "USD", @family.reload.currency
    assert_equal "Jakob", @member.reload.first_name
  end

  test "security fields are ignored" do
    original_digest = @admin.password_digest

    patch "/api/v1/users/me",
          params: { user: { first_name: "Robert", email: "new@example.com", password: "newpassword123",
                            role: "super_admin", otp_required: true, family_attributes: { moniker: "Group" } } },
          headers: api_headers(@admin_key), as: :json

    assert_response :ok
    @admin.reload
    assert_equal "Robert", @admin.first_name
    assert_equal "bob@bobdylan.com", @admin.email
    assert_nil @admin.unconfirmed_email
    assert_equal original_digest, @admin.password_digest
    assert_equal "admin", @admin.role
    assert_not @admin.otp_required?
    assert_not_equal "Group", @family.reload.moniker
  end

  test "update returns validation errors" do
    patch "/api/v1/users/me", params: { user: { default_period: "forever" } }, headers: api_headers(@admin_key), as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert body["errors"].any?
    assert_equal "last_30_days", @admin.reload.default_period
  end

  test "update returns family validation errors" do
    patch "/api/v1/users/me", params: { user: { family_attributes: { date_format: "nope" } } },
          headers: api_headers(@admin_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
    assert_equal "%m-%d-%Y", @family.reload.date_format
  end

  test "update rejects unknown theme" do
    patch "/api/v1/users/me", params: { user: { theme: "neon" } }, headers: api_headers(@admin_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
    assert_not_equal "neon", @admin.reload.theme
  end

  test "update without user params is a bad request" do
    patch "/api/v1/users/me", params: {}, headers: api_headers(@admin_key), as: :json

    assert_response :bad_request
  end

  private

    def create_key(user, scopes)
      ApiKey.create!(
        user: user,
        name: "Profile Key #{scopes.join}",
        scopes: scopes,
        source: "web",
        display_key: "test_profile_#{SecureRandom.hex(8)}"
      )
    end
end
