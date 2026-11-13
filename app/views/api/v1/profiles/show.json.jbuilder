# frozen_string_literal: true

json.id @user.id
json.email @user.email
json.first_name @user.first_name
json.last_name @user.last_name
json.display_name @user.display_name
json.role @user.role
json.locale @user.locale
json.theme @user.theme
json.default_period @user.default_period
json.can_edit_family @user.admin?

json.family do
  family = @user.family
  json.id family.id
  json.name family.name
  json.currency family.currency
  json.country family.country
  json.timezone family.timezone
  json.date_format family.date_format
  json.locale family.locale
end

json.created_at @user.created_at.iso8601
json.updated_at @user.updated_at.iso8601
