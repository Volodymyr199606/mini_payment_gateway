# frozen_string_literal: true

module Ai
  module Performance
    # Merchant-safe cache key builders. All keys prefixed with ai/ to avoid collisions.
    class CacheKeys
      PREFIX = 'ai'

      class << self
        # Retrieval: message + agent + mode + corpus version (cache invalidates when docs change)
        def retrieval(message:, agent_key: nil, graph_enabled: false, vector_enabled: false, doc_version: nil)
          norm = normalize_message(message)
          parts = [PREFIX, 'ret', norm, (agent_key || 'none').to_s]
          parts << 'g' if graph_enabled
          parts << 'v' if vector_enabled
          parts << (doc_version.to_s.presence || doc_version_default)
          safe_key(parts)
        end

        # Tool: merchant_id + tool_name + normalized args
        def tool(merchant_id:, tool_name:, args: {})
          norm_args = normalize_tool_args(tool_name, args)
          parts = [PREFIX, 'tool', merchant_id, tool_name, norm_args]
          safe_key(parts)
        end

        # Memory/context: session-scoped
        def memory(session_id:, messages_count:)
          parts = [PREFIX, 'mem', session_id, messages_count]
          safe_key(parts)
        end

        def safe_key(parts)
          joined = parts.map(&:to_s).reject(&:blank?).join(':')
          return 'ai:empty' if joined.blank?
          # Digest for long keys; keep readable prefix for debugging
          if joined.length > 200
            digest = Digest::SHA256.hexdigest(joined)[0, 16]
            "#{PREFIX}:#{digest}"
          else
            joined
          end
        end

        # Safe fingerprint for observability (not the full key)
        def fingerprint(key)
          return nil if key.blank?
          Digest::SHA256.hexdigest(key.to_s)[0, 8]
        end

        private

        def normalize_message(msg)
          return '' if msg.blank?
          s = msg.to_s.strip.downcase.gsub(/\s+/, ' ')
          s.length > 500 ? "#{s[0, 500]}:#{s.length}" : s
        end

        def normalize_tool_args(tool_name, args)
          h = args.to_h.stringify_keys
          case tool_name.to_s
          when 'get_merchant_account'
            'ma' # args are empty
          when 'get_ledger_summary'
            # from, to, preset, currency
            parts = [h['from'].to_s[0, 30], h['to'].to_s[0, 30], h['preset'].to_s, (h['currency'] || 'USD').to_s.upcase]
            parts.join('|')
          else
            Digest::SHA256.hexdigest(h.sort.to_json)[0, 16]
          end
        end

        def doc_version_default
          ENV['AI_CACHE_DOC_VERSION'].presence || 'v1'
        end
      end
    end
  end
end
