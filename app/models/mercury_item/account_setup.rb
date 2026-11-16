# frozen_string_literal: true

# Creating a Mercury connection and turning its accounts into Sure accounts,
# shared by MercuryItemsController and the API.
class MercuryItem::AccountSetup
  SELECTION_MODE = :typed

  ACCOUNT_TYPE_KEYS = {
    "depository" => "Depository",
    "credit_card" => "CreditCard",
    "investment" => "Investment",
    "loan" => "Loan",
    "other_asset" => "OtherAsset"
  }.freeze

  def self.permitted_attributes
    %i[name sync_start_date token base_url]
  end

  # Returns the item, unsaved with errors when invalid. The first sync fetches
  # the accounts.
  def self.create(family, attributes)
    item = family.mercury_items.build(attributes)
    item.name ||= "Mercury Connection"
    item.sync_later if item.save
    item
  end

  attr_reader :mercury_item

  def initialize(mercury_item)
    @mercury_item = mercury_item
  end

  # Fetches and stores the accounts when none are cached yet. Returns nil on
  # success, or the setup page's error message.
  def import_accounts
    return nil unless mercury_item.mercury_accounts.empty?
    return I18n.t("mercury_items.setup_accounts.no_api_token") unless mercury_item.credentials_configured?

    mercury_provider = mercury_item.mercury_provider
    return I18n.t("mercury_items.setup_accounts.no_api_token") unless mercury_provider.present?

    begin
      accounts_data = mercury_provider.get_accounts
      available_accounts = accounts_data[:accounts] || []

      if available_accounts.empty?
        Rails.logger.info("Mercury API returned no accounts for item #{mercury_item.id}")
        return nil
      end

      available_accounts.each do |account_data|
        account_name = account_data[:nickname].presence || account_data[:name].presence || account_data[:legalBusinessName].presence
        next if account_name.blank?

        mercury_account = mercury_item.mercury_accounts.find_or_initialize_by(account_id: account_data[:id].to_s)
        mercury_account.upsert_mercury_snapshot!(account_data)
        mercury_account.save!
      end

      nil
    rescue Provider::Mercury::MercuryError => e
      Rails.logger.error("Mercury API error: #{e.message}")
      I18n.t("mercury_items.setup_accounts.api_error", message: e.message)
    rescue StandardError => e
      Rails.logger.error("Unexpected error fetching Mercury accounts: #{e.class}: #{e.message}")
      I18n.t("mercury_items.setup_accounts.api_error", message: e.message)
    end
  end

  def unlinked_accounts
    mercury_item.mercury_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
  end

  def account_type_options
    supported_types = Provider::MercuryAdapter.supported_account_types

    ACCOUNT_TYPE_KEYS.filter_map do |key, type|
      next unless supported_types.include?(type)

      [ I18n.t("mercury_items.setup_accounts.account_types.#{key}"), type ]
    end
  end

  def subtype_options
    {
      "Depository" => {
        label: I18n.t("mercury_items.setup_accounts.subtype_labels.depository"),
        options: translate_subtypes("depository", Depository::SUBTYPES)
      },
      "CreditCard" => {
        label: I18n.t("mercury_items.setup_accounts.subtype_labels.credit_card"),
        options: [],
        message: I18n.t("mercury_items.setup_accounts.subtype_messages.credit_card")
      },
      "Investment" => {
        label: I18n.t("mercury_items.setup_accounts.subtype_labels.investment"),
        options: translate_subtypes("investment", Investment::SUBTYPES)
      },
      "Loan" => {
        label: I18n.t("mercury_items.setup_accounts.subtype_labels.loan"),
        options: translate_subtypes("loan", Loan::SUBTYPES)
      },
      "OtherAsset" => {
        label: I18n.t("mercury_items.setup_accounts.subtype_labels.other_asset").presence,
        options: [],
        message: I18n.t("mercury_items.setup_accounts.subtype_messages.other_asset")
      }
    }.slice(*Provider::MercuryAdapter.supported_account_types)
  end

  # The setup form preselects "skip" for every account.
  def suggestion_for(_mercury_account, _inferred = nil)
    {}
  end

  def institution_name_for(_mercury_account)
    mercury_item.institution_display_name
  end

  # All accounts are created in one transaction; a failure raises and
  # creates none.
  def complete!(account_types:, account_subtypes:)
    valid_types = Provider::MercuryAdapter.supported_account_types
    created_accounts = []
    skipped_count = 0

    ActiveRecord::Base.transaction do
      account_types.each do |mercury_account_id, selected_type|
        if selected_type == "skip" || selected_type.blank?
          skipped_count += 1
          next
        end

        unless valid_types.include?(selected_type)
          Rails.logger.warn("Invalid account type '#{selected_type}' submitted for Mercury account #{mercury_account_id}")
          next
        end

        mercury_account = mercury_item.mercury_accounts.find_by(id: mercury_account_id)
        unless mercury_account
          Rails.logger.warn("Mercury account #{mercury_account_id} not found for item #{mercury_item.id}")
          next
        end

        if mercury_account.account_provider.present?
          Rails.logger.info("Mercury account #{mercury_account_id} already linked, skipping")
          next
        end

        selected_subtype = account_subtypes[mercury_account_id]
        selected_subtype = "credit_card" if selected_type == "CreditCard" && selected_subtype.blank?

        # The provider sync creates the balance.
        account = Account.create_and_sync(
          {
            family: mercury_item.family,
            name: mercury_account.name,
            balance: mercury_account.current_balance || 0,
            currency: "USD", # Mercury is US-only
            accountable_type: selected_type,
            accountable_attributes: selected_subtype.present? ? { subtype: selected_subtype } : {}
          },
          skip_initial_sync: true
        )

        AccountProvider.create!(account: account, provider: mercury_account)
        created_accounts << account
      end
    end

    mercury_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts, skipped_count: skipped_count }
  end

  private

    def translate_subtypes(type_key, subtypes_hash)
      subtypes_hash.map do |k, v|
        [ I18n.t("mercury_items.setup_accounts.subtypes.#{type_key}.#{k}", default: v[:long] || k.humanize), k ]
      end
    end
end
