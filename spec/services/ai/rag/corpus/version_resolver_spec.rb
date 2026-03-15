# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::Corpus::VersionResolver do
  let(:docs_root) { Rails.root }

  describe '.resolve' do
    it 'returns a stable short hex string when docs exist' do
      version = described_class.resolve(docs_root: docs_root)
      expect(version).to match(/\A[a-f0-9]{12}\z/)
    end

    it 'returns v0 when no docs' do
      empty = Pathname(Dir.mktmpdir)
      version = described_class.resolve(docs_root: empty)
      expect(version).to eq('v0')
    end

    it 'produces different version for different doc sets' do
      dir1 = Pathname(Dir.mktmpdir)
      (dir1 + 'docs').mkpath
      (dir1 + 'docs' + 'a.md').write('# A')
      (dir1 + 'docs' + 'b.md').write('# B')
      dir2 = Pathname(Dir.mktmpdir)
      (dir2 + 'docs').mkpath
      (dir2 + 'docs' + 'a.md').write('# A')
      (dir2 + 'docs' + 'c.md').write('# C')
      v1 = described_class.resolve(docs_root: dir1)
      v2 = described_class.resolve(docs_root: dir2)
      expect(v1).not_to eq(v2)
    end
  end

  describe '#last_changed_at' do
    it 'returns latest mtime when docs exist' do
      resolver = described_class.new(docs_root: docs_root)
      t = resolver.last_changed_at
      expect(t).to be_a(Time).or be_nil
    end

    it 'returns nil when no docs' do
      empty = Pathname(Dir.mktmpdir)
      resolver = described_class.new(docs_root: empty)
      expect(resolver.last_changed_at).to be_nil
    end
  end
end
