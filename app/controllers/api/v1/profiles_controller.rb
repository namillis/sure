# frozen_string_literal: true

class Api::V1::ProfilesController < Api::V1::BaseController
  THEMES = %w[light dark system].freeze
  USER_FIELDS = %i[first_name last_name locale theme default_period].freeze
  FAMILY_FIELDS = %i[currency country timezone date_format locale].freeze

  before_action :ensure_read_scope, only: :show
  before_action :ensure_write_scope, only: :update

  def show
    @user = current_resource_owner
  end

  def update
    @user = current_resource_owner
    attributes = profile_params

    if attributes.key?(:theme) && THEMES.exclude?(attributes[:theme])
      render_validation_error("Theme must be one of: #{THEMES.join(', ')}")
      return
    end

    if @user.update(attributes)
      render :show
    else
      render_json({
        error: "validation_failed",
        message: @user.errors.full_messages.to_sentence,
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity)
    end
  end

  private

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def profile_params
      params.require(:user).permit(*USER_FIELDS, family_attributes: FAMILY_FIELDS)
    end
end
