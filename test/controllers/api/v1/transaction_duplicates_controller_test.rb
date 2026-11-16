# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionDuplicatesControllerTest < ActionDispatch::IntegrationTest
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

    @posted_entry = create_transaction(account: @account, amount: 50, name: "STARBUCKS CORP", date: 1.day.ago.to_date)
    @pending_entry = create_pending_transaction(account: @account, amount: 50, name: "Starbucks pending", date: 3.days.ago.to_date)
    @pending = @pending_entry.entryable
  end

  # Transaction JSON

  test "transaction JSON shows the suggested duplicate the web banner shows" do
    suggest_duplicate

    get api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert_response :success

    body = response.parsed_body
    assert body["pending"]
    assert body["duplicate_suspected"]
    assert_equal "medium", body["duplicate_confidence"]
    candidate = body["duplicate_candidate"]
    assert_equal @posted_entry.entryable_id, candidate["id"]
    assert_equal @posted_entry.id, candidate["entry_id"]
    assert_equal "STARBUCKS CORP", candidate["name"]
    assert_equal @posted_entry.date.iso8601, candidate["date"]
    assert_equal 5000, candidate["amount_cents"]
    assert_equal(-5000, candidate["signed_amount_cents"])
    assert_equal "USD", candidate["currency"]
  end

  test "transaction JSON has no duplicate once the suggestion is dismissed" do
    suggest_duplicate(dismissed: true)

    get api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    body = response.parsed_body
    assert_equal false, body["duplicate_suspected"]
    assert_nil body["duplicate_confidence"]
    assert_nil body["duplicate_candidate"]
  end

  test "a suggested match in another account is not shown" do
    other_account = @family.accounts.create!(name: "Other", balance: 0, currency: "USD", accountable: Depository.new, owner: @user)
    elsewhere = create_transaction(account: other_account, amount: 50)
    suggest_duplicate(entry: elsewhere)

    get api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert response.parsed_body["duplicate_suspected"]
    assert_nil response.parsed_body["duplicate_candidate"]
  end

  test "index loads suggested duplicates without a query per row" do
    suggest_duplicate
    baseline = count_db_queries do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers(@api_key)
      assert_response :success
    end

    3.times do |i|
      posted = create_transaction(account: @account, amount: 20 + i)
      pending = create_pending_transaction(account: @account, amount: 20 + i).entryable
      suggest_duplicate(transaction: pending, entry: posted)
    end
    expanded = count_db_queries do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers(@api_key)
      assert_response :success
    end

    assert_equal baseline, expanded
    suspected = response.parsed_body["transactions"].select { |t| t["duplicate_suspected"] }
    assert_equal 4, suspected.size
    assert suspected.all? { |t| t["duplicate_candidate"].present? }
  end

  # merge_duplicate

  test "merge_duplicate merges into the posted transaction and returns it" do
    suggest_duplicate

    assert_difference "Entry.count", -1 do
      post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    end
    assert_response :success
    assert_equal @posted_entry.entryable_id, response.parsed_body["id"]
    assert_nil Entry.find_by(id: @pending_entry.id)
  end

  test "merge_duplicate returns 422 when there is no suggestion" do
    post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "no_duplicate", response.parsed_body["error"]
  end

  test "merge_duplicate returns 422 for a posted transaction" do
    post merge_duplicate_api_v1_transaction_url(@posted_entry.entryable), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "not_pending", response.parsed_body["error"]
  end

  test "merge_duplicate returns 422 when the model refuses the merge" do
    suggest_duplicate
    Transaction.any_instance.stubs(:merge_with_duplicate!).returns(false)

    post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "merge_failed", response.parsed_body["error"]
    assert Entry.exists?(@pending_entry.id)
  end

  test "merge_duplicate needs owner or full control" do
    suggest_duplicate
    key = key_for_share("read_write")

    post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(key)
    assert_response :forbidden
    assert Entry.exists?(@pending_entry.id)
  end

  test "merge_duplicate is allowed on a full control share" do
    suggest_duplicate
    key = key_for_share("full_control")

    post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(key)
    assert_response :success
  end

  test "merge_duplicate needs the read_write scope" do
    suggest_duplicate
    post merge_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body["error"]
  end

  # dismiss_duplicate

  test "dismiss_duplicate keeps both and returns the transaction" do
    suggest_duplicate

    post dismiss_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert_response :success
    assert_equal @pending.id, response.parsed_body["id"]
    assert_equal false, response.parsed_body["duplicate_suspected"]
    assert @pending.reload.potential_duplicate_dismissed?
    assert Entry.exists?(@posted_entry.id)
  end

  test "dismiss_duplicate returns 422 when there is no suggestion" do
    post dismiss_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "no_duplicate", response.parsed_body["error"]
  end

  test "dismiss_duplicate needs owner or full control" do
    suggest_duplicate
    post dismiss_duplicate_api_v1_transaction_url(@pending), headers: api_headers(key_for_share("read_write"))
    assert_response :forbidden
    assert_not @pending.reload.potential_duplicate_dismissed?
  end

  test "dismiss_duplicate needs the read_write scope" do
    suggest_duplicate
    post dismiss_duplicate_api_v1_transaction_url(@pending), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
  end

  # pending_merge_candidates

  test "pending_merge_candidates lists posted transactions in the same account" do
    pending_elsewhere = create_pending_transaction(account: @account, amount: 9)
    euro = create_transaction(account: @account, amount: 9, currency: "EUR")

    get pending_merge_candidates_api_v1_transaction_url(@pending), headers: api_headers(@read_only_api_key)
    assert_response :success

    ids = response.parsed_body["candidates"].map { |t| t["entry_id"] }
    assert_includes ids, @posted_entry.id
    assert_not_includes ids, @pending_entry.id
    assert_not_includes ids, pending_elsewhere.id
    assert_not_includes ids, euro.id
    assert_equal 0, response.parsed_body["pagination"]["offset"]
    assert_equal 10, response.parsed_body["pagination"]["limit"]
  end

  test "pending_merge_candidates pages by offset" do
    12.times { |i| create_transaction(account: @account, amount: 1 + i) }

    get pending_merge_candidates_api_v1_transaction_url(@pending), headers: api_headers(@api_key)
    first_page = response.parsed_body
    assert_equal 10, first_page["candidates"].size
    assert first_page["pagination"]["has_more"]

    get pending_merge_candidates_api_v1_transaction_url(@pending), params: { offset: 10 }, headers: api_headers(@api_key)
    second_ids = response.parsed_body["candidates"].map { |t| t["id"] }
    assert_empty second_ids & first_page["candidates"].map { |t| t["id"] }
  end

  test "pending_merge_candidates returns 422 for a posted transaction" do
    get pending_merge_candidates_api_v1_transaction_url(@posted_entry.entryable), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "not_pending", response.parsed_body["error"]
  end

  # pending_merge

  test "pending_merge merges into the chosen posted transaction" do
    assert_difference "Entry.count", -1 do
      post pending_merge_api_v1_transaction_url(@pending),
           params: { pending_merge: { posted_entry_id: @posted_entry.id } }, headers: api_headers(@api_key), as: :json
    end
    assert_response :success
    assert_equal @posted_entry.entryable_id, response.parsed_body["id"]
  end

  test "pending_merge is allowed on a read_write share, like the web" do
    key = key_for_share("read_write")

    post pending_merge_api_v1_transaction_url(@pending),
         params: { pending_merge: { posted_entry_id: @posted_entry.id } }, headers: api_headers(key), as: :json
    assert_response :success
  end

  test "pending_merge is refused on a read_only share" do
    key = key_for_share("read_only", role: "guest")

    post pending_merge_api_v1_transaction_url(@pending),
         params: { pending_merge: { posted_entry_id: @posted_entry.id } }, headers: api_headers(key), as: :json
    assert_response :forbidden
    assert Entry.exists?(@pending_entry.id)
  end

  test "pending_merge returns 422 without a posted entry" do
    post pending_merge_api_v1_transaction_url(@pending), params: { pending_merge: { posted_entry_id: "" } },
         headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "pending_merge returns 422 for an entry that is not a candidate" do
    other_account = @family.accounts.create!(name: "Other", balance: 0, currency: "USD", accountable: Depository.new, owner: @user)
    elsewhere = create_transaction(account: other_account, amount: 50)

    [ elsewhere.id, @pending_entry.id, "not-a-uuid" ].each do |id|
      post pending_merge_api_v1_transaction_url(@pending), params: { pending_merge: { posted_entry_id: id } },
           headers: api_headers(@api_key), as: :json
      assert_response :unprocessable_entity
      assert_equal "invalid_posted_entry", response.parsed_body["error"]
    end
    assert Entry.exists?(@pending_entry.id)
  end

  test "pending_merge returns 422 for a posted transaction" do
    post pending_merge_api_v1_transaction_url(@posted_entry.entryable),
         params: { pending_merge: { posted_entry_id: @pending_entry.id } }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "not_pending", response.parsed_body["error"]
  end

  test "pending_merge needs the read_write scope" do
    post pending_merge_api_v1_transaction_url(@pending),
         params: { pending_merge: { posted_entry_id: @posted_entry.id } }, headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden
  end

  # Auth and tenancy

  test "every action returns 401 without an API key" do
    post merge_duplicate_api_v1_transaction_url(@pending)
    assert_response :unauthorized
    post dismiss_duplicate_api_v1_transaction_url(@pending)
    assert_response :unauthorized
    get pending_merge_candidates_api_v1_transaction_url(@pending)
    assert_response :unauthorized
    post pending_merge_api_v1_transaction_url(@pending)
    assert_response :unauthorized
  end

  test "another family's transaction returns 404" do
    other_family = families(:empty)
    other_account = other_family.accounts.create!(name: "Theirs", balance: 0, currency: "USD", accountable: Depository.new)
    theirs = create_pending_transaction(account: other_account, amount: 5).entryable

    post merge_duplicate_api_v1_transaction_url(theirs), headers: api_headers(@api_key)
    assert_response :not_found
    post dismiss_duplicate_api_v1_transaction_url(theirs), headers: api_headers(@api_key)
    assert_response :not_found
    get pending_merge_candidates_api_v1_transaction_url(theirs), headers: api_headers(@api_key)
    assert_response :not_found
    post pending_merge_api_v1_transaction_url(theirs), params: { pending_merge: { posted_entry_id: @posted_entry.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :not_found
  end

  private

    def create_pending_transaction(attributes = {})
      entry = create_transaction(attributes)
      entry.entryable.update!(extra: { "simplefin" => { "pending" => true } })
      entry
    end

    def suggest_duplicate(transaction: @pending, entry: @posted_entry, dismissed: false)
      transaction.update!(extra: transaction.extra.merge(
        "potential_posted_match" => {
          "entry_id" => entry.id, "reason" => "fuzzy_amount_match", "posted_amount" => entry.amount.to_s,
          "confidence" => "medium", "detected_at" => Date.current.to_s, "dismissed" => dismissed
        }
      ))
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
