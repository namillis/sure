# Replaces a transaction in a trade-capable account with a trade for the same
# date, currency and amount, and excludes the original. Shared by the web
# "Convert to trade" modal and the API.
#
# Params (string or symbol keys):
#   security_id               an existing Security id, or "__custom__" (web form)
#   ticker                    "SYMBOL|EXCHANGE|PROVIDER", as the securities combobox submits
#   custom_ticker             a ticker typed by hand
#   exchange_operating_mic    optional MIC for ticker / custom_ticker
#   qty, price                at least one; the other is inferred from the amount
#   investment_activity_label "Buy" or "Sell"; inferred from the amount's sign when blank
#   trade_name                optional; defaults to Trade.build_name
class Transaction::TradeConversion
  ACTIVITY_LABELS = %w[Buy Sell].freeze

  # `key` names an entry under transactions.convert_to_trade.errors.
  class Error < StandardError
    attr_reader :key

    def initialize(key)
      @key = key
      super(I18n.t("transactions.convert_to_trade.errors.#{key}"))
    end

    def invalid_trade_values?
      key.in?(%i[enter_qty_or_price invalid_qty_or_price])
    end
  end

  attr_reader :transaction, :entry, :params

  def initialize(transaction, params = {})
    @transaction = transaction
    @entry = transaction.entry
    @params = params.to_h.with_indifferent_access
  end

  def account
    entry.account
  end

  # Activity the form preselects: money out buys, money in sells, matching
  # what #convert! infers when no label is given.
  def suggested_activity_label
    entry.amount.negative? ? "Sell" : "Buy"
  end

  # Securities already held in the account, which the web form offers when no
  # securities provider is configured.
  def held_securities
    account.holdings
      .includes(:security)
      .where.not(security: nil)
      .map(&:security)
      .uniq(&:ticker)
      .sort_by(&:ticker)
  end

  def ensure_convertible!
    raise Error.new(:not_investment_account) unless account.supports_trades?
    raise Error.new(:already_converted) if entry.excluded?
  end

  # Returns the new trade Entry. Raises Error for invalid input or a source
  # that was converted concurrently, and ActiveRecord errors from the writes.
  def convert!
    ensure_convertible!

    # Resolve before locking the source, avoiding network calls under its lock.
    security = resolve_security
    activity_label = params[:investment_activity_label].presence

    # Entry#transaction is its delegated transaction record, so use an explicit
    # DB transaction rather than ActiveRecord's instance with_lock.
    ActiveRecord::Base.transaction do
      entry.lock!
      raise Error.new(:already_converted) if entry.excluded?

      # Infer missing values from the locked source amount, including edits
      # committed while the security was being resolved.
      qty, price = qty_and_price

      is_sell = activity_label == "Sell" || (activity_label.blank? && entry.amount < 0)
      # Positive qty/amount buys (money out); negative sells (money in).
      signed_qty = is_sell ? -qty : qty
      trade_amount = qty * price
      signed_amount = is_sell ? -trade_amount : trade_amount
      activity_label ||= is_sell ? "Sell" : "Buy"

      conversion_note = I18n.t("transactions.convert_to_trade.conversion_note",
        original_name: entry.name,
        original_date: I18n.l(entry.date, format: :long))

      new_entry = account.entries.create!(
        name: params[:trade_name] || Trade.build_name(is_sell ? "sell" : "buy", qty, security.ticker),
        date: entry.date,
        amount: signed_amount,
        currency: entry.currency,
        notes: conversion_note,
        entryable: Trade.new(
          security: security,
          qty: signed_qty,
          price: price,
          currency: entry.currency,
          investment_activity_label: activity_label
        )
      )

      # Protect the new trade from sync overwrites.
      new_entry.lock_saved_attributes!
      new_entry.mark_user_modified!

      entry.update!(excluded: true)
      new_entry
    end
  end

  private

    def resolve_security
      security =
        if params[:security_id] == "__custom__"
          if params[:ticker].present?
            resolve_combobox_ticker
          elsif params[:custom_ticker].present?
            resolve_custom_ticker
          else
            raise Error.new(:enter_ticker)
          end
        elsif params[:security_id].present?
          Security.find_by(id: params[:security_id]) || raise(Error.new(:security_not_found))
        elsif params[:ticker].present?
          resolve_combobox_ticker
        elsif params[:custom_ticker].present?
          resolve_custom_ticker
        end

      security || raise(Error.new(:select_security))
    end

    def resolve_combobox_ticker
      parsed = Security.parse_combobox_id(params[:ticker])
      raise Error.new(:enter_ticker) if parsed[:ticker].blank?

      Security::Resolver.new(
        parsed[:ticker].strip,
        exchange_operating_mic: parsed[:exchange_operating_mic] || params[:exchange_operating_mic].presence,
        country_code: transaction_family_country,
        price_provider: parsed[:price_provider]
      ).resolve
    end

    def resolve_custom_ticker
      Security::Resolver.new(
        params[:custom_ticker].to_s.strip,
        exchange_operating_mic: params[:exchange_operating_mic].presence,
        country_code: transaction_family_country
      ).resolve
    end

    def transaction_family_country
      account.family.country
    end

    def qty_and_price
      amount = entry.amount.abs
      qty = params[:qty].present? ? params[:qty].to_d.abs : nil
      price = params[:price].present? ? params[:price].to_d : nil

      if qty.nil? && price.nil?
        raise Error.new(:enter_qty_or_price)
      elsif qty.nil? && price.present? && price > 0
        qty = (amount / price).round(6)
      elsif price.nil? && qty.present? && qty > 0
        price = (amount / qty).round(4)
      end

      raise Error.new(:invalid_qty_or_price) if qty.nil? || qty <= 0 || price.nil? || price <= 0

      [ qty, price ]
    end
end
