# frozen_string_literal: true

class Api::V1::AccountBalanceSeriesController < Api::V1::BaseController
  include Api::V1::ChartSeriesRendering

  VIEWS = %w[balance cash_balance holdings_balance].freeze

  before_action :ensure_read_scope

  def show
    account = current_resource_owner.family.accounts.accessible_by(current_resource_owner).find_by(id: params[:id])
    return render_json({ error: "not_found", message: "Account not found" }, status: :not_found) unless account

    view = requested_view
    period = requested_period

    return unless stale?(etag: series_etag(account.balance_series_cache_key(period: period, view: view)), public: false)

    series = account.cached_balance_series(period: period, view: view.to_sym)
    render_json(series_payload(series, currency: account.currency).merge(account_id: account.id, view: view))
  end

  private
    def requested_view
      view = params[:view].presence || "balance"
      return view if VIEWS.include?(view)

      raise InvalidSeriesParams.new("invalid_view", "view must be one of: #{VIEWS.join(', ')}")
    end

    def ensure_read_scope
      authorize_scope!(:read)
    end
end
