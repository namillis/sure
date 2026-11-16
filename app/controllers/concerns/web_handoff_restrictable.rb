# Confines a session minted by WebHandoff to the provider connect flow it was opened for.
#
# The session may reach the providers page and every action of a provider *_items controller.
# Leaving that area by a top-level navigation, or being redirected to the providers page, the
# accounts pages or the dashboard, ends the handoff: the session is destroyed and the browser is
# sent back to the Sure+ app. Anything else (a lazy frame, a prefetch, a form or fetch aimed
# elsewhere) is refused without ending the flow.
module WebHandoffRestrictable
  extend ActiveSupport::Concern

  PREFETCH_HEADERS = %w[Purpose Sec-Purpose X-Sec-Purpose].freeze

  included do
    before_action :enforce_web_handoff_scope
  end

  def redirect_to(options = {}, response_options = {})
    if web_handoff_session? && (status = web_handoff_redirect_finish_status(options, response_options))
      return finish_web_handoff!(status)
    end

    super
  end

  private
    def web_handoff_session?
      Current.session&.persisted? && Current.session.web_handoff?
    end

    def enforce_web_handoff_scope
      return unless web_handoff_session?
      return finish_web_handoff!("error") unless web_handoff_credential_active?
      return if WebHandoff::RoutePolicy.session_request_allowed?(controller_path, action_name)

      if web_handoff_top_level_navigation?
        finish_web_handoff!(web_handoff_navigation_finish_status)
      else
        head :forbidden
      end
    end

    def web_handoff_credential_active?
      handoff = Current.session.web_handoff
      WebHandoff.credential_active?(
        user: Current.session.user,
        credential_type: handoff["credential_type"],
        credential_id: handoff["credential_id"]
      )
    end

    # A plain fetch (Sec-Fetch-Mode cors/same-origin) is never treated as leaving the flow, so a
    # background request can't end it. Turbo Drive visits are fetches too, but carry their own id.
    def web_handoff_top_level_navigation?
      return false unless request.get? && request.format.html?
      return false if request.xhr? || turbo_frame_request?
      return false if PREFETCH_HEADERS.any? { |header| request.headers[header].to_s.match?(/prefetch|prerender/i) }

      fetch_mode = request.headers["Sec-Fetch-Mode"]
      fetch_mode.blank? || fetch_mode == "navigate" || request.headers["X-Turbo-Request-Id"].present?
    end

    # A flow's own Cancel links go straight to the accounts or providers page from one of its
    # pages, while a finished flow arrives by a redirect carrying a flash.
    def web_handoff_navigation_finish_status
      return "error" if flash[:alert].present?
      return "ok" if flash[:notice].present?

      referrer = WebHandoff::RoutePolicy.recognize_location(request.referer, host: request.host)
      WebHandoff::RoutePolicy.cancellable_flow_page?(referrer) ? "cancelled" : "ok"
    end

    def web_handoff_redirect_finish_status(options, response_options)
      return unless options.is_a?(String) || options.is_a?(Hash) || options.respond_to?(:to_model)

      location = _compute_redirect_to_location(request, options)
      return unless WebHandoff::RoutePolicy.finish_route?(WebHandoff::RoutePolicy.recognize_location(location, host: request.host))

      response_options[:alert].present? || flash[:alert].present? ? "error" : "ok"
    rescue ActionController::ActionControllerError, NoMethodError
      nil
    end

    def finish_web_handoff!(status)
      Current.session.destroy
      cookies.delete(:session_token)
      Current.session = nil
      flash.discard
      redirect_to web_handoff_done_path(status: status), status: :see_other
    end
end
