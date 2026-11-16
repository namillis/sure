# frozen_string_literal: true

module SurePlus
  # Providers whose web connect form only asks for a token or API key, so the Sure+ app can create
  # them natively. Every other provider is connected through the web handoff.
  module TokenProviders
    KEYS = %w[
      binance
      brex
      coinspot
      ibkr
      kraken
      lunchflow
      mercury
      onchain_wallet
      simplefin
      wise
    ].freeze
  end
end
