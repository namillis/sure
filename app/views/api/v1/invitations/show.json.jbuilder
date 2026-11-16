# frozen_string_literal: true

json.partial! "api/v1/invitations/invitation", invitation: @invitation
json.delivery invitation_delivery
