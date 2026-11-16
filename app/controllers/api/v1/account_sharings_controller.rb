# frozen_string_literal: true

# API counterpart of AccountSharingsController. The owner picks a permission
# (or "none") per family member; a member the account is shared with can only
# change their own include_in_finances, as on the web.
class Api::V1::AccountSharingsController < Api::V1::BaseController
  NO_SHARE = "none"

  before_action -> { authorize_scope!(:read) }, only: :show
  before_action -> { authorize_scope!(:read_write) }, only: :update
  before_action :set_account

  def show
    render_sharing
  end

  def update
    sharing = params.require(:sharing)
    return render_validation_error("sharing must be an object") unless sharing.is_a?(ActionController::Parameters)

    if @account.owned_by?(current_resource_owner)
      update_members(sharing)
    else
      update_own_finance_inclusion(sharing)
    end
  end

  private

    def set_account
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      @account = current_resource_owner.accessible_accounts.find(params[:id])
    end

    def eligible_members
      current_resource_owner.family.users.where.not(id: @account.owner_id).where(active: true)
    end

    def update_members(sharing)
      if sharing.key?(:include_in_finances)
        return render_validation_error("include_in_finances is set by the members an account is shared with, not its owner")
      end

      entries = member_entries(sharing)
      return if performed?

      members_by_id = eligible_members.where(id: entries.map { |entry| entry[:user_id] }).index_by(&:id)
      unknown_ids = entries.map { |entry| entry[:user_id] }.reject { |id| members_by_id.key?(id) }
      return render_validation_error("Unknown or ineligible user_id: #{unknown_ids.join(', ')}") if unknown_ids.any?

      AccountShare.transaction do
        entries.each do |entry|
          user = members_by_id.fetch(entry[:user_id])
          share = @account.account_shares.find_by(user: user)

          if entry[:permission] == NO_SHARE
            share&.destroy!
          elsif share
            share.update!(permission: entry[:permission])
          else
            @account.account_shares.create!(user: user, permission: entry[:permission], include_in_finances: true)
          end
        end
      end

      render_sharing
    end

    def update_own_finance_inclusion(sharing)
      if sharing.key?(:members)
        return render_json({ error: "forbidden", message: I18n.t("account_sharings.update.not_owner") }, status: :forbidden)
      end
      return render_validation_error("include_in_finances is required") unless sharing.key?(:include_in_finances)

      include_value = ActiveModel::Type::Boolean.new.cast(sharing[:include_in_finances])
      return render_validation_error("include_in_finances must be true or false") if include_value.nil?

      @account.account_shares.find_by!(user: current_resource_owner).update!(include_in_finances: include_value)
      render_sharing
    end

    def member_entries(sharing)
      members = sharing[:members]
      members = members.values if members.is_a?(ActionController::Parameters)
      unless members.is_a?(Array) && members.all? { |member| member.is_a?(ActionController::Parameters) }
        return render_validation_error("members must be an array of { user_id, permission }")
      end

      allowed = [ NO_SHARE, *AccountShare::PERMISSIONS ]
      entries = members.map { |member| { user_id: member[:user_id].to_s, permission: member[:permission].to_s } }
      if entries.any? { |entry| allowed.exclude?(entry[:permission]) }
        return render_validation_error("permission must be one of: #{allowed.join(', ')}")
      end

      entries
    end

    def render_sharing
      owner = @account.owned_by?(current_resource_owner)
      shares = @account.account_shares.includes(:user).index_by(&:user_id)
      own_share = shares[current_resource_owner.id]

      members = owner ? eligible_members.order(:created_at) : []

      render_json({
        account_id: @account.id,
        is_owner: owner,
        owner: @account.owner && { id: @account.owner.id, name: @account.owner.display_name },
        permission: owner ? nil : own_share&.permission,
        include_in_finances: owner ? nil : own_share&.include_in_finances,
        permissions: AccountShare::PERMISSIONS,
        members: members.map do |member|
          { user_id: member.id, name: member.display_name, permission: shares[member.id]&.permission || NO_SHARE }
        end
      })
    end
end
