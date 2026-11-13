# frozen_string_literal: true

# API additions this fork (Sure+) makes on top of upstream Sure. GET /api/v1/version lists them so the
# Sure+ app can tell which endpoints the server has; a stock Sure server sends no "features" key.
module SurePlus
  module Features
    NAMES = %w[
      accounts.loan_rates
      accounts.permissions
      accounts.write
      budgets.allocations
      budgets.permissions
      budgets.write
      categories.write
      charts.series
      connections.manage
      goals
      goals.lifecycle
      goals.pledges
      goals.summary
      holdings.stable_order
      merchants.write
      profile.write
      recurring.category
      rules.apply_all
      rules.catalog
      rules.groups
      rules.reorder
      rules.write
    ].freeze
  end
end
