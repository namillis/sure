# frozen_string_literal: true

entry = @conversion.entry
account = @conversion.account
amount_money = entry.amount_money.abs

json.transaction_id @transaction.id
json.date entry.date
json.name entry.name
# Unsigned, as the web form shows it; the sign picks the default activity.
json.amount amount_money.format
json.amount_cents money_to_minor_units(amount_money)
json.currency entry.currency

json.account do
  json.id account.id
  json.name account.name
  json.account_type account.accountable_type.underscore
end

json.defaults do
  json.investment_activity_label @conversion.suggested_activity_label
  json.security_id nil
  json.qty nil
  json.price nil
end
json.investment_activity_labels Transaction::TradeConversion::ACTIVITY_LABELS

# Whether a typed ticker can be looked up through a securities provider.
json.ticker_search_available Security.providers.any?

json.security_options @security_options do |security|
  price = @prices_by_security_id[security.id]
  price_money = price && Money.new(price.price, price.currency)

  json.id security.id
  json.ticker security.ticker
  json.name security.name
  json.exchange_operating_mic security.exchange_operating_mic
  json.current_price price_money&.format
  json.current_price_cents money_to_minor_units(price_money)
  json.current_price_currency price&.currency
end
