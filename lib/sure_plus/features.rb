# frozen_string_literal: true

# API additions this fork (Sure+) makes on top of upstream Sure. GET /api/v1/version lists them so the
# Sure+ app can tell which endpoints the server has; a stock Sure server sends no "features" key.
module SurePlus
  module Features
    NAMES = %w[
      accounts.write
      budgets.write
      categories.write
      connections.manage
      goals
      goals.pledges
      holdings.stable_order
      merchants.write
      profile.write
      recurring.category
      rules.apply_all
      rules.groups
      rules.reorder
      rules.write
    ].freeze
  end
end
