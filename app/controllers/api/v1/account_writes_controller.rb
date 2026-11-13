# frozen_string_literal: true

class Api::V1::AccountWritesController < Api::V1::BaseController
  ACCOUNT_ATTRIBUTES = %i[
    name balance subtype currency institution_name institution_domain notes
    exclude_from_reports enable_category_matcher
  ].freeze
  PROPERTY_ACCOUNT_ATTRIBUTES = %i[name balance subtype currency institution_name institution_domain notes].freeze
  PROPERTY_ACCOUNTABLE_ATTRIBUTES = %i[id subtype year_built area_unit area_value].freeze
  ADDRESS_ATTRIBUTES = %i[line1 line2 locality region country postal_code].freeze
  LINKED_LOCKED_ACCOUNT_ATTRIBUTES = %w[balance currency].freeze
  LINKED_LOCKED_ACCOUNTABLE_ATTRIBUTES = %w[initial_balance initial_balance_shown purchase_date].freeze

  before_action -> { authorize_scope!(:read_write) }
  before_action :set_writable_account, only: %i[update destroy]

  def create
    type = accountable_type_from_params
    return render_validation_error("accountable_type must be one of: #{Accountable::TYPES.join(', ')}") unless type

    @account = type == "Property" ? create_property : create_account(type)
    return if performed?

    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_record_invalid(e)
  end

  def update
    requested_type = params.require(:account)[:accountable_type]
    if requested_type.present? && normalize_accountable_type(requested_type) != @account.accountable_type
      return render_validation_error("accountable_type cannot be changed")
    end

    if @account.linked? && (locked = locked_linked_fields).any?
      return render_validation_error("Linked accounts cannot change: #{locked.join(', ')}")
    end

    @account.property? ? update_property : update_account
    return if performed?

    render :show
  rescue ActiveRecord::RecordInvalid => e
    render_record_invalid(e)
  end

  def destroy
    if @account.linked?
      return render_validation_error("Linked accounts cannot be deleted; disconnect the account first")
    end

    if @account.destroy_later == false
      render_json({ error: "internal_server_error", message: "Account could not be scheduled for deletion" },
        status: :internal_server_error)
    else
      render_json({ id: @account.id, message: "Account scheduled for deletion" }, status: :accepted)
    end
  end

  private

    def set_writable_account
      return render_account_not_found unless valid_uuid?(params[:id])

      @account = family.accounts.accessible_by(current_resource_owner)
                       .where.not(status: :pending_deletion)
                       .find_by(id: params[:id])
      return render_account_not_found unless @account

      unless @account.permission_for(current_resource_owner).in?([ :owner, :full_control ])
        render_json({ error: "forbidden", message: "You do not have permission to modify this account" }, status: :forbidden)
      end
    end

    def create_account(type)
      attributes = generic_params(type, creating: true)
      opening_balance_date = begin
        attributes[:opening_balance_date].presence&.to_date
      rescue Date::Error
        nil
      end || (Time.zone.today - 2.years)

      Account.transaction do
        account = family.accounts.create_and_sync(
          attributes.except(:opening_balance_date).merge(
            accountable_type: type,
            currency: attributes[:currency].presence || family.currency,
            owner: current_resource_owner,
            logo_chosen: false
          ),
          opening_balance_date: opening_balance_date
        )
        account.lock_saved_attributes!
        account
      end
    end

    def update_account
      attributes = generic_params(@account.accountable_type, creating: false)
      update_attributes = attributes.except(:balance)
      @account.logo_chosen = false

      Account.transaction do
        if attributes[:balance].present? && attributes[:balance].to_d != @account.balance
          set_balance!(attributes[:balance])
        end
        raise ActiveRecord::RecordInvalid, @account unless @account.update(update_attributes)

        @account.lock_saved_attributes!
      end
    end

    def create_property
      attributes = property_params
      return render_validation_error("Balance can't be blank") if attributes[:balance].blank?

      Account.transaction do
        account = family.accounts.create!(
          attributes.except(:balance).merge(
            accountable_type: "Property",
            balance: 0,
            status: "draft",
            owner: current_resource_owner,
            currency: attributes[:currency].presence || family.currency
          )
        )
        account.accountable.lock_saved_attributes!
        account.auto_share_with_family! if family.share_all_by_default?

        @account = account
        set_balance!(attributes[:balance])
        update_address!
        account.activate! if account.draft?
        account
      end
    end

    def update_property
      attributes = property_params

      Account.transaction do
        @account.update!(attributes.except(:balance))
        @account.accountable.lock_saved_attributes!
        set_balance!(attributes[:balance]) if attributes[:balance].present?
        if address_params.present?
          update_address!
          @account.activate! if @account.draft?
        end
      end
    end

    def set_balance!(balance)
      result = @account.set_current_balance(balance.to_d)
      return if result.success?

      @account.errors.add(:balance, result.error.to_s)
      raise ActiveRecord::RecordInvalid, @account
    end

    def update_address!
      return if address_params.blank?

      property = @account.property
      address_attributes = address_params.to_h
      address_attributes[:id] = property.address.id if property.address
      property.update!(address_attributes: address_attributes)
    end

    def render_record_invalid(error)
      messages = error.record.errors.full_messages.presence || [ error.message ]
      render_json({ error: "validation_failed", message: messages.join(", "), errors: messages }, status: :unprocessable_entity)
    end

    def render_account_not_found
      render_json({ error: "not_found", message: "Account not found" }, status: :not_found)
    end

    def family
      current_resource_owner.family
    end

    def accountable_type_from_params
      type = normalize_accountable_type(params.require(:account)[:accountable_type])
      type if Accountable::TYPES.include?(type)
    end

    def normalize_accountable_type(value)
      value.to_s.camelize
    end

    def generic_params(type, creating:)
      account_attributes = creating ? ACCOUNT_ATTRIBUTES + [ :opening_balance_date ] : ACCOUNT_ATTRIBUTES
      params.require(:account).permit(
        *account_attributes,
        accountable_attributes: web_controller_for(type).permitted_accountable_attributes
      )
    end

    def property_params
      params.require(:account).permit(*PROPERTY_ACCOUNT_ATTRIBUTES, accountable_attributes: PROPERTY_ACCOUNTABLE_ATTRIBUTES)
    end

    def address_params
      params.require(:account).fetch(:accountable_attributes, {}).fetch(:address_attributes, {}).permit(*ADDRESS_ATTRIBUTES)
    end

    def web_controller_for(type)
      "#{type.pluralize}Controller".constantize
    end

    def locked_linked_fields
      raw = params.require(:account)
      locked = LINKED_LOCKED_ACCOUNT_ATTRIBUTES.select { |key| raw.key?(key) }
      accountable = raw[:accountable_attributes]
      if @account.vehicle? && accountable.respond_to?(:key?)
        locked += LINKED_LOCKED_ACCOUNTABLE_ATTRIBUTES.select { |key| accountable.key?(key) }.map { |key| "accountable_attributes.#{key}" }
      end
      locked
    end
end
