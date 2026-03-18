# frozen_string_literal: true

module Ai
  module Followups
    # Rule-based follow-up detection and context resolution.
    # No LLM; deterministic. Extracts prior entities, time range, topic, filters from recent conversation.
    class Resolver
      FOLLOWUP_TYPES = %i[
        entity_followup
        time_range_adjustment
        result_filtering
        explanation_rewrite
        topic_continuation
        ambiguous_followup
      ].freeze

      # Pronouns and references suggesting continuation
      REFERENCE_WORDS = /\b(that|it|those|this|same|them)\b/i
      # Time adjustment phrases (standalone or combined)
      TIME_ADJUSTMENT = /\b(yesterday|today|last\s+week|last\s+7\s+days|last\s+month|this\s+month|same\s+range|previous\s+period|same\s+period)\b/i
      # Filtering language
      FILTER_PHRASES = /\b(only\s+(?:failed|refunds?|captures?|succeeded)|just\s+(?:failed|refunds?|the\s+important|failed\s+ones)|failed\s+ones?|just\s+refunds?)\b/i
      # Explanation style adjustments
      EXPLAIN_PHRASES = /\b(simpler|shorter|more\s+detailed|more\s+technical|bullet\s+points?|in\s+simple\s+terms|explain\s+that\s+more|what\s+does\s+that\s+mean|only\s+(?:the\s+)?important\s+part)\b/i
      # Continuation questions
      CONTINUATION_PHRASES = /\b(was\s+it\s+(?:captured|refunded|voided|authorized)|what\s+happened\s+next|what\s+about\s+retries?|and\s+then|after\s+that)\b/i

      def self.call(current_message:, recent_messages: [])
        new(current_message: current_message, recent_messages: recent_messages).call
      end

      def initialize(current_message:, recent_messages: [])
        @msg = current_message.to_s.strip
        @recent = Array(recent_messages).map { |m| { role: m[:role].to_s, content: m[:content].to_s } }
      end

      def call
        if @msg.blank? || @recent.size < 2
          return no_followup_result
        end

        prior_user, prior_assistant = last_pair
        return no_followup_result unless prior_user && prior_assistant

        detected = detect_followup_type
        return no_followup_result unless detected

        prior_intent = extract_prior_intent(prior_user[:content])
        prior_time = extract_prior_time_range(prior_user[:content])
        prior_topic = resolve_prior_topic(prior_user[:content], prior_assistant[:content])
        prior_agent = prior_assistant[:agent].to_s.presence

        inherited = build_inherited(detected, prior_intent, prior_time, prior_topic)
        response_style = extract_response_style if detected[:type] == :explanation_rewrite

        {
          original_message: @msg,
          followup_detected: true,
          resolved_message_or_context: build_resolved_message(prior_user[:content], inherited),
          inherited_entities: inherited[:entities] || {},
          inherited_time_range: inherited[:time_range],
          inherited_topic: inherited[:topic],
          inherited_filters: inherited[:filters] || [],
          followup_type: detected[:type],
          confidence: detected[:confidence],
          response_style_adjustments: response_style,
          prior_intent: prior_intent&.dig(:tool_name),
          prior_agent_hint: prior_agent
        }
      end

      private

      def no_followup_result
        {
          original_message: @msg,
          followup_detected: false,
          resolved_message_or_context: @msg,
          inherited_entities: {},
          inherited_time_range: nil,
          inherited_topic: nil,
          inherited_filters: [],
          followup_type: nil,
          confidence: 0
        }
      end

      def last_pair
        # Recent is chronological (oldest first). Current user message is last in array.
        # We need the previous user + assistant pair (the turn before current).
        users = @recent.each_with_index.select { |m, _| m[:role] == 'user' }
        return [nil, nil] if users.size < 2

        prev_user_idx = users[-2][1]
        prev_user = @recent[prev_user_idx]
        after = @recent[(prev_user_idx + 1)..]
        prev_assistant = after&.find { |m| m[:role] == 'assistant' }
        [prev_user, prev_assistant]
      end

      def last_user_content
        pair = last_pair
        pair[0]&.dig(:content).to_s
      end

      def last_assistant_content
        pair = last_pair
        pair[1]&.dig(:content).to_s
      end

      def detect_followup_type
        lower = @msg.downcase.strip
        return nil if lower.length > 150 # Long messages rarely pure follow-ups

        # Short message with references
        has_ref = REFERENCE_WORDS.match?(lower)
        mentions_entity = lower.match?(/\b(transaction|payment\s+intent|webhook\s+event)\b/i)
        has_time = TIME_ADJUSTMENT.match?(lower)
        has_filter = FILTER_PHRASES.match?(lower)
        has_explain = EXPLAIN_PHRASES.match?(lower)
        has_continuation = CONTINUATION_PHRASES.match?(lower)

        if has_time && (lower.split.size <= 8)
          { type: :time_range_adjustment, confidence: 0.85 }
        elsif has_ref && mentions_entity
          # Examples we want to recognize:
          # - "Use that transaction from the previous session"
          # - "Use same payment intent from before after merchant/session switch"
          { type: :entity_followup, confidence: 0.9 }
        elsif has_ref && has_continuation
          { type: :entity_followup, confidence: 0.9 }
        elsif has_ref && has_filter
          { type: :result_filtering, confidence: 0.85 }
        elsif has_explain || lower.match?(/\b(explain|simplify|simpler|shorter|what\s+does\s+that)\b/i)
          { type: :explanation_rewrite, confidence: 0.85 }
        elsif has_filter && lower.split.size <= 10
          { type: :result_filtering, confidence: 0.8 }
        elsif has_ref && lower.split.size <= 6
          { type: :ambiguous_followup, confidence: 0.5 }
        elsif lower.match?(/\bwhat\s+about\b/i) && lower.split.size <= 12
          { type: :topic_continuation, confidence: 0.75 }
        elsif has_ref || has_time || has_filter
          { type: :ambiguous_followup, confidence: 0.5 }
        else
          nil
        end
      end

      def extract_prior_intent(prior_user_content)
        return nil if prior_user_content.blank?

        ::Ai::Tools::IntentDetector.detect(prior_user_content)
      end

      def extract_prior_time_range(prior_user_content)
        return nil if prior_user_content.blank?

        result = ::Ai::TimeRangeParser.extract_and_parse(prior_user_content)
        return nil if result[:inferred] && result[:default_used] == 'all_time'

        { from: result[:from], to: result[:to], range_label: result[:range_label] }
      rescue ::Ai::TimeRangeParser::ParseError
        nil
      end

      def resolve_prior_topic(user_content, assistant_content)
        combined = [user_content, assistant_content].join(' ')
        ::Ai::Conversation::CurrentTopicDetector.call([{ role: 'user', content: combined }])
      end

      def build_inherited(detected, prior_intent, prior_time, prior_topic)
        inherited = { entities: {}, time_range: nil, topic: prior_topic, filters: [] }

        case detected[:type]
        when :entity_followup
          inherited[:entities] = prior_intent&.dig(:args) || {}
        when :time_range_adjustment
          inherited[:time_range] = resolve_current_time_range
          inherited[:entities] = prior_intent&.dig(:args)&.slice(:from, :to) ? {} : (prior_intent&.dig(:args) || {})
          inherited[:topic] = prior_topic
        when :result_filtering
          inherited[:filters] = extract_filter_hints
          inherited[:entities] = prior_intent&.dig(:args) || {}
          inherited[:time_range] = prior_time
        when :explanation_rewrite, :topic_continuation
          inherited[:topic] = prior_topic
          inherited[:entities] = prior_intent&.dig(:args) || {}
          inherited[:time_range] = prior_time
        when :ambiguous_followup
          # Conservative: only inherit when high confidence
          inherited[:topic] = prior_topic if detected[:confidence] >= 0.6
        end

        inherited
      end

      def resolve_current_time_range
        result = ::Ai::TimeRangeParser.extract_and_parse(@msg)
        { from: result[:from], to: result[:to], range_label: result[:range_label] }
      rescue ::Ai::TimeRangeParser::ParseError
        nil
      end

      def extract_filter_hints
        lower = @msg.downcase
        hints = []
        hints << 'failed' if lower.include?('failed')
        hints << 'refund' if lower.include?('refund')
        hints << 'capture' if lower.include?('capture')
        hints
      end

      def extract_response_style
        lower = @msg.downcase
        styles = []
        styles << :simpler if lower.match?(/\b(simpler|simple|simply)\b/)
        styles << :shorter if lower.match?(/\b(shorter|brief|concise)\b/)
        styles << :more_detailed if lower.match?(/\b(more\s+detailed|detail|expand)\b/)
        styles << :more_technical if lower.match?(/\b(more\s+technical|technical)\b/)
        styles << :bullet_points if lower.match?(/\b(bullet|bullets|list)\b/)
        styles << :only_important if lower.match?(/\b(important\s+part|key\s+points|just\s+the\s+important)\b/)
        styles
      end

      def build_resolved_message(prior_user_content, inherited)
        # For tool path: we return context usable by IntentResolver, not a rewritten user message.
        parts = [prior_user_content, @msg].compact
        parts.join(' [follow-up: ')
      end
    end
  end
end
