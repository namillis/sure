# frozen_string_literal: true

# The connections this server lets the user add, for the Sure+ app's "Add connection" list.
class Api::V1::AvailableProviderConnectionsController < Api::V1::BaseController
  before_action :ensure_read_scope

  def index
    render_json({ data: ProviderConnectionCatalog.available_for(current_resource_owner) })
  end
end
