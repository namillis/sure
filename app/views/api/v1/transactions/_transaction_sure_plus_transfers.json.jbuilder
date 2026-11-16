# frozen_string_literal: true

# Merged into the `transfer` object built above. An automatic match is
# "pending" until someone confirms it, and until then both legs keep their
# own kind and still count in budgets and reports.
transfer = transaction.transfer
if transfer.present?
  json.transfer do
    json.status transfer.status
  end
end
