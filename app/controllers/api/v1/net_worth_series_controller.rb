# frozen_string_literal: true

class Api::V1::NetWorthSeriesController < Api::V1::BaseController
  include Api::V1::ChartSeriesRendering

  before_action :ensure_read_scope

  def show
    family = current_resource_owner.family
    balance_sheet = family.balance_sheet(user: current_resource_owner)
    period = requested_period

    return unless stale?(etag: series_etag(balance_sheet.net_worth_series_cache_key(period: period)), public: false)

    series = balance_sheet.any_net_worth_accounts? ? balance_sheet.net_worth_series(period: period) : nil
    render_json(series_payload(series, currency: family.currency))
  end

  private
    def ensure_read_scope
      authorize_scope!(:read)
    end
end
