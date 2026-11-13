# frozen_string_literal: true

# Lifecycle transitions and partial spends on a goal, mirroring the member
# actions on the web GoalsController.
class Api::V1::GoalActionsController < Api::V1::BaseController
  before_action :ensure_write_scope
  before_action :require_preview_features_for_api
  before_action :set_goal

  def pause = perform_transition(:pause)
  def resume = perform_transition(:resume)
  def complete = perform_transition(:complete)
  def archive = perform_transition(:archive)
  def unarchive = perform_transition(:unarchive)
  def reopen = perform_transition(:reopen)

  def consume
    input = params.require(:consumption)
    Goal::Consumption.new(@goal, user: current_resource_owner).record!(
      amount: input[:amount], account_id: input[:account_id], transaction_id: input[:transaction_id]
    )

    render_goal(status: :created)
  rescue Goal::ConsumptionRefused => e
    message = I18n.t("goals.consume.errors.#{e.reason}")
    render json: { error: "consumption_refused", reason: e.reason.to_s, message: message, errors: [ message ] },
           status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render_invalid("validation_failed", e.record.errors.full_messages)
  end

  private
    def ensure_write_scope
      authorize_scope!(:write)
    end

    def require_preview_features_for_api
      return if current_resource_owner.preview_features_enabled?

      render_json(
        { error: "feature_disabled", message: "Preview features are not enabled for this user" },
        status: :forbidden
      )
    end

    def set_goal
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      family = current_resource_owner.family
      @goal = Goal.prepared_for(family, scope: family.goals.where(id: params[:id])).first ||
        raise(ActiveRecord::RecordNotFound)
    end

    # Same two refusals as GoalsController#perform_transition!: the state
    # machine says no, or the save that persists the new state fails validation
    # (AASM's bang event returns false rather than raising).
    def perform_transition(event)
      return render_invalid("invalid_transition", [ I18n.t("goals.#{event}.invalid_transition") ]) unless @goal.aasm.may_fire_event?(event)

      unless @goal.public_send("#{event}!")
        messages = @goal.errors.full_messages.presence || [ I18n.t("goals.#{event}.invalid_transition") ]
        return render_invalid("invalid_transition", messages)
      end

      render_goal
    end

    def render_invalid(error, messages)
      render json: { error: error, message: messages.to_sentence, errors: messages }, status: :unprocessable_entity
    end

    def render_goal(status: :ok)
      family = current_resource_owner.family
      @goal = Goal.prepared_for(family, scope: family.goals.where(id: @goal.id)).first
      @accessible_account_ids = current_resource_owner.accessible_accounts
                                                      .where(id: @goal.linked_accounts.map(&:id))
                                                      .pluck(:id).to_set
      render "api/v1/goals/show", status: status
    end
end
