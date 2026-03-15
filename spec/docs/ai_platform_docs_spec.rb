# frozen_string_literal: true

require 'rails_helper'

# Sanity check: key internal AI platform docs exist. Keeps doc set discoverable.
RSpec.describe 'AI platform docs' do
  let(:docs_root) { Rails.root.join('docs') }

  it 'has AI_PLATFORM.md' do
    expect(File).to exist(docs_root.join('AI_PLATFORM.md'))
  end

  it 'has AI_REQUEST_FLOW.md' do
    expect(File).to exist(docs_root.join('AI_REQUEST_FLOW.md'))
  end

  it 'has AI_EXTENSION_GUIDE.md' do
    expect(File).to exist(docs_root.join('AI_EXTENSION_GUIDE.md'))
  end

  it 'has AI_OPERATIONS.md' do
    expect(File).to exist(docs_root.join('AI_OPERATIONS.md'))
  end

  it 'has AI_SAFETY_AND_POLICY.md' do
    expect(File).to exist(docs_root.join('AI_SAFETY_AND_POLICY.md'))
  end

  it 'has AI_DEBUGGING_AND_REPLAY.md' do
    expect(File).to exist(docs_root.join('AI_DEBUGGING_AND_REPLAY.md'))
  end
end
