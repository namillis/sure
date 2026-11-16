# frozen_string_literal: true

# API additions this fork (Sure+) makes on top of upstream Sure. GET /api/v1/version lists them so the
# Sure+ app can tell which endpoints the server has; a stock Sure server sends no "features" key.
module SurePlus
  module Features
    NAMES = %w[
      accounts.loan_rates
      accounts.permissions
      accounts.sharing
      accounts.write
      budgets.allocations
      budgets.permissions
      budgets.sharing
      budgets.write
      categories.write
      charts.series
      connections.available
      connections.manage
      connections.web_handoff
      goals
      goals.lifecycle
      goals.pledges
      goals.summary
      holdings.stable_order
      household.members
      merchants.write
      profile.write
      recurring.category
      rules.apply_all
      rules.catalog
      rules.groups
      rules.reorder
      rules.write
      settings.ai
      settings.api_keys
      settings.sync_schedule
      transactions.attachments
      transactions.convert_to_trade
      transactions.duplicates
      transactions.locks
      transactions.mark_recurring
      transactions.transfers
    ].freeze
  end
end
