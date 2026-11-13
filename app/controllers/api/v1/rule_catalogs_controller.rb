# frozen_string_literal: true

class Api::V1::RuleCatalogsController < Api::V1::BaseController
  before_action :ensure_read_scope
  # Localize picks the locale before the API key identifies the user, so pick
  # it again once the key's user is known, as the web does for its session.
  skip_around_action :switch_locale
  around_action :switch_locale

  def show
    resource_type = params[:resource_type].presence || "transaction"

    unless Rule::SUPPORTED_RESOURCE_TYPES.include?(resource_type)
      return render_validation_error("resource_type must be one of: #{Rule::SUPPORTED_RESOURCE_TYPES.join(", ")}")
    end

    render_json(Rule::Catalog.new(family: current_resource_owner.family, resource_type: resource_type).as_json)
  end
end
