# frozen_string_literal: true

json.partial! "api/v1/accounts/account", account: @account
json.partial! "api/v1/accounts/accountable", account: @account
