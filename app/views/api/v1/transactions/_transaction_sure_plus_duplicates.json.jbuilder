# frozen_string_literal: true

# The web's duplicate banner: a provider sync (or a manual pending merge) left
# a suggested posted match on this pending transaction. Only a match in the
# same account is shown, because merge_with_duplicate! refuses any other.
# The index preloads the matches into @sure_plus_duplicate_candidates; other
# callers look the single row up.
duplicate_suspected = transaction.has_potential_duplicate?

json.pending transaction.pending?
json.duplicate_suspected duplicate_suspected
json.duplicate_confidence(duplicate_suspected ? transaction.potential_duplicate_confidence : nil)

candidate = if duplicate_suspected
  preloaded = @sure_plus_duplicate_candidates
  match = preloaded ? preloaded[transaction.potential_duplicate_entry_id] : transaction.potential_duplicate_entry
  match if match&.transaction? && match.account_id == transaction.entry.account_id
end

if candidate
  json.duplicate_candidate do
    candidate_money = candidate.amount_money
    candidate_cents = money_to_minor_units(candidate_money).abs

    json.id candidate.entryable_id
    json.entry_id candidate.id
    json.date candidate.date
    json.name candidate.name
    json.amount candidate_money.format
    json.amount_cents candidate_cents
    json.signed_amount_cents(candidate.classification == "income" ? candidate_cents : -candidate_cents)
    json.currency candidate.currency
  end
else
  json.duplicate_candidate nil
end
