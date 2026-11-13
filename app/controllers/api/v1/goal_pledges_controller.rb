# frozen_string_literal: true

class Api::V1::GoalPledgesController < Api::V1::BaseController
  before_action :ensure_write_scope
  before_action :require_preview_features_for_api
  before_action :set_goal
  before_action :set_pledge, only: %i[renew destroy]

  def create
    @pledge = @goal.goal_pledges.new(amount: pledge_input[:amount])
    @pledge.account = lookup_account(pledge_input[:account_id])
    @pledge.kind = @pledge.account&.default_pledge_kind || "transfer"
    @pledge.currency = @goal.currency

    if @pledge.save
      render_pledge(status: :created)
    else
      render json: {
        error: "validation_failed",
        message: "Pledge could not be created",
        errors: @pledge.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def renew
    @pledge.extend!
    render_pledge
  rescue GoalPledge::NotOpenError
    render_not_open
  end

  def destroy
    @pledge.cancel!
    render_pledge
  rescue GoalPledge::NotOpenError
    render_not_open
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
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:goal_id])

      @goal = current_resource_owner.family.goals.find(params[:goal_id])
    end

    def set_pledge
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      @pledge = @goal.goal_pledges.find(params[:id])
    end

    def pledge_input
      params.require(:pledge)
    end

    def lookup_account(id)
      return nil if id.blank? || !valid_uuid?(id.to_s)

      current_resource_owner.accessible_accounts.where(id: @goal.goal_accounts.select(:account_id)).find_by(id: id)
    end

    def render_pledge(status: :ok)
      family = current_resource_owner.family
      @goal = Goal.prepared_for(family, scope: family.goals.where(id: @goal.id)).first
      linked_ids = @goal.linked_accounts.map(&:id)
      @accessible_account_ids = current_resource_owner.accessible_accounts.where(id: linked_ids).pluck(:id).to_set
      render :show, status: status
    end

    def render_not_open
      render json: {
        error: "pledge_not_open",
        message: "Only open pledges can be changed",
        errors: [ "Only open pledges can be changed" ]
      }, status: :unprocessable_entity
    end
end
