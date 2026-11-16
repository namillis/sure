# frozen_string_literal: true

# API counterpart of the budget sharing section of Settings > Preferences
# (Settings::PreferencesController#show and Settings::BudgetSharesController
# #update): the caller grants each family member "none", "read_only" or
# "read_write" access to the caller's personal budget.
class Api::V1::BudgetSharesController < Api::V1::BaseController
  NO_SHARE = "none"

  before_action -> { authorize_scope!(:read) }, only: :show
  before_action -> { authorize_scope!(:read_write) }, only: :update

  def show
    render_shares
  end

  def update
    shares_params = params.require(:budget_shares)
    return render_validation_error("budget_shares must be an object") unless shares_params.is_a?(ActionController::Parameters)

    members = shares_params[:members]
    members = members.values if members.is_a?(ActionController::Parameters)
    unless members.is_a?(Array) && members.all? { |member| member.is_a?(ActionController::Parameters) }
      return render_validation_error("members must be an array of { user_id, permission }")
    end

    allowed = [ NO_SHARE, *BudgetShare::PERMISSIONS ]
    entries = members.map { |member| { user_id: member[:user_id].to_s, permission: member[:permission].to_s } }
    if entries.any? { |entry| allowed.exclude?(entry[:permission]) }
      return render_validation_error("permission must be one of: #{allowed.join(', ')}")
    end

    viewers_by_id = eligible_members.where(id: entries.map { |entry| entry[:user_id] }).index_by(&:id)
    unknown_ids = entries.map { |entry| entry[:user_id] }.reject { |id| viewers_by_id.key?(id) }
    return render_validation_error("Unknown or ineligible user_id: #{unknown_ids.join(', ')}") if unknown_ids.any?

    BudgetShare.transaction do
      entries.each do |entry|
        viewer = viewers_by_id.fetch(entry[:user_id])
        share = current_resource_owner.budget_shares_given.find_by(viewer: viewer)

        if entry[:permission] == NO_SHARE
          share&.destroy!
        elsif share
          share.update!(permission: entry[:permission])
        else
          current_resource_owner.budget_shares_given.create!(viewer: viewer, permission: entry[:permission])
        end
      end
    end

    render_shares
  end

  private

    def eligible_members
      current_resource_owner.family.users.where.not(id: current_resource_owner.id).where(active: true)
    end

    def render_shares
      shares = current_resource_owner.budget_shares_given.index_by(&:viewer_id)

      render_json({
        personal_budgets: current_resource_owner.family.personal_budgets?,
        permissions: BudgetShare::PERMISSIONS,
        members: eligible_members.order(:created_at).map do |member|
          { user_id: member.id, name: member.display_name, permission: shares[member.id]&.permission || NO_SHARE }
        end
      })
    end
end
