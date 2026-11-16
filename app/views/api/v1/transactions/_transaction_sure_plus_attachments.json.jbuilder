# frozen_string_literal: true

json.attachments transaction.attachments do |attachment|
  json.partial! "api/v1/transaction_attachments/attachment", attachment: attachment
end
