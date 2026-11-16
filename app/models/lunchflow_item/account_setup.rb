# frozen_string_literal: true

# Creating a Lunch Flow connection and turning its accounts into Sure
# accounts, shared by LunchflowItemsController and the API.
class LunchflowItem::AccountSetup
  SELECTION_MODE = :typed

  ACCOUNT_TYPE_KEYS = {
    "depository" => "Depository",
    "credit_card" => "CreditCard",
    "investment" => "Investment",
    "loan" => "Loan",
    "other_asset" => "OtherAsset"
  }.freeze

  def self.permitted_attributes
    %i[name sync_start_date api_key base_url]
  end

  # Returns the item, unsaved with errors when invalid. The first sync fetches
  # the accounts.
  def self.create(family, attributes)
    item = family.lunchflow_items.build(attributes)
    item.name ||= "Lunch Flow Connection"
    item.sync_later if item.save
    item
  end

  attr_reader :lunchflow_item

  def initialize(lunchflow_item)
    @lunchflow_item = lunchflow_item
  end

  # Fetches and stores the accounts when none are cached yet. Returns nil on
  # success, or the setup page's error message.
  def import_accounts
    return nil unless lunchflow_item.lunchflow_accounts.empty?
    return I18n.t("lunchflow_items.setup_accounts.no_api_key") unless lunchflow_item.credentials_configured?

    lunchflow_provider = lunchflow_item.lunchflow_provider
    return I18n.t("lunchflow_items.setup_accounts.no_api_key") unless lunchflow_provider.present?

    begin
      accounts_data = lunchflow_provider.get_accounts
      available_accounts = accounts_data[:accounts] || []

      if available_accounts.empty?
        Rails.logger.info("LunchFlow API returned no accounts for item #{lunchflow_item.id}")
        return nil
      end

      available_accounts.each do |account_data|
        next if account_data[:name].blank?

        lunchflow_account = lunchflow_item.lunchflow_accounts.find_or_initialize_by(account_id: account_data[:id].to_s)
        lunchflow_account.upsert_lunchflow_snapshot!(account_data)
        lunchflow_account.save!
      end

      nil
    rescue Provider::Lunchflow::LunchflowError => e
      Rails.logger.error("LunchFlow API error: #{e.message}")
      I18n.t("lunchflow_items.setup_accounts.api_error", message: e.message)
    rescue StandardError => e
      Rails.logger.error("Unexpected error fetching LunchFlow accounts: #{e.class}: #{e.message}")
      I18n.t("lunchflow_items.setup_accounts.api_error", message: e.message)
    end
  end

  def unlinked_accounts
    lunchflow_item.lunchflow_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
  end

  def account_type_options
    supported_types = Provider::LunchflowAdapter.supported_account_types

    ACCOUNT_TYPE_KEYS.filter_map do |key, type|
      next unless supported_types.include?(type)

      [ I18n.t("lunchflow_items.setup_accounts.account_types.#{key}"), type ]
    end
  end

  def subtype_options
    {
      "Depository" => {
        label: I18n.t("lunchflow_items.setup_accounts.subtype_labels.depository"),
        options: translate_subtypes("depository", Depository)
      },
      "CreditCard" => {
        label: I18n.t("lunchflow_items.setup_accounts.subtype_labels.credit_card"),
        options: [],
        message: I18n.t("lunchflow_items.setup_accounts.subtype_messages.credit_card")
      },
      "Investment" => {
        label: I18n.t("lunchflow_items.setup_accounts.subtype_labels.investment"),
        options: translate_subtypes("investment", Investment)
      },
      "Loan" => {
        label: I18n.t("lunchflow_items.setup_accounts.subtype_labels.loan"),
        options: translate_subtypes("loan", Loan)
      },
      "OtherAsset" => {
        label: I18n.t("lunchflow_items.setup_accounts.subtype_labels.other_asset").presence,
        options: [],
        message: I18n.t("lunchflow_items.setup_accounts.subtype_messages.other_asset")
      }
    }.slice(*Provider::LunchflowAdapter.supported_account_types)
  end

  # The setup form preselects "skip" for every account.
  def suggestion_for(_lunchflow_account, _inferred = nil)
    {}
  end

  def institution_name_for(lunchflow_account)
    lunchflow_account.institution_metadata.to_h["name"].presence || lunchflow_item.institution_display_name
  end

  # All accounts are created in one transaction; a failure raises and
  # creates none.
  def complete!(account_types:, account_subtypes:)
    valid_types = Provider::LunchflowAdapter.supported_account_types
    created_accounts = []
    skipped_count = 0

    ActiveRecord::Base.transaction do
      account_types.each do |lunchflow_account_id, selected_type|
        if selected_type == "skip" || selected_type.blank?
          skipped_count += 1
          next
        end

        unless valid_types.include?(selected_type)
          Rails.logger.warn("Invalid account type '#{selected_type}' submitted for LunchFlow account #{lunchflow_account_id}")
          next
        end

        lunchflow_account = lunchflow_item.lunchflow_accounts.find_by(id: lunchflow_account_id)
        unless lunchflow_account
          Rails.logger.warn("LunchFlow account #{lunchflow_account_id} not found for item #{lunchflow_item.id}")
          next
        end

        if lunchflow_account.account_provider.present?
          Rails.logger.info("LunchFlow account #{lunchflow_account_id} already linked, skipping")
          next
        end

        selected_subtype = account_subtypes[lunchflow_account_id]
        selected_subtype = "credit_card" if selected_type == "CreditCard" && selected_subtype.blank?

        # The provider sync creates the balance, in the right currency.
        account = Account.create_and_sync(
          {
            family: lunchflow_item.family,
            name: lunchflow_account.name,
            balance: lunchflow_account.current_balance || 0,
            currency: lunchflow_account.currency || "USD",
            accountable_type: selected_type,
            accountable_attributes: selected_subtype.present? ? { subtype: selected_subtype } : {}
          },
          skip_initial_sync: true
        )

        AccountProvider.create!(account: account, provider: lunchflow_account)
        created_accounts << account
      end
    end

    lunchflow_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts, skipped_count: skipped_count }
  end

  private

    def translate_subtypes(type_key, accountable_class)
      accountable_class::SUBTYPES.keys.map do |key|
        [ I18n.t("lunchflow_items.setup_accounts.subtypes.#{type_key}.#{key}", default: accountable_class.long_subtype_label_for(key)), key ]
      end
    end
end
