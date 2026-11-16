# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = @family.accounts.first
    @account.update!(owner: @user)
    @transaction = create_transaction(account: @account, amount: 25, name: "Receipt").entryable

    @user.api_keys.active.destroy_all
    @api_key = create_key(@user, [ "read_write" ])
    @read_only_api_key = create_key(@user, [ "read" ])
  end

  # CREATE

  test "uploads a file and returns the attachment" do
    assert_difference -> { @transaction.attachments.count }, 1 do
      post api_v1_transaction_attachments_url(@transaction),
           params: { file: pdf_upload },
           headers: api_headers(@api_key)
    end
    assert_response :created

    body = JSON.parse(response.body)
    attachment = @transaction.attachments.last
    assert_equal attachment.id, body["id"]
    assert_equal "receipt.pdf", body["filename"]
    assert_equal "application/pdf", body["content_type"]
    assert_equal attachment.byte_size, body["byte_size"]
    assert_equal api_v1_attachment_url(attachment), body["url"]
  end

  test "rejects a disallowed content type" do
    assert_no_difference -> { ActiveStorage::Attachment.count } do
      post api_v1_transaction_attachments_url(@transaction),
           params: { file: fixture_file_upload("test.txt", "text/plain") },
           headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_match "unsupported format", body["message"]
    assert_kind_of Array, body["errors"]
  end

  test "rejects an oversized file" do
    ActiveStorage::Blob.any_instance.stubs(:byte_size).returns(Transaction::MAX_ATTACHMENT_SIZE + 1)

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      post api_v1_transaction_attachments_url(@transaction),
           params: { file: pdf_upload },
           headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    assert_match "too large", JSON.parse(response.body)["message"]
  end

  test "rejects HEIC like the web does" do
    heic = Rack::Test::UploadedFile.new(StringIO.new("\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic".b),
                                        "image/heic", true, original_filename: "photo.heic")

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      post api_v1_transaction_attachments_url(@transaction), params: { file: heic }, headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    assert_match "image/heic", JSON.parse(response.body)["message"]
  end

  test "rejects an upload past the attachment limit" do
    Transaction::MAX_ATTACHMENTS_PER_TRANSACTION.times { |i| attach_pdf(name: "file#{i}.pdf") }

    assert_no_difference -> { @transaction.attachments.count } do
      post api_v1_transaction_attachments_url(@transaction),
           params: { file: pdf_upload },
           headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "rejects a request without a file" do
    post api_v1_transaction_attachments_url(@transaction),
         params: { file: "not a file" },
         headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "create requires authentication" do
    post api_v1_transaction_attachments_url(@transaction), params: { file: pdf_upload }
    assert_response :unauthorized
  end

  test "create requires a write scope" do
    post api_v1_transaction_attachments_url(@transaction),
         params: { file: pdf_upload },
         headers: api_headers(@read_only_api_key)
    assert_response :forbidden
  end

  test "a read_write share can upload but a read_only share cannot" do
    writer = shared_user("read_write")
    post api_v1_transaction_attachments_url(@transaction),
         params: { file: pdf_upload }, headers: api_headers(create_key(writer, [ "read_write" ]))
    assert_response :created

    viewer = shared_user("read_only")
    post api_v1_transaction_attachments_url(@transaction),
         params: { file: pdf_upload }, headers: api_headers(create_key(viewer, [ "read_write" ]))
    assert_response :forbidden
  end

  test "create returns 404 for another family's transaction" do
    post api_v1_transaction_attachments_url(other_family_transaction),
         params: { file: pdf_upload },
         headers: api_headers(@api_key)
    assert_response :not_found
  end

  # SHOW (download)

  test "downloads the file with an API key" do
    attachment = attach_pdf

    get api_v1_attachment_url(attachment), headers: api_headers(@read_only_api_key)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal "%PDF-1.4 receipt", response.body
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
  end

  test "download can be sent as an attachment" do
    attachment = attach_pdf

    get api_v1_attachment_url(attachment, disposition: "attachment"), headers: api_headers(@read_only_api_key)
    assert_response :success
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  end

  test "download requires authentication" do
    attachment = attach_pdf

    get api_v1_attachment_url(attachment)
    assert_response :unauthorized
    assert_not_includes response.body, "%PDF"
  end

  test "a read_only share can download" do
    attachment = attach_pdf
    viewer = shared_user("read_only")

    get api_v1_attachment_url(attachment), headers: api_headers(create_key(viewer, [ "read" ]))
    assert_response :success
  end

  test "download returns 404 for another family's attachment" do
    foreign = other_family_transaction
    foreign.attachments.attach(io: StringIO.new("secret"), filename: "secret.pdf", content_type: "application/pdf")

    get api_v1_attachment_url(foreign.attachments.first), headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "download returns 404 for an account the user cannot access" do
    attachment = attach_pdf
    outsider = User.create!(family: @family, email: "outsider-#{SecureRandom.hex(4)}@example.com",
                            password: "password123", password_confirmation: "password123", role: "member")

    get api_v1_attachment_url(attachment), headers: api_headers(create_key(outsider, [ "read" ]))
    assert_response :not_found
  end

  test "download returns 404 for a malformed id" do
    get api_v1_attachment_url("not-a-uuid"), headers: api_headers(@api_key)
    assert_response :not_found
  end

  # DESTROY

  test "deletes an attachment" do
    attachment = attach_pdf

    assert_difference -> { @transaction.attachments.count }, -1 do
      delete api_v1_transaction_attachment_url(@transaction, attachment), headers: api_headers(@api_key)
    end
    assert_response :no_content
  end

  test "destroy requires a write scope" do
    attachment = attach_pdf

    delete api_v1_transaction_attachment_url(@transaction, attachment), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
    assert @transaction.attachments.exists?(attachment.id)
  end

  test "a read_write share cannot delete" do
    attachment = attach_pdf
    writer = shared_user("read_write")

    delete api_v1_transaction_attachment_url(@transaction, attachment),
           headers: api_headers(create_key(writer, [ "read_write" ]))
    assert_response :forbidden
    assert @transaction.attachments.exists?(attachment.id)
  end

  test "a full_control share can delete" do
    attachment = attach_pdf
    manager = shared_user("full_control")

    delete api_v1_transaction_attachment_url(@transaction, attachment),
           headers: api_headers(create_key(manager, [ "read_write" ]))
    assert_response :no_content
  end

  test "destroy returns 404 for another transaction's attachment" do
    other = create_transaction(account: @account, amount: 5, name: "Other").entryable
    other.attachments.attach(io: StringIO.new("x"), filename: "x.pdf", content_type: "application/pdf")

    delete api_v1_transaction_attachment_url(@transaction, other.attachments.first), headers: api_headers(@api_key)
    assert_response :not_found
    assert other.attachments.exists?
  end

  test "destroy returns 404 for another family's transaction" do
    foreign = other_family_transaction
    foreign.attachments.attach(io: StringIO.new("secret"), filename: "secret.pdf", content_type: "application/pdf")

    delete api_v1_transaction_attachment_url(foreign, foreign.attachments.first), headers: api_headers(@api_key)
    assert_response :not_found
    assert foreign.attachments.exists?
  end

  # TRANSACTION JSON

  test "transaction json lists attachments" do
    attachment = attach_pdf

    get api_v1_transaction_url(@transaction), headers: api_headers(@read_only_api_key)
    assert_response :success

    attachments = JSON.parse(response.body)["attachments"]
    assert_equal [ attachment.id ], attachments.map { |a| a["id"] }
    assert_equal api_v1_attachment_url(attachment), attachments.first["url"]
  end

  test "transaction index lists attachments" do
    attach_pdf

    get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers(@read_only_api_key)
    assert_response :success

    row = JSON.parse(response.body)["transactions"].find { |t| t["id"] == @transaction.id }
    assert_equal 1, row["attachments"].length
  end

  test "transaction index does not query attachments per row" do
    selects = ->(&block) do
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
    list = -> { get api_v1_transactions_url, params: { account_id: @account.id, per_page: 100 }, headers: api_headers(@read_only_api_key) }

    attach_pdf
    one = selects.call(&list)
    3.times { |i| create_transaction(account: @account, amount: 1, name: "More #{i}").entryable.attachments.attach(io: StringIO.new("%PDF-1.4 x"), filename: "x.pdf", content_type: "application/pdf") }
    four = selects.call(&list)

    assert_equal one, four
  end

  private

    def create_key(user, scopes)
      key = ApiKey.create!(user: user, name: "Key #{SecureRandom.hex(3)}", scopes: scopes,
                           display_key: "test_#{SecureRandom.hex(8)}", source: scopes.include?("read_write") ? "web" : "mobile")
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def shared_user(permission)
      user = User.create!(family: @family, email: "#{permission}-#{SecureRandom.hex(4)}@example.com",
                          password: "password123", password_confirmation: "password123", role: "member")
      AccountShare.create!(account: @account, user: user, permission: permission)
      user
    end

    def other_family_transaction
      family = Family.create!(name: "Other", currency: "USD", locale: "en", date_format: "%m-%d-%Y")
      account = family.accounts.create!(name: "Other checking", balance: 0, currency: "USD", accountable: Depository.new)
      create_transaction(account: account, amount: 10, name: "Foreign").entryable
    end

    def pdf_upload
      Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 receipt"), "application/pdf", original_filename: "receipt.pdf")
    end

    def attach_pdf(name: "receipt.pdf")
      @transaction.attachments.attach(io: StringIO.new("%PDF-1.4 receipt"), filename: name, content_type: "application/pdf")
      @transaction.attachments.order(:created_at).last
    end
end
