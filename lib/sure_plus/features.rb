# frozen_string_literal: true

# API additions this fork (Sure+) makes on top of upstream Sure. GET /api/v1/version lists them so the
# Sure+ app can tell which endpoints the server has; a stock Sure server sends no "features" key.
module SurePlus
  module Features
    NAMES = %w[
      categories.write
      holdings.stable_order
      recurring.category
    ].freeze
  end
end
