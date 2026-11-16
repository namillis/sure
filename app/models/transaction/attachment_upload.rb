# Adds files to a transaction within its attachment limits. Attaching to a persisted
# record stores the files before validation runs, so files that fail validation are
# purged again and the transaction keeps only what it had.
class Transaction::AttachmentUpload
  Result = Data.define(:status, :attachments, :errors) do
    def success? = status == :attached
  end

  def initialize(transaction, attachables)
    @transaction = transaction
    @attachables = attachables.is_a?(Array) ? attachables : [ attachables ]
  end

  # status is :attached, :too_many (the count limit would be exceeded, nothing stored)
  # or :invalid (errors holds the validation messages, nothing kept).
  def call
    transaction.with_lock do
      if transaction.attachments.count + attachables.length > Transaction::MAX_ATTACHMENTS_PER_TRANSACTION
        return Result.new(status: :too_many, attachments: [], errors: [])
      end

      existing_ids = transaction.attachments.pluck(:id)
      newly_added = Array(transaction.attachments.attach(attachables)).reject { |a| existing_ids.include?(a.id) }

      if transaction.valid?
        Result.new(status: :attached, attachments: newly_added, errors: [])
      else
        newly_added.each(&:purge)
        Result.new(status: :invalid, attachments: [], errors: transaction.errors.full_messages_for(:attachments))
      end
    end
  end

  private
    attr_reader :transaction, :attachables
end
