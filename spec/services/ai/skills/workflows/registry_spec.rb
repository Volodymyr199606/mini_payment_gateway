# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Workflows::Registry do
  describe '.definitions' do
    it 'registers known workflows with unique keys' do
      expect(described_class.definitions.keys).to contain_exactly(
        :payment_explain_with_docs,
        :reconciliation_analysis_workflow,
        :webhook_failure_analysis_workflow,
        :rewrite_response_workflow
      )
    end

    it 'validate! passes' do
      expect(described_class.validate!).to be(true)
    end
  end
end
