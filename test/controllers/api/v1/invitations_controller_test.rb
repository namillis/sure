# frozen_string_literal: true

require "test_helper"

class Api::V1::InvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @family = @admin.family
    Rails.application.config.stubs(:app_mode).returns("managed".inquiry)

    @write_key = api_key_for(@admin, %w[read_write])
    @read_key = api_key_for(@admin, %w[read])
    @member_write_key = api_key_for(@member, %w[read_write])
  end

  # Members list

  test "lists members and pending invitations without tokens" do
    get api_v1_family_members_url, headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)

    member_ids = body["members"].map { |m| m["id"] }
    assert_equal @family.users.order(:created_at).pluck(:id), member_ids

    me = body["members"].find { |m| m["id"] == @admin.id }
    assert_equal @admin.display_name, me["name"]
    assert_equal @admin.email, me["email"]
    assert_equal "admin", me["role"]
    assert_nil me["avatar_url"]
    assert_equal true, me["is_current_user"]
    assert_equal false, body["members"].find { |m| m["id"] == @member.id }["is_current_user"]

    invitation_ids = body["pending_invitations"].map { |i| i["id"] }
    assert_equal @family.invitations.pending.pluck(:id).sort, invitation_ids.sort
    assert_not_includes invitation_ids, invitations(:other_family).id
    assert_equal %w[created_at email expires_at id role], body["pending_invitations"].first.keys.sort
    assert_not_includes response.body, invitations(:one).token

    assert_equal true, body["can_manage_invitations"]
    assert_equal true, body["invitations_enabled"]
    assert_equal "email", body["invitation_delivery"]
  end

  test "members list omits expired invitations and reports non-admins cannot manage" do
    invitations(:two).update_columns(expires_at: 1.day.ago)

    get api_v1_family_members_url, headers: api_headers(@member_write_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ invitations(:one).id ], body["pending_invitations"].map { |i| i["id"] }
    assert_equal false, body["can_manage_invitations"]
  end

  test "members list returns a signed avatar url from a private service" do
    @admin.profile_image.attach(io: file_fixture("profile_image.png").open, filename: "avatar.png", content_type: "image/png")
    @admin.profile_image.variant(:small).processed

    get api_v1_family_members_url, headers: api_headers(@read_key)

    assert_response :success
    me = JSON.parse(response.body)["members"].find { |m| m["id"] == @admin.id }
    assert_includes me["avatar_url"], "/rails/active_storage/disk/"
  end

  test "members list hides avatar urls from a public service" do
    @admin.profile_image.attach(io: file_fixture("profile_image.png").open, filename: "avatar.png", content_type: "image/png")
    @admin.profile_image.variant(:small).processed
    ActiveStorage::Service::DiskService.any_instance.stubs(:public?).returns(true)

    get api_v1_family_members_url, headers: api_headers(@read_key)

    me = JSON.parse(response.body)["members"].find { |m| m["id"] == @admin.id }
    assert_nil me["avatar_url"]
  end

  test "members list reports link-only delivery and closed sign-up on self-hosted instances" do
    with_self_hosting do
      Setting.stubs(:onboarding_state).returns("closed")

      get api_v1_family_members_url, headers: api_headers(@read_key)

      body = JSON.parse(response.body)
      assert_equal false, body["invitations_enabled"]
      assert_equal "link_only", body["invitation_delivery"]
    end
  end

  test "members list requires authentication" do
    get api_v1_family_members_url
    assert_response :unauthorized
  end

  # Create

  test "admin creates an invitation and the invitation email is sent" do
    assert_difference("Invitation.count") do
      assert_enqueued_email_with InvitationMailer, :invite_email, args: ->(args) { args.first.email == "new@example.com" } do
        post api_v1_invitations_url,
             params: { invitation: { email: "New@Example.com", role: "member" } },
             headers: api_headers(@write_key), as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    invitation = @family.invitations.find(body["id"])
    assert_equal "new@example.com", body["email"]
    assert_equal "member", body["role"]
    assert_equal "email", body["delivery"]
    assert_equal @admin, invitation.inviter
    assert_not body.key?("token")
    assert_not_includes response.body, invitation.token
  end

  test "self-hosted create sends no email and reports link-only delivery" do
    with_self_hosting do
      assert_difference("Invitation.count") do
        assert_no_enqueued_emails do
          post api_v1_invitations_url,
               params: { invitation: { email: "selfhost@example.com", role: "guest" } },
               headers: api_headers(@write_key), as: :json
        end
      end

      assert_response :created
      assert_equal "link_only", JSON.parse(response.body)["delivery"]
    end
  end

  test "create returns 422 invitations_disabled when the instance is closed to sign-ups" do
    with_self_hosting do
      Setting.stubs(:onboarding_state).returns("closed")

      assert_no_difference("Invitation.count") do
        post api_v1_invitations_url,
             params: { invitation: { email: "closed@example.com", role: "member" } },
             headers: api_headers(@write_key), as: :json
      end

      assert_response :unprocessable_entity
      assert_equal "invitations_disabled", JSON.parse(response.body)["error"]
    end
  end

  test "create returns 422 for a duplicate pending invitation" do
    assert_no_difference("Invitation.count") do
      assert_no_enqueued_emails do
        post api_v1_invitations_url,
             params: { invitation: { email: invitations(:one).email, role: "member" } },
             headers: api_headers(@write_key), as: :json
      end
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_match(/already been invited/, body["message"])
  end

  test "create returns 422 for an existing household member" do
    assert_no_difference("Invitation.count") do
      post api_v1_invitations_url,
           params: { invitation: { email: @member.email.upcase, role: "member" } },
           headers: api_headers(@write_key), as: :json
    end

    assert_response :unprocessable_entity
    assert_match(/already a member/, JSON.parse(response.body)["message"])
  end

  test "create returns 422 for a bad email, a bad role and the admin's own email" do
    [
      { email: "not-an-email", role: "member" },
      { email: "fine@example.com", role: "owner" },
      { email: @admin.email, role: "member" }
    ].each do |attributes|
      assert_no_difference("Invitation.count") do
        post api_v1_invitations_url, params: { invitation: attributes }, headers: api_headers(@write_key), as: :json
      end
      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_equal "validation_failed", body["error"]
      assert body["message"].present?
    end
  end

  test "create answers like any invitation for an email with an account in another family" do
    assert_difference("Invitation.count") do
      post api_v1_invitations_url,
           params: { invitation: { email: users(:empty).email, role: "member" } },
           headers: api_headers(@write_key), as: :json
    end

    assert_response :created
    assert_equal users(:empty).family_id, users(:empty).reload.family_id
  end

  test "create requires an admin" do
    assert_no_difference("Invitation.count") do
      post api_v1_invitations_url,
           params: { invitation: { email: "new@example.com", role: "member" } },
           headers: api_headers(@member_write_key), as: :json
    end

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
  end

  test "create requires the read_write scope" do
    post api_v1_invitations_url,
         params: { invitation: { email: "new@example.com", role: "member" } },
         headers: api_headers(@read_key), as: :json

    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
  end

  test "create requires authentication" do
    post api_v1_invitations_url, params: { invitation: { email: "new@example.com", role: "member" } }, as: :json
    assert_response :unauthorized
  end

  # Bulk create

  test "bulk create invites each address and reports per-email results" do
    assert_difference("Invitation.count", 2) do
      assert_enqueued_emails 2 do
        post api_v1_bulk_invitations_url,
             params: { bulk_invitation: { emails: [ "a@example.com", "b@example.com", invitations(:one).email ], role: "member" } },
             headers: api_headers(@write_key), as: :json
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["sent"]
    assert_equal 1, body["invalid"]
    assert_equal %w[sent sent invalid], body["results"].map { |r| r["status"] }
  end

  test "bulk create accepts the web's comma separated string" do
    assert_difference("Invitation.count", 2) do
      post api_v1_bulk_invitations_url,
           params: { bulk_invitation: { emails: "c@example.com, d@example.com", role: "guest" } },
           headers: api_headers(@write_key), as: :json
    end
    assert_response :success
  end

  test "bulk create refuses the admin role, empty lists and oversized batches" do
    post api_v1_bulk_invitations_url,
         params: { bulk_invitation: { emails: [ "a@example.com" ], role: "admin" } },
         headers: api_headers(@write_key), as: :json
    assert_response :unprocessable_entity

    post api_v1_bulk_invitations_url,
         params: { bulk_invitation: { emails: [], role: "member" } },
         headers: api_headers(@write_key), as: :json
    assert_response :unprocessable_entity

    too_many = (1..(BulkInvitation::MAX_BULK_INVITES + 1)).map { |i| "u#{i}@example.com" }
    assert_no_difference("Invitation.count") do
      post api_v1_bulk_invitations_url,
           params: { bulk_invitation: { emails: too_many, role: "member" } },
           headers: api_headers(@write_key), as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "too_many", JSON.parse(response.body)["error"]
  end

  test "bulk create requires an admin and an open instance" do
    post api_v1_bulk_invitations_url,
         params: { bulk_invitation: { emails: [ "a@example.com" ], role: "member" } },
         headers: api_headers(@member_write_key), as: :json
    assert_response :forbidden

    with_self_hosting do
      Setting.stubs(:onboarding_state).returns("closed")
      post api_v1_bulk_invitations_url,
           params: { bulk_invitation: { emails: [ "a@example.com" ], role: "member" } },
           headers: api_headers(@write_key), as: :json
      assert_response :unprocessable_entity
      assert_equal "invitations_disabled", JSON.parse(response.body)["error"]
    end
  end

  # Destroy

  test "admin revokes an invitation" do
    assert_difference("Invitation.count", -1) do
      delete api_v1_invitation_url(invitations(:one)), headers: api_headers(@write_key)
    end
    assert_response :no_content
  end

  test "revoking another family's invitation returns 404" do
    assert_no_difference("Invitation.count") do
      delete api_v1_invitation_url(invitations(:other_family)), headers: api_headers(@write_key)
    end
    assert_response :not_found

    delete api_v1_invitation_url("not-a-uuid"), headers: api_headers(@write_key)
    assert_response :not_found
  end

  test "revoke requires an admin and the read_write scope" do
    delete api_v1_invitation_url(invitations(:one)), headers: api_headers(@member_write_key)
    assert_response :forbidden

    delete api_v1_invitation_url(invitations(:one)), headers: api_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
  end

  private

    def api_key_for(user, scopes)
      key = ApiKey.create!(
        user: user,
        name: "Test #{scopes.join} #{SecureRandom.hex(3)}",
        scopes: scopes,
        source: "web",
        display_key: "test_#{SecureRandom.hex(12)}"
      )
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end
end
