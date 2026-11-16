# frozen_string_literal: true

# Creating a Binance connection and importing the accounts its sync found,
# shared by BinanceItemsController and the API. Every account becomes a Crypto
# exchange account; the user only picks which ones.
class BinanceItem::AccountSetup
  SELECTION_MODE = :select
  ACCOUNTABLE_TYPE = "Crypto"
  SUBTYPE = "exchange"

  def self.permitted_attributes
    %i[name sync_start_date api_key api_secret]
  end

  def self.create(family, attributes)
    item = family.binance_items.build(attributes)
    item.name ||= I18n.t("binance_items.create.default_name")

    if item.save
      item.set_binance_institution_defaults!
      item.sync_later
    end

    item
  end

  attr_reader :binance_item

  def initialize(binance_item)
    @binance_item = binance_item
  end

  def import_accounts
    nil
  end

  def unlinked_accounts
    binance_item.binance_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).order(:name)
  end

  def institution_name_for(_binance_account)
    binance_item.institution_display_name
  end

  # Applies a submitted sync start date. Returns false, changing nothing, when
  # it isn't a date on or before today.
  def update_sync_start_date(value)
    parsed_date = begin
      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
    return false unless parsed_date.present? && parsed_date <= Date.current

    binance_item.update!(sync_start_date: parsed_date)
    true
  end

  # One account's failure is logged and the rest still run.
  def complete!(account_ids)
    created_accounts = []

    account_ids.each do |binance_account_id|
      ba = binance_item.binance_accounts.find_by(id: binance_account_id)
      next unless ba

      begin
        ba.with_lock do
          next if ba.account.present?

          account = Account.create_from_binance_account(ba)
          provider_link = ba.ensure_account_provider!(account)

          if provider_link
            created_accounts << account
          else
            account.destroy!
          end
        end
      rescue StandardError => e
        Rails.logger.error("Failed to setup account for BinanceAccount #{ba.id}: #{e.message}")
        next
      end

      ba.reload

      begin
        BinanceAccount::HoldingsProcessor.new(ba).process
      rescue StandardError => e
        Rails.logger.error("Failed to process holdings for #{ba.id}: #{e.message}")
      end
    end

    binance_item.update!(pending_account_setup: unlinked_accounts.count > 0)
    binance_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts }
  end
end
