# frozen_string_literal: true

module AiMoneyHelper
  # Format cents as dollar string, e.g. 1234 -> "$12.34"
  def self.format_cents(cents)
    return '$0.00' if cents.nil? || cents == 0
    sign = cents < 0 ? '-' : ''
    "#{sign}$#{format('%.2f', cents.abs / 100.0)}"
  end
end
