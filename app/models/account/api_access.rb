# frozen_string_literal: true

# What a user may do with an account through the API, and which fields a
# linked (provider-synced) account will not accept. The write endpoints
# enforce these rules and the account JSON reports them, so both read here.
class Account::ApiAccess
  MANAGE_PERMISSIONS = %i[owner full_control].freeze

  # The web form hides these for linked accounts: the provider owns them.
  LINKED_LOCKED_FIELDS = %w[balance currency].freeze
  LINKED_LOCKED_ACCOUNTABLE_FIELDS = {
    "Vehicle" => %w[initial_balance initial_balance_shown purchase_date]
  }.freeze

  attr_reader :account, :user

  def initialize(account, user)
    @account = account
    @user = user
  end

  # Pending deletion reads as not editable: the write endpoints no longer find it.
  def can_edit?
    !account.pending_deletion? && account.permission_for(user).in?(MANAGE_PERMISSIONS)
  end

  def can_delete?
    can_edit? && !account.linked?
  end

  # Field paths as the write API names them: top-level keys, then
  # "accountable_attributes.<key>" for the type's own fields.
  def locked_fields
    return [] unless account.linked?

    LINKED_LOCKED_FIELDS +
      LINKED_LOCKED_ACCOUNTABLE_FIELDS.fetch(account.accountable_type, []).map { |key| "accountable_attributes.#{key}" }
  end

  # The locked fields an update request tries to set.
  def locked_fields_in(account_params)
    accountable_params = account_params[:accountable_attributes]
    locked_fields.select do |path|
      scope, key = path.include?(".") ? [ accountable_params, path.split(".", 2).last ] : [ account_params, path ]
      scope.respond_to?(:key?) && scope.key?(key)
    end
  end
end
