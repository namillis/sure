# frozen_string_literal: true

# The household list from Settings::ProfilesController#show: every member of the
# family plus its pending invitations. Invitation tokens are never included.
class Api::V1::FamilyMembersController < Api::V1::BaseController
  include Api::V1::InvitationAvailability

  before_action :ensure_read_scope

  helper_method :avatar_url_for

  def index
    @viewer = current_resource_owner
    @family = @viewer.family
    @users = @family.users.with_attached_profile_image.order(:created_at)
    @pending_invitations = @family.invitations.pending.order(:created_at)
  end

  private

    # The web's avatar is the :small variant's service URL. Private services
    # sign it with a short expiry; a public bucket would make it a permanent
    # public link, so none is returned there.
    def avatar_url_for(user)
      image = user.profile_image
      return nil unless image.attached?
      return nil if image.blob.service.public?

      image.variant(:small).url
    rescue ActiveStorage::Error
      nil
    end
end
