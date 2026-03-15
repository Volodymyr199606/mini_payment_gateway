# frozen_string_literal: true

module Ai
  # Internal AI interface contracts and schema versions.
  # Use these when building or consuming payloads across layers.
  module Contracts
    # Schema/contract versions for persisted or cross-layer payloads.
    TOOL_RESULT_VERSION = '1'
    RETRIEVAL_RESULT_VERSION = '1'
    COMPOSED_RESPONSE_VERSION = '1'
    AUDIT_PAYLOAD_VERSION = '1'
    DEBUG_PAYLOAD_VERSION = '1'
    EXECUTION_PLAN_VERSION = '1'
    RUN_RESULT_VERSION = '1'
    PARSED_INTENT_VERSION = '1'
    INTENT_RESOLUTION_VERSION = '1'
  end
end
