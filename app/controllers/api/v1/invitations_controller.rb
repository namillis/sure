# frozen_string_literal: true

# API counterpart of InvitationsController#create, #bulk_create and #destroy:
# the same Invitation and BulkInvitation models, the same admin-only rule and
# the same InvitationMailer delivery. Accepting stays on the web.
class Api::V1::InvitationsController < Api::V1::BaseController
  include Api::V1::InvitationAvailability

  before_action -> { authorize_scope!(:read_write) }
  before_action :require_admin
  before_action :require_invitations_enabled, only: %i[create bulk_create]

  def create
    invitation = family.invitations.build(params.require(:invitation).permit(:email, :role))
    invitation.inviter = current_resource_owner

    if invitation.email.present? && family.users.find_by_email_with_legacy_fallback(invitation.email)
      return render_invitation_error("This person is already a member of your household.")
    end

    unless save_invitation(invitation)
      message = invitation.errors.of_kind?(:email, :own_email) ? I18n.t("invitations.create.own_email") : invitation.errors.full_messages.to_sentence
      return render_invitation_error(message.presence || I18n.t("invitations.create.failure"), invitation.errors.full_messages)
    end

    InvitationMailer.invite_email(invitation).deliver_later unless self_hosted?

    @invitation = invitation
    render :show, status: :created
  end

  def bulk_create
    bulk_params = params.require(:bulk_invitation)
    return render_bad_bulk_shape unless bulk_params.is_a?(ActionController::Parameters)

    role = bulk_params[:role]
    unless ::InvitationsController::BULK_INVITE_ROLES.include?(role)
      return render_invitation_error(I18n.t("invitations.bulk_create.invalid_role"))
    end

    emails = bulk_params[:emails]
    emails = emails.join(",") if emails.is_a?(Array)

    bulk = BulkInvitation.new(
      family: family,
      inviter: current_resource_owner,
      role: role,
      emails: emails.is_a?(String) ? emails : nil,
      self_hosted: self_hosted?
    )

    if bulk.over_limit?
      return render_json({ error: "too_many", message: I18n.t("invitations.bulk_create.too_many", max: BulkInvitation::MAX_BULK_INVITES),
                           errors: [] }, status: :unprocessable_entity)
    end
    return render_invitation_error(I18n.t("invitations.bulk_create.no_emails")) if bulk.emails.empty?

    bulk.process

    render_json({
      sent: bulk.sent,
      link_only: bulk.link_only,
      invalid: bulk.invalid,
      results: bulk.results.map { |result| { email: result.email, status: result.status.to_s, detail: result.detail } }
    })
  end

  def destroy
    raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

    family.invitations.find(params[:id]).destroy!
    head :no_content
  end

  private

    def family
      current_resource_owner.family
    end

    def require_admin
      return if current_resource_owner.admin?

      render_json({ error: "forbidden", message: I18n.t("invitations.destroy.not_authorized") }, status: :forbidden)
    end

    def require_invitations_enabled
      return if invitations_enabled?

      render_json({
        error: "invitations_disabled",
        message: "This server is closed to new sign-ups, so invitations can't be accepted.",
        errors: []
      }, status: :unprocessable_entity)
    end

    def render_invitation_error(message, errors = [ message ])
      render_json({ error: "validation_failed", message: message, errors: errors }, status: :unprocessable_entity)
    end

    def render_bad_bulk_shape
      render_invitation_error("bulk_invitation must be an object with emails and role")
    end

    # Mirrors InvitationsController#save_invitation: a double submit that races
    # past the duplicate validation hits the partial unique index instead.
    def save_invitation(invitation)
      invitation.save
    rescue ActiveRecord::RecordNotUnique
      invitation.errors.add(:email, "has already been invited to this family")
      false
    end
end
