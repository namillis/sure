# frozen_string_literal: true

# Creating a SimpleFIN connection and turning its imported accounts into Sure
# accounts, shared by SimplefinItemsController and the API.
class SimplefinItem::AccountSetup
  SELECTION_MODE = :typed

  # Labels are the setup form's, which are not translated.
  ACCOUNT_TYPE_OPTIONS = [
    [ "Checking or Savings Account", "Depository" ],
    [ "Credit Card", "CreditCard" ],
    [ "Investment Account", "Investment" ],
    [ "Crypto Account", "Crypto" ],
    [ "Loan or Mortgage", "Loan" ],
    [ "Other Asset", "OtherAsset" ]
  ].freeze

  def self.permitted_attributes
    %i[setup_token]
  end

  # Claims the setup token. Raises ProviderConnectionManager::Unprocessable
  # with the web form's message when the token is blank, malformed or refused.
  def self.create(family, attributes)
    setup_token = attributes[:setup_token]
    raise unprocessable("blank_token") if setup_token.blank?

    family.create_simplefin_item!(setup_token: setup_token, item_name: "SimpleFIN Connection")
  rescue ArgumentError, URI::InvalidURIError
    raise unprocessable("invalid_token")
  rescue Provider::Simplefin::SimplefinError => e
    case e.error_type
    when :token_compromised then raise unprocessable("token_compromised")
    when :invalid_url then raise unprocessable("invalid_token")
    else raise unprocessable("create_failed", message: e.message)
    end
  rescue ProviderConnectionManager::Unprocessable
    raise
  rescue => e
    Rails.logger.error("SimpleFin connection error: #{e.message}")
    raise unprocessable("unexpected")
  end

  def self.unprocessable(key, **interpolations)
    ProviderConnectionManager::Unprocessable.new(key, I18n.t("simplefin_items.create.errors.#{key}", **interpolations))
  end
  private_class_method :unprocessable

  attr_reader :simplefin_item

  def initialize(simplefin_item)
    @simplefin_item = simplefin_item
  end

  def import_accounts
    nil
  end

  # Checks both the legacy account FK and AccountProvider.
  def unlinked_accounts
    simplefin_item.simplefin_accounts
      .left_joins(:account, :account_provider)
      .where(accounts: { id: nil }, account_providers: { id: nil })
  end

  def account_type_options
    ACCOUNT_TYPE_OPTIONS
  end

  def subtype_options
    {
      "Depository" => {
        label: "Account Subtype:",
        options: Depository::SUBTYPES.map { |k, v| [ v[:long], k ] }
      },
      "CreditCard" => {
        label: "",
        options: [],
        message: "Credit cards will be automatically set up as credit card accounts."
      },
      "Investment" => {
        label: "Investment Type:",
        options: Investment::SUBTYPES.map { |k, v| [ v[:long], k ] }
      },
      "Loan" => {
        label: "Loan Type:",
        options: Loan::SUBTYPES.map { |k, v| [ v[:long], k ] }
      },
      "Crypto" => {
        label: nil,
        options: [],
        message: "Crypto accounts track cryptocurrency holdings."
      },
      "OtherAsset" => {
        label: nil,
        options: [],
        message: "No additional options needed for Other Assets."
      }
    }
  end

  # UI-only type guesses; the form preselects one only at high confidence.
  def inferred_map(simplefin_accounts = unlinked_accounts)
    simplefin_accounts.each_with_object({}) do |sfa, map|
      inference = Simplefin::AccountTypeMapper.infer(
        name: sfa.name,
        holdings: sfa.raw_holdings_payload.presence || sfa.raw_payload.to_h["holdings"],
        extra: sfa.extra,
        balance: sfa.current_balance,
        available_balance: sfa.available_balance,
        institution: institution_name_for(sfa)
      )
      map[sfa.id] = { type: inference.accountable_type, subtype: inference.subtype, confidence: inference.confidence }
    end
  end

  # What the setup form preselects: nothing for a likely-closed account
  # (activity that has stopped, near-zero balance), else a high-confidence guess.
  def suggestion_for(simplefin_account, inferred = nil)
    inferred ||= inferred_map([ simplefin_account ])[simplefin_account.id] || {}
    activity = simplefin_account.activity_summary
    near_zero_balance = (simplefin_account.current_balance || 0).to_d.abs <= 1
    likely_closed = activity.last_transacted_at.present? && activity.dormant? && near_zero_balance
    return {} if likely_closed || inferred[:confidence] != :high

    { accountable_type: inferred[:type], subtype: inferred[:subtype] }
  end

  def institution_name_for(simplefin_account)
    org_data = simplefin_account.org_data
    org_data["name"] if org_data.is_a?(Hash)
  rescue
    nil
  end

  # account_types / account_subtypes are keyed by SimplefinAccount id; a
  # "skip" or blank type leaves that account unlinked.
  def complete!(account_types:, account_subtypes:)
    valid_types = Provider::SimplefinAdapter.supported_account_types + [ "Crypto", "OtherAsset" ]
    created_accounts = []
    skipped_count = 0

    account_types.each do |simplefin_account_id, selected_type|
      if selected_type == "skip" || selected_type.blank?
        skipped_count += 1
        next
      end

      unless valid_types.include?(selected_type)
        Rails.logger.warn("Invalid account type '#{selected_type}' submitted for SimpleFIN account #{simplefin_account_id}")
        next
      end

      simplefin_account = simplefin_item.simplefin_accounts.find_by(id: simplefin_account_id)
      unless simplefin_account
        Rails.logger.warn("SimpleFIN account #{simplefin_account_id} not found for item #{simplefin_item.id}")
        next
      end

      if simplefin_account.account.present?
        Rails.logger.info("SimpleFIN account #{simplefin_account_id} already linked, skipping")
        next
      end

      selected_subtype = account_subtypes[simplefin_account_id]
      selected_subtype = "credit_card" if selected_type == "CreditCard" && selected_subtype.blank?

      account = Account.create_from_simplefin_account(simplefin_account, selected_type, selected_subtype)
      simplefin_account.update!(account: account)
      simplefin_account.ensure_account_provider!
      created_accounts << account
    end

    simplefin_item.update!(pending_account_setup: false)
    simplefin_item.sync_later if created_accounts.any?

    { created_accounts: created_accounts, skipped_count: skipped_count }
  end
end
