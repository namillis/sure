# Opens the restricted web session a Sure+ app handoff token was issued for, and hands the browser
# back to the app when the flow ends. The token arrives as the filtered `token` query parameter,
# so it is masked in request logs.
class WebHandoffsController < ApplicationController
  skip_authentication
  skip_before_action :require_onboarding_and_upgrade

  layout false

  before_action :prevent_caching

  def show
    grant = WebHandoff.redeem(params[:token])
    user = grant && User.find_by(id: grant.user_id)

    unless user&.active? && WebHandoff::RoutePolicy.entry_path_allowed?(grant.path) &&
        WebHandoff.credential_active?(user: user, credential_type: grant.credential_type, credential_id: grant.credential_id)
      return redirect_to new_session_path, alert: t(".invalid")
    end

    session_record = start_handoff_session(user, grant)
    return redirect_to new_session_path, alert: t(".invalid") unless session_record

    Rails.logger.info("[WebHandoff] Started session for user_id=#{user.id}")
    redirect_to grant.path
  end

  # A real navigation follows the redirect to the app's URL scheme, which the app's auth sheet
  # catches. Turbo and fetch requests can't follow it, so they get a page that makes Turbo reload
  # it as a full navigation.
  def done
    @app_callback_url = app_callback_url
    fetch_mode = request.headers["Sec-Fetch-Mode"]

    if fetch_mode.blank? || fetch_mode == "navigate"
      redirect_to @app_callback_url, allow_other_host: true
    else
      render :done
    end
  end

  private
    def app_callback_url
      WebHandoff.app_callback_url(params[:status])
    end

    def prevent_caching
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def start_handoff_session(user, grant)
      discard_previous_handoff_session
      reset_session

      user.with_active_lock! do
        expires_at = Session::WEB_HANDOFF_LIFETIME.from_now
        session_record = user.sessions.create!(
          data: {
            Session::WEB_HANDOFF_KEY => {
              "expires_at" => expires_at.iso8601,
              "started_path" => grant.path,
              "credential_type" => grant.credential_type,
              "credential_id" => grant.credential_id
            }
          }
        )
        cookies.signed[:session_token] = { value: session_record.id, httponly: true, expires: expires_at }
        session_record
      end
    rescue User::InactiveError
      nil
    end

    def discard_previous_handoff_session
      previous = Session.find_by(id: cookies.signed[:session_token])
      previous.destroy if previous&.web_handoff?
    end
end
