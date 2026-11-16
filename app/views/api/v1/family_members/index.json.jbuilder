# frozen_string_literal: true

json.members @users do |user|
  json.id user.id
  json.name user.display_name
  json.email user.email
  json.role user.role
  json.avatar_url avatar_url_for(user)
  json.is_current_user user.id == @viewer.id
end

json.pending_invitations @pending_invitations do |invitation|
  json.partial! "api/v1/invitations/invitation", invitation: invitation
end

json.can_manage_invitations @viewer.admin?
json.invitations_enabled invitations_enabled?
json.invitation_delivery invitation_delivery
