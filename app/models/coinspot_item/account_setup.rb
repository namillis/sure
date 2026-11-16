# frozen_string_literal: true

# Creating a CoinSpot connection and importing the accounts its sync found,
# shared by CoinspotItemsController and the API. Every account becomes a
# Crypto exchange account; the user only picks which ones.
class CoinspotItem::AccountSetup
  SELECTION_MODE = :select
  ACCOUNTABLE_TYPE = "Crypto"
  SUBTYPE = "exchange"

  def self.permitted_attributes
    %i[name sync_start_date api_key api_secret]
  end

  def self.create(family, attributes)
    item = family.coinspot_items.build(attributes)
    item.name ||= I18n.t("coinspot_items.create.default_name")

    if item.save
      item.set_coinspot_institution_defaults!
      item.sync_later
    end

    item
  end

  attr_reader :coinspot_item

  def initialize(coinspot_item)
    @coinspot_item = coinspot_item
  end

  def import_accounts
    nil
  end

  def unlinked_accounts
    coinspot_item.coinspot_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).order(:name)
  end

  def institution_name_for(_coinspot_account)
    coinspot_item.institution_display_name
  end

  # A single account's failure is logged and skipped rather than aborting the
  # rest; a created account whose provider link fails to save is torn back
  # down instead of left half-set-up.
  def complete!(account_ids)
    created_accounts = []
    failed_count = 0

    account_ids.each do |coinspot_account_id|
      coinspot_account = coinspot_item.coinspot_accounts.find_by(id: coinspot_account_id)
      next unless coinspot_account

      coinspot_account.with_lock do
        if coinspot_account.account_provider.blank?
          account = Account.create_from_coinspot_account(coinspot_account)
          provider_link = coinspot_account.ensure_account_provider!(account)
          provider_link ? created_accounts << account : account.destroy!
        end
      end

      CoinspotAccount::Processor.new(coinspot_account.reload).process
    rescue StandardError => e
      failed_count += 1
      DebugLogEntry.capture(
        category: "provider_sync_error",
        level: "error",
        message: "Failed to setup account for CoinspotAccount: #{e.message}",
        source: self.class.name,
        provider_key: "coinspot",
        family: coinspot_item.family,
        metadata: { coinspot_account_id: coinspot_account_id, error_class: e.class.name }
      )
    end

    coinspot_item.update!(pending_account_setup: unlinked_accounts.exists?)
    coinspot_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts, failed_count: failed_count }
  end
end
