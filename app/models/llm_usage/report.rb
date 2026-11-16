# Settings → LLM usage's totals for a date range (LlmUsage.statistics_for_family),
# with the per-model and per-day breakdowns the API adds. Days are the
# current Time.zone's, which API requests set to the family's.
class LlmUsage::Report
  attr_reader :start_date, :end_date

  def initialize(family, start_date:, end_date:)
    @family = family
    @start_date = start_date
    @end_date = end_date
  end

  def statistics
    @statistics ||= LlmUsage.statistics_for_family(family, start_date: range.begin, end_date: range.end)
  end

  def by_model
    breakdown(:model).map { |model, totals| totals.merge(model: model) }.sort_by { |row| [ -row[:cost], row[:model].to_s ] }
  end

  def by_day
    day = Arel.sql("DATE(llm_usages.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{LlmUsage.connection.quote(Time.zone.tzinfo.name)})")
    breakdown(day).map { |date, totals| totals.merge(date: date) }.sort_by { |row| row[:date] }
  end

  private
    attr_reader :family

    def range
      start_date.beginning_of_day..end_date.end_of_day
    end

    def scope
      LlmUsage.for_family(family).for_date_range(range.begin, range.end)
    end

    # Requests and tokens count every call; cost only those with one, as the
    # web's totals do.
    def breakdown(group)
      rows = scope.group(group).pluck(
        group,
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(estimated_cost)"),
        Arel.sql("COALESCE(SUM(prompt_tokens), 0)"),
        Arel.sql("COALESCE(SUM(completion_tokens), 0)"),
        Arel.sql("COALESCE(SUM(total_tokens), 0)"),
        Arel.sql("COALESCE(SUM(estimated_cost), 0)")
      )

      rows.map do |key, requests, requests_with_cost, prompt_tokens, completion_tokens, total_tokens, cost|
        [ key, {
          total_requests: requests,
          requests_with_cost: requests_with_cost,
          total_prompt_tokens: prompt_tokens.to_i,
          total_completion_tokens: completion_tokens.to_i,
          total_tokens: total_tokens.to_i,
          cost: cost.to_d
        } ]
      end
    end
end
