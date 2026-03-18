# frozen_string_literal: true

module Ai
  module Performance
    # Central cache policy: TTLs, bypass rules, categories.
    # Prefer correctness over aggressive caching.
    class CachePolicy
      # TTLs in seconds (conservative)
      TTL_RETRIEVAL = 120      # 2 min - docs rarely change mid-session
      TTL_LEDGER = 45          # ledger data changes frequently
      TTL_MERCHANT_ACCOUNT = 60 # merchant metadata changes less often
      TTL_MEMORY = 30          # memory formatting; invalidate on new message
      TTL_OTHER_TOOL = 30      # generic tool result fallback

      CATEGORIES = %i[retrieval ledger merchant_account memory tool_other].freeze

      class << self
        def ttl_for(category)
          case category.to_s.to_sym
          when :retrieval then TTL_RETRIEVAL
          when :ledger then TTL_LEDGER
          when :merchant_account then TTL_MERCHANT_ACCOUNT
          when :memory then TTL_MEMORY
          when :tool_other then TTL_OTHER_TOOL
          else TTL_OTHER_TOOL
          end
        end

        def bypass?
          ai_debug? || cache_bypass?
        end

        def ai_debug?
          ::Ai::Config::FeatureFlags.ai_debug_enabled?
        end

        def cache_bypass?
          ::Ai::Config::FeatureFlags.ai_cache_bypass?
        end

        def cacheable_tool?(tool_name)
          defn = ::Ai::Tools::Registry.definition(tool_name)
          return defn.cacheable? if defn
          # Fallback when no definition (should not happen if registry is used)
          %w[get_merchant_account get_ledger_summary].include?(tool_name.to_s)
        end

        def tool_category(tool_name)
          case tool_name.to_s
          when 'get_merchant_account' then :merchant_account
          when 'get_ledger_summary' then :ledger
          else :tool_other
          end
        end

        # Do not cache failures unless explicitly safe (e.g. empty result).
        def cache_failure?(success:, category:)
          return false if success
          # Only cache "no data" style results; never cache errors
          false
        end
      end
    end
  end
end
