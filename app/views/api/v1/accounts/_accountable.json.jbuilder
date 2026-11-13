# frozen_string_literal: true

# The type's own fields, keyed as PATCH /api/v1/accounts/:id takes them in
# accountable_attributes, so an edit form can be prefilled from this block.
accountable = account.accountable

if accountable.is_a?(Depository) || accountable.is_a?(OtherAsset) || accountable.is_a?(OtherLiability)
  json.accountable({}) # their subtype is the account's top-level subtype
else
  json.accountable do
    case accountable
    when Loan
      json.extract! accountable, :subtype, :rate_type, :interest_rate, :term_months, :initial_balance,
        :start_date, :down_payment, :insurance_rate, :insurance_rate_type, :day_count_convention,
        :principal_only_transfers
      json.rate_changes accountable.variable_rates do |effective_date, rate|
        json.effective_date effective_date.iso8601
        json.rate rate.to_s("F")
      end
    when CreditCard
      json.extract! accountable, :available_credit, :minimum_payment, :apr, :annual_fee, :expiration_date,
        :statement_close_day, :due_day
    when Investment
      json.extract! accountable, :subtype
    when Crypto
      json.extract! accountable, :subtype, :tax_treatment
    when Vehicle
      purchase_price = accountable.purchase_price&.amount
      json.extract! accountable, :make, :model, :year, :mileage_value, :mileage_unit
      # Send initial_balance_shown back unchanged with an edit: the server compares
      # the two to tell an edited purchase price from an untouched one.
      json.initial_balance purchase_price
      json.initial_balance_shown purchase_price
      json.purchase_date account.opening_anchor_date
    when Property
      json.extract! accountable, :subtype, :year_built, :area_unit, :area_value
      if (address = accountable.address)
        json.address_attributes do
          json.extract! address, :line1, :line2, :locality, :region, :country, :postal_code
        end
      else
        json.address_attributes nil
      end
    end
  end
end
