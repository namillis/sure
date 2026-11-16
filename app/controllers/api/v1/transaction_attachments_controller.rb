# frozen_string_literal: true

class Api::V1::TransactionAttachmentsController < Api::V1::BaseController
  include Api::V1::TransactionLookup
  include ActiveStorage::Streaming

  # Same as the web: any share may view, read_write shares may also upload, deleting needs owner or full_control.
  UPLOAD_PERMISSIONS = %i[owner full_control read_write].freeze
  DELETE_PERMISSIONS = %i[owner full_control].freeze

  before_action :ensure_read_scope, only: [ :show ]
  before_action :ensure_write_scope, only: [ :create, :destroy ]
  before_action :set_transaction, only: [ :create, :destroy ]

  # GET /api/v1/attachments/:id
  #
  # API keys carry no session, which the blob routes require, so the file is sent here.
  def show
    attachment = accessible_attachments.find(params[:id])
    disposition = params[:disposition] == "attachment" ? :attachment : :inline

    send_blob_stream attachment.blob, disposition: disposition
  end

  # POST /api/v1/transactions/:transaction_id/attachments
  def create
    return unless require_account_permission!(UPLOAD_PERMISSIONS)

    file = params[:file]
    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return render_unprocessable("file must be a multipart file upload")
    end

    result = Transaction::AttachmentUpload.new(@transaction, file).call

    case result.status
    when :attached
      @attachment = result.attachments.first
      render :create, status: :created
    when :too_many
      render_unprocessable("A transaction can have at most #{Transaction::MAX_ATTACHMENTS_PER_TRANSACTION} attachments")
    else
      render_unprocessable(result.errors.join(", "), result.errors)
    end
  end

  # DELETE /api/v1/transactions/:transaction_id/attachments/:id
  def destroy
    return unless require_account_permission!(DELETE_PERMISSIONS)

    @transaction.attachments.find(params[:id]).purge
    head :no_content
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def set_transaction
      load_accessible_transaction(params[:transaction_id])
    end

    def accessible_attachments
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      transaction_ids = current_resource_owner.family.transactions
        .joins(entry: :account)
        .merge(Account.accessible_by(current_resource_owner))
        .select(:id)

      ActiveStorage::Attachment.where(record_type: "Transaction", name: "attachments", record_id: transaction_ids)
    end

    def require_account_permission!(allowed)
      return true if @entry.account.permission_for(current_resource_owner).in?(allowed)

      render json: {
        error: "forbidden",
        message: "You do not have permission to change this account's attachments"
      }, status: :forbidden
      false
    end

    def render_unprocessable(message, errors = nil)
      render json: {
        error: "validation_failed",
        message: message,
        errors: errors || [ message ]
      }, status: :unprocessable_entity
    end
end
