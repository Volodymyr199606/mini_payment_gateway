# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::SkillDefinition do
  it 'rejects unknown dependency keys' do
    expect do
      described_class.new(
        key: :bad,
        class_name: 'Bad',
        dependencies: [:retrieval, :not_a_real_dependency]
      )
    end.to raise_error(ArgumentError, /unknown dependencies/)
  end

  it 'exposes dependency predicates' do
    d = described_class.new(
      key: :t,
      class_name: 'T',
      dependencies: %i[retrieval tools],
      deterministic: true
    )
    expect(d.depends_on_retrieval?).to be(true)
    expect(d.depends_on_tools?).to be(true)
    expect(d.depends_on_memory?).to be(false)
  end
end
