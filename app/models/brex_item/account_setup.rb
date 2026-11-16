# frozen_string_literal: true

# Creating a Brex connection, shared by BrexItemsController and the API, and
# the API's view of BrexItem::AccountFlow's account setup.
class BrexItem::AccountSetup
  SELECTION_MODE = :typed

  def self.permitted_attributes
    %i[name sync_start_date token base_url]
  end

  def self.create(family, attributes)
    item = family.brex_items.build(normalize(attributes))
    item.name = I18n.t("brex_items.default_connection_name") if item.name.blank?
    item.sync_later if item.save
    item
  end

  def self.normalize(attributes)
    attributes = attributes.dup
    attributes[:token] = attributes[:token].to_s.strip if attributes[:token].present?
    if attributes.key?(:base_url)
      attributes[:base_url] = attributes[:base_url].to_s.strip
      attributes[:base_url] = nil if attributes[:base_url].blank?
    end
    attributes
  end

  attr_reader :brex_item

  def initialize(brex_item)
    @brex_item = brex_item
  end

  def import_accounts
    flow.import_accounts_with_user_facing_error
  end

  def unlinked_accounts
    flow.unlinked_brex_accounts
  end

  def account_type_options
    flow.displayable_account_type_options
  end

  # Only the subtypes BrexItems::AccountSetupsController accepts.
  def subtype_options
    allowed_subtypes = (Depository::SUBTYPES.keys + CreditCard::SUBTYPES.keys).map(&:to_s)

    flow.subtype_options.transform_values do |config|
      config.merge(options: config[:options].select { |_label, value| allowed_subtypes.include?(value.to_s) })
    end
  end

  # The setup form preselects Credit Card for cards and Depository otherwise.
  def suggestion_for(brex_account, _inferred = nil)
    { accountable_type: brex_account.card? ? "CreditCard" : "Depository" }
  end

  def institution_name_for(_brex_account)
    brex_item.institution_display_name
  end

  def complete!(account_types:, account_subtypes:)
    result = flow.complete_setup!(account_types: account_types, account_subtypes: account_subtypes)
    { created_accounts: result.created_accounts, skipped_count: result.skipped_count, failed_count: result.failed_count }
  end

  private

    def flow
      @flow ||= BrexItem::AccountFlow.new(family: brex_item.family, brex_item: brex_item)
    end
end
