# frozen_string_literal: true

module Ai
  module Streaming
    # Accepts chunks from the generation layer, forwards them, and accumulates the final message.
    # Use for audit, citations, persistence, and debug metadata.
    class ResponseStreamer
      attr_reader :full_content

      def initialize
        @full_content = +''
      end

      # Call for each chunk; optionally pass a block to forward (e.g. write to SSE).
      def <<(chunk)
        delta = chunk.to_s
        return if delta.empty?

        @full_content << delta
        yield delta if block_given?
      end

      # Append bulk content (e.g. from non-streaming fallback).
      def append_all(content)
        text = content.to_s
        return if text.empty?

        @full_content << text
        yield text if block_given?
      end
    end
  end
end
