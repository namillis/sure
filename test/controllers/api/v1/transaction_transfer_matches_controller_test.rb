# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionTransferMatchesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @api_key = create_key(@user, [ "read_write" ])
    @read_only_api_key = create_key(@user, [ "read" ], source: "mobile")

    @outflow_entry = create_transaction(amount: 100, account: accounts(:depository), name: "Move to broker")
    @inflow_entry = create_transaction(amount: -100, account: accounts(:investment), name: "From checking")
  end

  # CANDIDATES

  test "lists the dialog's candidates and the accounts a new counterpart can go to" do
    get transfer_candidates_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@read_only_api_key)
    assert_response :success

    body = JSON.parse(response.body)
    candidate = body["candidates"].find { |c| c["transaction"]["id"] == @inflow_entry.transaction.id }
    assert candidate, "the matching inflow is offered"
    assert_equal @inflow_entry.id, candidate["transaction"]["entry_id"]
    assert_equal({ "id" => accounts(:investment).id, "name" => accounts(:investment).name }, candidate["account"])

    account_ids = body["accounts"].map { |a| a["id"] }
    assert_includes account_ids, accounts(:investment).id
    assert_not_includes account_ids, accounts(:depository).id, "never the transaction's own account"
  end

  test "candidates leave out accounts the user cannot write to" do
    loan = accounts(:loan)
    loan.update!(owner: users(:family_member))
    loan.account_shares.create!(user: @user, permission: "read_only")
    hidden = create_transaction(amount: -100, account: loan, name: "Read-only inflow")

    get transfer_candidates_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@api_key)
    assert_response :success

    body = JSON.parse(response.body)
    assert_not_includes body["candidates"].map { |c| c["transaction"]["id"] }, hidden.transaction.id
    assert_not_includes body["accounts"].map { |a| a["id"] }, loan.id
  end

  test "candidates leave out split children, which cannot be matched" do
    parent = create_transaction(amount: -100, account: accounts(:credit_card), name: "Split inflow")
    parent.split!([ { name: "A", amount: -50, category_id: nil }, { name: "B", amount: -50, category_id: nil } ])
    child_ids = parent.reload.child_entries.map(&:entryable_id)

    get transfer_candidates_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@api_key)
    assert_response :success

    offered = JSON.parse(response.body)["candidates"].map { |c| c["transaction"]["id"] }
    assert_empty offered & child_ids
  end

  # CREATE

  test "matches an existing transaction" do
    assert_difference("Transfer.count", 1) do
      post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
           params: { transfer_match: { method: "existing", matched_entry_id: @inflow_entry.id } },
           headers: api_headers(@api_key), as: :json
    end
    assert_response :created

    body = JSON.parse(response.body)
    transfer = Transfer.find(body["transfer"]["id"])
    assert transfer.confirmed?
    assert_equal @inflow_entry.transaction.id, body["inflow"]["id"]
    assert_equal @outflow_entry.transaction.id, body["outflow"]["id"]
    assert_equal transfer.id, body["inflow"]["transfer"]["id"]
    assert_equal "confirmed", body["outflow"]["transfer"]["status"]
    assert_equal "investment_contribution", body["outflow"]["kind"]
  end

  test "creates the other side in a target account" do
    assert_difference([ "Transfer.count", "Transaction.count" ], 1) do
      post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
           params: { transfer_match: { method: "new", target_account_id: accounts(:credit_card).id } },
           headers: api_headers(@api_key), as: :json
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert_equal @outflow_entry.transaction.id, body["outflow"]["id"]
    assert_equal accounts(:credit_card).id, body["inflow"]["account"]["id"]
    assert_equal "-100.0", body["inflow"]["amount_decimal"]
  end

  test "an invalid pair returns 422 with a message" do
    unrelated = create_transaction(amount: -42, account: accounts(:investment), name: "Different amount")

    assert_no_difference("Transfer.count") do
      post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
           params: { transfer_match: { method: "existing", matched_entry_id: unrelated.id } },
           headers: api_headers(@api_key), as: :json
    end
    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_equal "not_a_candidate", body["reason"]
    assert body["message"].present?
  end

  test "matching to the transaction's own account returns 422" do
    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "new", target_account_id: accounts(:depository).id } },
         headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "same_account", JSON.parse(response.body)["reason"]
  end

  test "an already matched transaction returns 422" do
    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "existing", matched_entry_id: @inflow_entry.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :created

    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "new", target_account_id: accounts(:credit_card).id } },
         headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "already_linked", JSON.parse(response.body)["reason"]
  end

  test "an unknown method or a missing body returns 422" do
    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "magic" } }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]

    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
  end

  test "a target account or matched entry from another family returns 404" do
    other_account = other_family_account
    other_entry = create_transaction(amount: -100, account: other_account)

    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "new", target_account_id: other_account.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :not_found

    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "existing", matched_entry_id: other_entry.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :not_found
  end

  test "a read-only share on either side returns 403" do
    member = users(:family_member)
    member.api_keys.active.destroy_all
    member_key = create_key(member, [ "read_write" ])
    share_with(member, accounts(:depository), "read_only")
    share_with(member, accounts(:investment), "full_control")

    assert_no_difference("Transfer.count") do
      post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
           params: { transfer_match: { method: "existing", matched_entry_id: @inflow_entry.id } },
           headers: api_headers(member_key), as: :json
    end
    assert_response :forbidden

    # Writable source, read-only target.
    assert_no_difference("Transfer.count") do
      post transfer_match_api_v1_transaction_url(@inflow_entry.transaction),
           params: { transfer_match: { method: "existing", matched_entry_id: @outflow_entry.id } },
           headers: api_headers(member_key), as: :json
    end
    assert_response :forbidden
  end

  test "a read key cannot match" do
    post transfer_match_api_v1_transaction_url(@outflow_entry.transaction),
         params: { transfer_match: { method: "existing", matched_entry_id: @inflow_entry.id } },
         headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
  end

  # DESTROY

  test "unmatching a transfer removes it and records the rejected pair" do
    transfer = Transfer::Matcher.new(@outflow_entry.transaction).match_with!(@inflow_entry.transaction)

    assert_difference("Transfer.count", -1) do
      assert_difference("RejectedTransfer.count", 1) do
        delete transfer_match_api_v1_transaction_url(@inflow_entry.transaction), headers: api_headers(@api_key)
      end
    end
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal @inflow_entry.transaction.id, body["id"]
    assert_nil body["transfer"]
    assert RejectedTransfer.exists?(inflow_transaction_id: transfer.inflow_transaction_id, outflow_transaction_id: transfer.outflow_transaction_id)
  end

  test "unmatching an unmatched transaction dismisses its transfer hint" do
    assert_difference("RejectedTransfer.count", 1) do
      delete transfer_match_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@api_key)
    end
    assert_response :success
    assert RejectedTransfer.exists?(inflow_transaction_id: @inflow_entry.transaction.id, outflow_transaction_id: @outflow_entry.transaction.id)
  end

  test "a read-only share cannot unmatch" do
    Transfer::Matcher.new(@outflow_entry.transaction).match_with!(@inflow_entry.transaction)
    member = users(:family_member)
    member.api_keys.active.destroy_all
    member_key = create_key(member, [ "read_write" ])
    share_with(member, accounts(:depository), "read_only")

    assert_no_difference([ "Transfer.count", "RejectedTransfer.count" ]) do
      delete transfer_match_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(member_key)
    end
    assert_response :forbidden
  end

  test "a read key cannot unmatch" do
    delete transfer_match_api_v1_transaction_url(@outflow_entry.transaction), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
  end

  # TRANSACTION JSON

  test "both sides of a transfer carry it, with its status" do
    transfer = Transfer.create!(inflow_transaction: @inflow_entry.transaction, outflow_transaction: @outflow_entry.transaction, status: "pending")

    [ @inflow_entry, @outflow_entry ].each do |entry|
      get api_v1_transaction_url(entry.transaction), headers: api_headers(@api_key)
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal transfer.id, body["transfer"]["id"]
      assert_equal "pending", body["transfer"]["status"]
      other = entry == @inflow_entry ? accounts(:depository) : accounts(:investment)
      assert_equal other.id, body["transfer"]["other_account"]["id"]
    end
  end

  # AUTH AND LOOKUP

  test "returns 401 without an API key" do
    get transfer_candidates_api_v1_transaction_url(@outflow_entry.transaction)
    assert_response :unauthorized
  end

  test "another family's transaction returns 404" do
    other_entry = create_transaction(amount: 100, account: other_family_account)

    get transfer_candidates_api_v1_transaction_url(other_entry.transaction), headers: api_headers(@api_key)
    assert_response :not_found
    post transfer_match_api_v1_transaction_url(other_entry.transaction),
         params: { transfer_match: { method: "new", target_account_id: accounts(:depository).id } },
         headers: api_headers(@api_key), as: :json
    assert_response :not_found
    delete transfer_match_api_v1_transaction_url(other_entry.transaction), headers: api_headers(@api_key)
    assert_response :not_found
  end

  private

    def create_key(user, scopes, source: "web")
      key = ApiKey.create!(user: user, name: "Key #{SecureRandom.hex(4)}", scopes: scopes,
                           display_key: "test_#{SecureRandom.hex(8)}", source: source)
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def share_with(user, account, permission)
      account.account_shares.find_or_initialize_by(user: user).update!(permission: permission)
    end

    def other_family_account
      families(:empty).accounts.create!(name: "Elsewhere", currency: "USD", balance: 0,
                                        accountable: Depository.new, owner: users(:empty))
    end
end
