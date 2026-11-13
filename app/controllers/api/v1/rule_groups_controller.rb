# frozen_string_literal: true

class Api::V1::RuleGroupsController < Api::V1::BaseController
  before_action -> { authorize_scope!(:read) }, only: :index
  before_action -> { authorize_scope!(:read_write) }, only: %i[create update destroy]
  before_action :reject_guest_writes!, only: %i[create update destroy]
  before_action :set_rule_group, only: %i[update destroy]

  # In the order the rules page shows them (see Rule::Layout).
  def index
    @rule_groups = current_resource_owner.family.rule_groups.order(:position, :created_at, :id)
    @rules_counts = Rule.where(rule_group_id: @rule_groups.select(:id)).group(:rule_group_id).count
    render :index
  end

  def create
    @rule_group = current_resource_owner.family.rule_groups.new(rule_group_params)
    render_saved(status: :created)
  end

  def update
    @rule_group.assign_attributes(rule_group_params)
    render_saved(status: :ok)
  end

  # The rules stay where they are, now without a group (see RuleGroup).
  def destroy
    @rule_group.destroy!
    head :no_content
  end

  private
    def set_rule_group
      @rule_group = current_resource_owner.family.rule_groups.find(params[:id])
    end

    def rule_group_params
      params.require(:rule_group).permit(:name)
    end

    def render_saved(status:)
      unless @rule_group.save
        messages = @rule_group.errors.full_messages
        return render_json({ error: "validation_failed", message: messages.to_sentence, errors: messages },
          status: :unprocessable_entity)
      end

      @rules_counts = { @rule_group.id => @rule_group.rules.count }
      render :show, status: status
    end
end
