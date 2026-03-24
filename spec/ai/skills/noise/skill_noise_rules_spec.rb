# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Evals::Skills::SkillNoiseRules do
  describe '.followup_rewriter_without_style_path?' do
    it 'flags rewriter when not in style path' do
      expect(described_class.followup_rewriter_without_style_path?(%i[followup_rewriter], style_only: false)).to be(true)
    end

    it 'allows rewriter on style path' do
      expect(described_class.followup_rewriter_without_style_path?(%i[followup_rewriter], style_only: true)).to be(false)
    end
  end

  describe '.heavy_on_trivial_support?' do
    it 'detects heavy skills on trivial support' do
      expect(described_class.heavy_on_trivial_support?(%i[discrepancy_detector], trivial: true)).to be(true)
    end
  end

  describe '.too_many_slots_filled?' do
    it 'flags excess slots' do
      expect(described_class.too_many_slots_filled?(5, max_slots: 3)).to be(true)
    end
  end
end
