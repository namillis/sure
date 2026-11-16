# frozen_string_literal: true

# One provider connection's sync schedule, as SyncSchedulesController edits it.
# Schedules are per connection only; there is no family-wide interval.
class Api::V1::ProviderConnectionSyncSchedulesController < Api::V1::BaseController
  before_action -> { authorize_scope!(:read) }, only: :show
  before_action -> { authorize_scope!(:read_write) }, only: :update
  before_action :set_syncable

  rescue_from ProviderConnectionManager::Unprocessable do |error|
    render_json({ error: error.code, message: error.message, errors: [ error.message ] }, status: :unprocessable_entity)
  end

  def show
    @sync_schedule = @syncable.sync_schedule
    render :show
  end

  # A null or blank interval_minutes removes the schedule, like the web form's
  # "usual sync only"; a body without the field is rejected.
  def update
    attributes = params.require(:sync_schedule).permit(:interval_minutes)
    unless attributes.key?(:interval_minutes)
      return render_validation_error("interval_minutes is required; send null to remove the schedule")
    end

    interval = attributes[:interval_minutes].presence

    if interval.nil?
      @syncable.sync_schedule&.destroy!
      @sync_schedule = nil
    else
      @sync_schedule = SyncSchedule.assign(@syncable, interval)

      if @sync_schedule.errors.any?
        messages = @sync_schedule.errors.full_messages
        return render_json({ error: "validation_failed", message: messages.to_sentence, errors: messages },
          status: :unprocessable_entity)
      end
    end

    render :show
  end

  private

    # Same lookup and checks as SyncSchedulesController#set_syncable: within the
    # family, not being deleted, and SyncSchedule.editable_by? for reads too,
    # since the web only shows the schedule to people who can change it.
    def set_syncable
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:provider_connection_id])

      @connection = ProviderConnectionManager.find(current_resource_owner.family, params[:provider_connection_id],
        provider_key: params[:provider])
      @syncable = @connection.item
      raise ActiveRecord::RecordNotFound if @syncable.try(:scheduled_for_deletion?)

      # FinanceKit data arrives from the device's Wallet publisher, so a server
      # sync on a schedule does nothing for it (see ProviderConnectionManager#sync!).
      if @connection.key == "financekit" || !SyncSchedule.schedulable_associations.key?(@syncable.class.name)
        message = "This connection does not support a sync schedule"
        return render_json({ error: "sync_schedule_not_supported", message: message, errors: [ message ] },
          status: :unprocessable_entity)
      end

      return if SyncSchedule.editable_by?(@syncable, current_resource_owner)

      render_json({ error: "forbidden", message: "You cannot manage this connection's sync schedule" }, status: :forbidden)
    end
end
