# frozen_string_literal: true

# Creating an Interactive Brokers connection and importing the accounts its
# sync found, shared by IbkrItemsController and the API. Every account becomes
# an Investment brokerage account; the user only picks which ones.
class IbkrItem::AccountSetup
  SELECTION_MODE = :select
  ACCOUNTABLE_TYPE = "Investment"
  SUBTYPE = "brokerage"

  def self.permitted_attributes
    %i[name query_id token]
  end

  def self.create(family, attributes)
    item = family.ibkr_items.build(attributes)
    item.name = item.name.presence || default_item_name(family)
    item.sync_later if item.save
    item
  end

  # "Interactive Brokers", then "Interactive Brokers 2", "Interactive Brokers 3"...
  def self.default_item_name(family)
    base = I18n.t("ibkr_items.defaults.name")
    existing = family.ibkr_items.active.pluck(:name)
    return base unless existing.include?(base)

    (2..).lazy.map { |n| "#{base} #{n}" }.find { |name| !existing.include?(name) }
  end

  attr_reader :ibkr_item

  def initialize(ibkr_item)
    @ibkr_item = ibkr_item
  end

  def import_accounts
    nil
  end

  def unlinked_accounts
    ibkr_item.ibkr_accounts.includes(account_provider: :account).reject { |ibkr_account| ibkr_account.current_account.present? }
  end

  def institution_name_for(_ibkr_account)
    ibkr_item.institution_display_name
  end

  def complete!(account_ids)
    created_accounts = []

    account_ids.each do |ibkr_account_id|
      ibkr_account = ibkr_item.ibkr_accounts.find_by(id: ibkr_account_id)
      next unless ibkr_account

      ibkr_account.with_lock do
        next if ibkr_account.current_account.present?

        account = Account.create_from_ibkr_account(ibkr_account)
        ibkr_account.ensure_account_provider!(account)
        created_accounts << account
      end

      begin
        IbkrAccount::Processor.new(ibkr_account.reload).process
      rescue => e
        Rails.logger.error("Failed to process IBKR account #{ibkr_account.id} after setup: #{e.class} - #{e.message}")
      end
    end

    ibkr_item.update!(pending_account_setup: ibkr_item.unlinked_accounts_count.positive?)
    ibkr_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts }
  end
end
