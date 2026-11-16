# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionLocksControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = accounts(:depository)

    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(user: @user, name: "RW", scopes: [ "read_write" ],
                              display_key: "test_rw_#{SecureRandom.hex(8)}")
    @read_only_api_key = ApiKey.create!(user: @user, name: "RO", scopes: [ "read" ],
                                        display_key: "test_ro_#{SecureRandom.hex(8)}", source: "mobile")
    Redis.new.del("api_rate_limit:#{@api_key.id}")
    Redis.new.del("api_rate_limit:#{@read_only_api_key.id}")

    @entry = create_transaction(account: @account, amount: 40, name: "Locked")
    @transaction = @entry.entryable
  end

  # Transaction JSON

  test "transaction JSON lists the locked fields the web shows" do
    lock_entry

    get api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :success

    body = response.parsed_body
    assert body["sync_locked"]
    fields = body["locked_attributes"].to_h { |lock| [ lock["field"], lock["locked_at"] ] }
    assert_equal %w[category_id date], fields.keys.sort
    assert_equal Time.zone.parse(@locked_at).iso8601, fields["date"]
  end

  test "an unlocked transaction has no locks" do
    get api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    body = response.parsed_body
    assert_equal false, body["sync_locked"]
    assert_equal [], body["locked_attributes"]
  end

  test "an excluded transaction is not shown as sync locked" do
    @entry.update!(excluded: true)

    get api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_equal false, response.parsed_body["sync_locked"]
  end

  test "transaction JSON reports reconciled status and whether reconcile applies" do
    get api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_equal "unreconciled", response.parsed_body["reconciled_status"]
    assert_equal false, response.parsed_body["reconcilable"]

    @family.update!(manual_reconciliation: true)
    get api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert response.parsed_body["reconcilable"]

    linked = create_transaction(account: accounts(:connected), amount: 5).entryable
    get api_v1_transaction_url(linked), headers: api_headers(@api_key)
    assert_equal false, response.parsed_body["reconcilable"]
  end

  test "reconcilable is false on a share without write access" do
    @family.update!(manual_reconciliation: true)

    get api_v1_transaction_url(@transaction), headers: api_headers(key_for_share("read_write"))
    assert_response :success
    assert_equal false, response.parsed_body["reconcilable"]
  end

  test "index adds locks and reconcile state without a query per row" do
    @family.update!(manual_reconciliation: true)
    lock_entry
    baseline = count_db_queries do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers(@api_key)
      assert_response :success
    end

    3.times do |i|
      entry = create_transaction(account: @account, amount: 10 + i)
      entry.update!(user_modified: true, locked_attributes: { "name" => Time.current.iso8601 })
      entry.entryable.update!(locked_attributes: { "category_id" => Time.current.iso8601 })
    end
    expanded = count_db_queries do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers(@api_key)
      assert_response :success
    end

    assert_equal baseline, expanded
  end

  # unlock

  test "unlock clears the sync protection and returns the transaction" do
    lock_entry

    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :success

    body = response.parsed_body
    assert_equal @transaction.id, body["id"]
    assert_equal false, body["sync_locked"]
    assert_equal [], body["locked_attributes"]
    assert_not @entry.reload.protected_from_sync?
    assert_empty @transaction.reload.locked_attributes
  end

  test "unlock clears import_locked" do
    @entry.update!(import_locked: true)

    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :success
    assert_not @entry.reload.import_locked?
  end

  test "unlock is allowed on a full control share" do
    lock_entry

    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(key_for_share("full_control"))
    assert_response :success
  end

  test "unlock needs owner or full control" do
    lock_entry

    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(key_for_share("read_write"))
    assert_response :forbidden
    assert @entry.reload.protected_from_sync?
  end

  test "unlock is refused to a guest with a read only share" do
    lock_entry

    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(key_for_share("read_only", role: "guest"))
    assert_response :forbidden
  end

  test "unlock needs the read_write scope" do
    post unlock_api_v1_transaction_url(@transaction), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body["error"]
  end

  # reconcile

  test "reconcile cycles unreconciled, cleared, reconciled and back" do
    @family.update!(manual_reconciliation: true)

    %w[cleared reconciled unreconciled].each do |expected|
      patch reconcile_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
      assert_response :success
      assert_equal expected, response.parsed_body["reconciled_status"]
      assert_equal expected, @entry.reload.reconciled_status
    end
  end

  test "reconcile returns 422 when the family has not turned it on" do
    patch reconcile_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "reconciliation_disabled", response.parsed_body["error"]
    assert_equal "unreconciled", @entry.reload.reconciled_status
  end

  test "reconcile returns 422 on a bank-synced account" do
    @family.update!(manual_reconciliation: true)
    linked = create_transaction(account: accounts(:connected), amount: 5)

    patch reconcile_api_v1_transaction_url(linked.entryable), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "not_manual_account", response.parsed_body["error"]
    assert_equal "unreconciled", linked.reload.reconciled_status
  end

  test "reconcile returns 422 and logs when the update fails" do
    @family.update!(manual_reconciliation: true)
    Entry.any_instance.stubs(:advance_reconciled_status!).raises(ActiveRecord::RecordInvalid.new(@entry))

    assert_difference -> { DebugLogEntry.where(category: "reconciliation").count }, 1 do
      patch reconcile_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    assert_equal "reconcile_failed", response.parsed_body["error"]
  end

  test "reconcile needs owner or full control" do
    @family.update!(manual_reconciliation: true)

    patch reconcile_api_v1_transaction_url(@transaction), headers: api_headers(key_for_share("read_write"))
    assert_response :forbidden
    assert_equal "unreconciled", @entry.reload.reconciled_status
  end

  test "reconcile needs the read_write scope" do
    @family.update!(manual_reconciliation: true)

    patch reconcile_api_v1_transaction_url(@transaction), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
  end

  # Auth and tenancy

  test "both actions return 401 without an API key" do
    post unlock_api_v1_transaction_url(@transaction)
    assert_response :unauthorized
    patch reconcile_api_v1_transaction_url(@transaction)
    assert_response :unauthorized
  end

  test "another family's transaction returns 404" do
    other_account = families(:empty).accounts.create!(name: "Theirs", balance: 0, currency: "USD", accountable: Depository.new)
    theirs = create_transaction(account: other_account, amount: 5).entryable

    post unlock_api_v1_transaction_url(theirs), headers: api_headers(@api_key)
    assert_response :not_found
    patch reconcile_api_v1_transaction_url(theirs), headers: api_headers(@api_key)
    assert_response :not_found
  end

  private

    def lock_entry
      @locked_at = 2.days.ago.iso8601
      @entry.update!(user_modified: true, locked_attributes: { "date" => @locked_at })
      @transaction.update!(locked_attributes: { "category_id" => @locked_at })
    end

    def key_for_share(permission, role: "member")
      other = User.create!(family: @family, email: "share-#{SecureRandom.hex(4)}@example.com",
                           password: "password123", password_confirmation: "password123", role: role)
      AccountShare.where(account: @account, user: other).destroy_all
      AccountShare.create!(account: @account, user: other, permission: permission)
      key = ApiKey.create!(user: other, name: "Share", scopes: [ "read_write" ], display_key: "test_s_#{SecureRandom.hex(8)}")
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def count_db_queries(&block)
      queries = 0
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:cached]
        next if payload[:name].in?(%w[SCHEMA TRANSACTION])

        queries += 1
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      queries
    end
end
