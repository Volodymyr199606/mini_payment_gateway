# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::BaseSkill do
  it 'raises NotImplementedError when subclass does not implement execute' do
    klass = Class.new(described_class)
    expect { klass.new.execute(context: {}) }.to raise_error(NotImplementedError)
  end
end
