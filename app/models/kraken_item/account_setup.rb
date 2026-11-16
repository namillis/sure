# frozen_string_literal: true

# Creating a Kraken connection and importing the accounts its sync found,
# shared by KrakenItemsController and the API. Every account becomes a Crypto
# exchange account; the user only picks which ones.
class KrakenItem::AccountSetup
  SELECTION_MODE = :select
  ACCOUNTABLE_TYPE = "Crypto"
  SUBTYPE = "exchange"

  def self.permitted_attributes
    %i[name sync_start_date api_key api_secret]
  end

  def self.create(family, attributes)
    item = family.kraken_items.build(attributes)
    item.name ||= I18n.t("kraken_items.create.default_name")

    if item.save
      item.set_kraken_institution_defaults!
      item.sync_later
    end

    item
  end

  attr_reader :kraken_item

  def initialize(kraken_item)
    @kraken_item = kraken_item
  end

  def import_accounts
    nil
  end

  def unlinked_accounts
    kraken_item.kraken_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).order(:name)
  end

  def institution_name_for(_kraken_account)
    kraken_item.institution_display_name
  end

  # One account's failure is logged and the rest still run.
  def complete!(account_ids)
    created_accounts = []

    account_ids.each do |kraken_account_id|
      kraken_account = kraken_item.kraken_accounts.find_by(id: kraken_account_id)
      next unless kraken_account

      kraken_account.with_lock do
        next if kraken_account.account_provider.present?

        account = Account.create_from_kraken_account(kraken_account)
        provider_link = kraken_account.ensure_account_provider!(account)
        provider_link ? created_accounts << account : account.destroy!
      end

      KrakenAccount::Processor.new(kraken_account.reload).process
    rescue StandardError => e
      Rails.logger.error("Failed to setup account for KrakenAccount #{kraken_account_id}: #{e.message}")
    end

    kraken_item.update!(pending_account_setup: unlinked_accounts.exists?)
    kraken_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts }
  end
end
