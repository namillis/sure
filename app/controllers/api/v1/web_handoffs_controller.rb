# frozen_string_literal: true

# Issues a one-time URL that opens a provider connect page in a restricted web session, so the
# Sure+ app can run any provider's web flow without a second sign-in. See WebHandoff.
class Api::V1::WebHandoffsController < Api::V1::BaseController
  CREATE_LIMIT = 10
  CREATE_WINDOW = 1.minute

  before_action -> { authorize_scope!(:read_write) }
  rate_limit to: CREATE_LIMIT, within: CREATE_WINDOW, by: -> { current_resource_owner.id }, only: :create,
    name: "web-handoff-create", with: -> { render_create_rate_limited }
  before_action :reject_guest_handoff

  def create
    path = params.require(:web_handoff).permit(:path)[:path]

    unless WebHandoff::RoutePolicy.entry_path_allowed?(path)
      message = "This page can't be opened from the app"
      return render_json({ error: "path_not_allowed", message: message, errors: [ message ] }, status: :unprocessable_entity)
    end

    token, expires_at = WebHandoff.issue!(
      user: current_resource_owner,
      path: path,
      credential_type: @authentication_method == :oauth ? "oauth" : "api_key",
      credential_id: @authentication_method == :oauth ? doorkeeper_token.id : @api_key.id
    )

    render_json({ url: redeem_web_handoff_url(token: token), expires_at: expires_at.iso8601 }, status: :created)
  end

  private
    # Guests can't create or change connections on the web, so there is nothing for them to open.
    def reject_guest_handoff
      return unless current_resource_owner.guest?

      message = "Guests can't manage connections"
      render_json({ error: "forbidden", message: message, errors: [ message ] }, status: :forbidden)
    end

    def render_create_rate_limited
      message = "Too many handoff links requested. Try again in a minute."
      render_json({ error: "rate_limit_exceeded", message: message, errors: [ message ] }, status: :too_many_requests)
    end
end
