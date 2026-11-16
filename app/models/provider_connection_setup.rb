# frozen_string_literal: true

# Creating a token-based provider connection and finishing its account setup
# through the API. Each provider's steps live in its <Provider>Item::AccountSetup,
# which the web controllers use too; this class only translates the API's
# request shape into theirs and checks it first, so a bad request changes nothing.
class ProviderConnectionSetup
  SETUP_CLASSES = {
    "binance" => "BinanceItem::AccountSetup",
    "brex" => "BrexItem::AccountSetup",
    "coinspot" => "CoinspotItem::AccountSetup",
    "ibkr" => "IbkrItem::AccountSetup",
    "kraken" => "KrakenItem::AccountSetup",
    "lunchflow" => "LunchflowItem::AccountSetup",
    "mercury" => "MercuryItem::AccountSetup",
    "simplefin" => "SimplefinItem::AccountSetup"
  }.freeze

  # Providers whose web setup takes a sync start date on the account setup
  # step rather than on create.
  SETUP_SYNC_START_DATE = %w[binance simplefin].freeze

  Unprocessable = ProviderConnectionManager::Unprocessable

  def self.setup_class_for(provider_key)
    class_name = SETUP_CLASSES[provider_key.to_s]
    return class_name.constantize if class_name

    message = if SurePlus::TokenProviders::KEYS.include?(provider_key.to_s)
      "#{provider_key} connections need steps the API doesn't support yet. Connect it on the web"
    else
      "This provider can't be connected through the API. Connect it on the web"
    end
    raise Unprocessable.new("provider_not_supported", message)
  end

  # Returns the item; unsaved, with errors, when the attributes are invalid.
  def self.create(family, provider_key, attributes)
    setup_class = setup_class_for(provider_key)
    setup_class.create(family, attributes.slice(*setup_class.permitted_attributes))
  end

  attr_reader :connection

  def initialize(connection)
    @connection = connection
    @setup = self.class.setup_class_for(connection.key).new(connection.item)
  end

  def item
    connection.item
  end

  # Fetches the provider's account list first where the web setup page does.
  def import_accounts!
    error = setup.import_accounts
    raise Unprocessable.new("provider_error", error) if error.present?
  end

  def pending_accounts
    @pending_accounts ||= begin
      accounts = setup.unlinked_accounts.to_a
      inferred = setup.respond_to?(:inferred_map) ? setup.inferred_map(accounts) : {}

      accounts.map { |provider_account| pending_account_payload(provider_account, inferred[provider_account.id]) }
    end
  end

  def setup_required?
    pending_accounts.any? || awaiting_accounts?
  end

  # No accounts are known yet because the first sync hasn't finished.
  def awaiting_accounts?
    provider_accounts.none? && item.syncs.completed.none?
  end

  # rows: [{ id:, import:, accountable_type:, subtype:, link_to_account_id: }].
  # Rows left out leave those accounts pending. Returns the created accounts.
  def complete!(rows, sync_start_date: nil)
    selections = validate_rows!(rows)
    apply_sync_start_date!(sync_start_date) if sync_start_date.present?

    result = if setup.class::SELECTION_MODE == :select
      setup.complete!(selections.select { |row| row[:import] }.map { |row| row[:id] })
    else
      setup.complete!(
        account_types: selections.to_h { |row| [ row[:id], row[:import] ? row[:accountable_type] : "skip" ] },
        account_subtypes: selections.select { |row| row[:import] && row[:subtype].present? }.to_h { |row| [ row[:id], row[:subtype] ] }
      )
    end

    @pending_accounts = nil
    result[:created_accounts]
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    raise Unprocessable.new("setup_failed", "The accounts could not be created: #{e.message}")
  end

  private

    attr_reader :setup

    def provider_accounts
      accounts_association = ProviderConnectionStatus::PROVIDERS.find { |provider| provider[:key] == connection.key }[:accounts]
      item.public_send(accounts_association)
    end

    def allowed_types
      @allowed_types ||= if setup.class::SELECTION_MODE == :select
        type = setup.class::ACCOUNTABLE_TYPE
        [ { accountable_type: type, label: type.constantize.display_name, subtypes: [] } ]
      else
        subtype_options = setup.subtype_options

        setup.account_type_options.map do |label, type|
          options = subtype_options.dig(type, :options) || []
          {
            accountable_type: type,
            label: label,
            subtypes: options.map { |subtype_label, value| { value: value.to_s, label: subtype_label } }
          }
        end
      end
    end

    def pending_account_payload(provider_account, inferred)
      suggestion = if setup.class::SELECTION_MODE == :select
        { accountable_type: setup.class::ACCOUNTABLE_TYPE, subtype: setup.class::SUBTYPE }
      else
        setup.suggestion_for(provider_account, inferred)
      end

      currency = provider_account.currency.presence || item.family.currency
      balance = Money.new(provider_account.current_balance || 0, currency)

      {
        id: provider_account.id,
        name: provider_account.name,
        institution: setup.institution_name_for(provider_account),
        balance: balance.format,
        balance_cents: (balance.amount * balance.currency.minor_unit_conversion).round(0).to_i,
        currency: currency,
        suggested_accountable_type: suggestion[:accountable_type],
        suggested_subtype: suggestion[:subtype],
        allowed_types: allowed_types
      }
    end

    def validate_rows!(rows)
      raise Unprocessable.new("validation_failed", "accounts must be an array") unless rows.is_a?(Array)

      pending_ids = pending_accounts.map { |account| account[:id].to_s }
      seen_ids = Set.new

      rows.map do |row|
        raise Unprocessable.new("validation_failed", "Each accounts entry must be an object") unless row.respond_to?(:to_h)

        row = row.to_h.symbolize_keys
        id = row[:id].to_s
        raise Unprocessable.new("unknown_account", "Account #{id.presence || '(blank)'} is not waiting for setup on this connection") unless pending_ids.include?(id)
        raise Unprocessable.new("validation_failed", "Account #{id} is listed more than once") unless seen_ids.add?(id)

        if row[:link_to_account_id].present?
          raise Unprocessable.new("link_not_supported", "Linking to an existing account isn't supported through the API. Link it on the web")
        end

        import = ActiveModel::Type::Boolean.new.cast(row.fetch(:import, true)) == true
        validate_type!(id, row[:accountable_type].presence, row[:subtype].presence) if import

        { id: id, import: import, accountable_type: row[:accountable_type].presence, subtype: row[:subtype].presence&.to_s }
      end
    end

    def validate_type!(id, accountable_type, subtype)
      if setup.class::SELECTION_MODE == :select
        fixed_type = setup.class::ACCOUNTABLE_TYPE
        return if (accountable_type.nil? || accountable_type == fixed_type) && (subtype.nil? || subtype == setup.class::SUBTYPE)

        raise Unprocessable.new("invalid_account_type", "Account #{id} can only be imported as #{fixed_type}")
      end

      raise Unprocessable.new("invalid_account_type", "Account #{id} needs an accountable_type") if accountable_type.nil?

      allowed = allowed_types.find { |type| type[:accountable_type] == accountable_type }
      raise Unprocessable.new("invalid_account_type", "#{accountable_type} is not an allowed type for account #{id}") unless allowed
      return if subtype.nil? || allowed[:subtypes].any? { |option| option[:value] == subtype.to_s }

      raise Unprocessable.new("invalid_subtype", "#{subtype} is not an allowed subtype of #{accountable_type} for account #{id}")
    end

    def apply_sync_start_date!(value)
      unless SETUP_SYNC_START_DATE.include?(connection.key)
        raise Unprocessable.new("validation_failed", "sync_start_date is set when creating a #{connection.key} connection")
      end

      date = begin
        Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
      raise Unprocessable.new("invalid_sync_start_date", "sync_start_date must be a date (YYYY-MM-DD) no later than today") unless date && date <= Date.current

      if connection.key == "binance"
        setup.update_sync_start_date(date)
      else
        item.update!(sync_start_date: date)
      end
    end
end
