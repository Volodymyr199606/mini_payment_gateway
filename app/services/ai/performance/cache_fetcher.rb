# frozen_string_literal: true

module Ai
  module Performance
    # Fetch-or-compute with cache. Handles bypass, TTL, observability.
    class CacheFetcher
      def self.fetch(key:, category:, bypass: nil, &block)
        new(key: key, category: category, bypass: bypass).fetch(&block)
      end

      def initialize(key:, category:, bypass: nil)
        @key = key.to_s
        @category = category.to_s.to_sym
        @bypass = bypass.nil? ? CachePolicy.bypass? : !!bypass
      end

      def fetch(&block)
        return compute(:bypassed, 'policy_bypass', &block) if @bypass && block
        return compute(:bypassed, 'no_block') unless block

        cached = read
        if cached
          log(:hit, cached)
          return cached
        end

        result = block.call
        write(result) if should_write?(result)
        log(:miss, result)
        result
      end

      private

      def read
        raw = store.read(@key)
        return nil unless raw.is_a?(Hash)

        # Re-symbolize for consistency
        deep_symbolize(raw)
      end

      def write(value)
        return unless value.is_a?(Hash) || value.is_a?(Array)
        store.write(@key, value, expires_in: CachePolicy.ttl_for(@category))
      end

      def compute(reason, detail, &blk)
        result = blk ? blk.call : nil
        log(reason, result, detail: detail)
        result
      end

      def should_write?(result)
        return false unless result.is_a?(Hash)
        # Do not cache error/failure results
        return false if result[:success] == false && result[:error].present?
        true
      end

      def log(outcome, result = nil, detail: nil)
        meta = {
          cache_category: @category,
          cache_key_fingerprint: CacheKeys.fingerprint(@key),
          cache_outcome: outcome,
          cache_ttl: CachePolicy.ttl_for(@category)
        }
        meta[:cache_bypass_reason] = detail if detail
        meta[:cache_result_keys] = result.keys.map(&:to_s).take(10) if result.is_a?(Hash)
        ::Ai::Observability::EventLogger.log_cache(**meta)
        record_for_debug(@category, outcome, detail)
      end

      def store
        Rails.cache
      end

      def record_for_debug(category, outcome, detail)
        events = (Thread.current[:ai_cache_events] ||= [])
        events << { category: category, outcome: outcome, bypass_reason: detail }
        events.shift if events.size > 20 # cap
      end

      def deep_symbolize(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
        when Array
          obj.map { |v| deep_symbolize(v) }
        else
          obj
        end
      end
    end
  end
end
