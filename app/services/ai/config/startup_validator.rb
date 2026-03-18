# frozen_string_literal: true

module Ai
  module Config
    # Validates AI configuration at boot. Fail fast in dev/test for invalid configs;
    # in production, log warnings and optionally allow degraded mode.
    class StartupValidator
      class ValidationError < StandardError; end
      class ValidationWarning < StandardError; end

      attr_reader :errors, :warnings

      def initialize
        @errors = []
        @warnings = []
      end

      def self.call
        new.call
      end

      def call
        validate_debug_in_production
        validate_internal_tooling_in_production
        validate_vector_requires_embeddings_hint
        validate_streaming_if_enabled
        apply_result
      end

      def valid?
        @errors.empty?
      end

      private

      def validate_debug_in_production
        return unless Rails.env.production?
        return unless FeatureFlags.ai_debug_enabled?

        # Debug in production is a security/release-safety concern unless explicitly allowed.
        if ENV['AI_DEBUG_ALLOWED_IN_PRODUCTION'].to_s.strip.downcase.in?(%w[true 1])
          @warnings << 'AI_DEBUG is enabled in production (AI_DEBUG_ALLOWED_IN_PRODUCTION=true). Ensure debug payloads never expose secrets.'
        else
          @errors << 'AI_DEBUG must not be enabled in production unless AI_DEBUG_ALLOWED_IN_PRODUCTION=true. Disable AI_DEBUG or set AI_DEBUG_ALLOWED_IN_PRODUCTION=true explicitly.'
        end
      end

      def validate_internal_tooling_in_production
        return unless Rails.env.production?
        return unless FeatureFlags.internal_tooling_available?

        # Internal tooling (playground, analytics, health, replay) is available in prod only when explicitly allowed.
        @warnings << 'Internal AI tooling (playground, analytics, health, replay) is enabled in production (AI_INTERNAL_TOOLING_ALLOWED=true). Restrict access by network/auth.'
      end

      def validate_vector_requires_embeddings_hint
        return unless FeatureFlags.ai_vector_retrieval_enabled?

        # We cannot reliably detect if embeddings are backfilled; just warn.
        @warnings << 'AI_VECTOR_RAG_ENABLED is true. Ensure pgvector is installed and doc embeddings are backfilled, or retrieval may be degraded.'
      end

      def validate_streaming_if_enabled
        return unless FeatureFlags.ai_streaming_enabled?

        # No programmatic check for streaming support; just ensure we don't have contradictory config.
        @warnings << 'AI_STREAMING_ENABLED is true. Ensure the deployment supports SSE/streaming responses.'
      end

      def apply_result
        if Rails.env.development? || Rails.env.test?
          raise ValidationError, "AI config validation failed: #{@errors.join('; ')}" if @errors.any?
        else
          # Production: log errors as fatal and warnings as warn; optionally raise on errors.
          @errors.each { |e| Rails.logger.error("[Ai::Config::StartupValidator] #{e}") }
          @warnings.each { |w| Rails.logger.warn("[Ai::Config::StartupValidator] #{w}") }
          # In production we do not raise by default so the app can boot; set AI_CONFIG_STRICT=true to fail.
          if @errors.any? && ENV['AI_CONFIG_STRICT'].to_s.strip.downcase.in?(%w[true 1])
            raise ValidationError, "AI config validation failed (AI_CONFIG_STRICT=true): #{@errors.join('; ')}"
          end
        end
        self
      end
    end
  end
end
