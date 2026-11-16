# frozen_string_literal: true

module Api::V1::InvitationAvailability
  extend ActiveSupport::Concern

  included do
    helper_method :invitations_enabled?, :invitation_delivery
  end

  private

    # RegistrationsController#ensure_signup_open turns away every signup on a
    # self-hosted instance whose onboarding is closed, invitation links
    # included, so an invitation created there could never be accepted.
    def invitations_enabled?
      !(self_hosted? && Setting.onboarding_state == "closed")
    end

    # Self-hosted instances send no invitation email (InvitationsController
    # #create); the admin shares the accept link from the web profile page.
    def invitation_delivery
      self_hosted? ? "link_only" : "email"
    end
end
