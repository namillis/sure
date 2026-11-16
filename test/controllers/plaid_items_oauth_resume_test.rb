require "test_helper"
require "ostruct"

class PlaidItemsOauthResumeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    plaid_provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).with(:us).returns(plaid_provider)
    plaid_provider.stubs(:get_link_token).returns(OpenStruct.new(link_token: "link-sandbox-oauth"))
  end

  test "an OAuth bank's return to accounts reopens Link with the same token and the returned URI" do
    get new_plaid_item_url(region: "us")
    assert_response :success

    get accounts_url(oauth_state_id: "state-123")
    assert_redirected_to oauth_resume_plaid_items_path(oauth_state_id: "state-123")

    follow_redirect!
    assert_response :success
    assert_select "[data-controller='plaid'][data-plaid-link-token-value='link-sandbox-oauth']"
    assert_select "[data-plaid-received-redirect-uri-value='#{accounts_url(oauth_state_id: "state-123")}']"
    assert_select "[data-plaid-is-update-value='false']"
  end

  test "accounts without an oauth_state_id or without a started link render normally" do
    get accounts_url(oauth_state_id: "state-123")
    assert_response :success

    get new_plaid_item_url(region: "us")
    get accounts_url
    assert_response :success
  end

  test "an expired resume goes back to accounts with an alert" do
    get new_plaid_item_url(region: "us")

    travel 31.minutes do
      get oauth_resume_plaid_items_url(oauth_state_id: "state-123")
    end

    assert_redirected_to accounts_path
    assert_equal I18n.t("plaid_items.oauth_resume.expired"), flash[:alert]
  end

  test "resume without a started link goes back to accounts" do
    get oauth_resume_plaid_items_url(oauth_state_id: "state-123")
    assert_redirected_to accounts_path
  end
end
