# frozen_string_literal: true

module Api::V1::ChartSeriesRendering
  extend ActiveSupport::Concern

  class InvalidSeriesParams < StandardError
    attr_reader :error_code

    def initialize(error_code, message)
      @error_code = error_code
      super(message)
    end
  end

  included do
    include Api::V1::MoneyHelper

    rescue_from InvalidSeriesParams do |error|
      render_json({ error: error.error_code, message: error.message, errors: [ error.message ] },
        status: :unprocessable_entity)
    end
  end

  private
    def requested_period
      @requested_period ||= params[:start_date].present? || params[:end_date].present? ? custom_period : keyed_period
    end

    def keyed_period
      key = params[:period].presence || "last_30_days"
      Period.from_key(key)
    rescue Period::InvalidKeyError
      raise InvalidSeriesParams.new("invalid_period", "period must be one of: #{Period::PERIODS.keys.join(', ')}")
    end

    def custom_period
      start_date = parse_series_date(params[:start_date], "start_date")
      end_date = parse_series_date(params[:end_date], "end_date")
      raise InvalidSeriesParams.new("invalid_date", "start_date must be on or before end_date") if start_date > end_date

      Period.custom(start_date: start_date, end_date: end_date)
    end

    def parse_series_date(value, name)
      raise InvalidSeriesParams.new("invalid_date", "#{name} is required with a custom range") if value.blank?

      Date.iso8601(value)
    rescue Date::Error
      raise InvalidSeriesParams.new("invalid_date", "#{name} must be an ISO 8601 date")
    end

    def series_etag(cache_key, *extra)
      [ cache_key, requested_period.start_date, requested_period.end_date, I18n.locale, *extra ]
    end

    def series_payload(series, currency:)
      values = series ? series.values : []
      {
        period: requested_period.key || "custom",
        start_date: requested_period.start_date,
        end_date: requested_period.end_date,
        interval: series&.interval || requested_period.interval,
        currency: currency,
        trend: values.any? ? trend_payload(series.trend) : nil,
        values: values.map do |point|
          amount = display_money(point.value)
          { date: point.date, value: amount.format, value_cents: money_to_minor_units(amount) }
        end
      }
    end

    def trend_payload(trend)
      change = display_money(trend.value)
      {
        value: change.format,
        value_cents: money_to_minor_units(change),
        percent: trend.percent.finite? ? trend.percent : nil,
        percent_formatted: trend.percent_formatted,
        direction: trend.direction.to_s,
        favorable_direction: trend.favorable_direction.to_s
      }
    end

    def display_money(amount)
      amount.is_a?(Money) ? amount.for_display : amount
    end
end
