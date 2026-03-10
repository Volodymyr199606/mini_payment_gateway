# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Evals::Runner do
  include ApiHelpers

  # Stub merchant (runner only needs merchant.id for reporting agent). Use real merchant in golden_eval_spec.
  let(:merchant) { double('Merchant', id: 1) }
  let(:fixture_path) { Rails.root.join('spec/fixtures/ai/golden_questions.yml') }

  before do
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
    stub_groq = instance_double(
      Ai::GroqClient,
      chat: { content: 'Stub reply for eval. No external API.', model_used: 'eval', fallback_used: false }
    )
    allow(Ai::GroqClient).to receive(:new).and_return(stub_groq)
    ledger_stub = {
      currency: 'USD',
      from: '2025-01-01T00:00:00Z',
      to: '2025-01-08T23:59:59Z',
      totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 75_00 },
      counts: { captures_count: 10, refunds_count: 2 }
    }
    allow(Reporting::LedgerSummary).to receive(:new).and_return(
      instance_double(Reporting::LedgerSummary, call: ledger_stub)
    )
  end

  describe '.load_questions' do
    it 'loads YAML and returns array of case hashes' do
      skip 'fixture missing' unless fixture_path.exist?
      cases = described_class.load_questions(fixture_path)
      expect(cases).to be_an(Array)
      expect(cases.size).to be >= 25
    end

    it 'each case has id, question, expected_agent, must_include, must_not_include' do
      skip 'fixture missing' unless fixture_path.exist?
      cases = described_class.load_questions(fixture_path)
      cases.each do |c|
        expect(c).to be_a(Hash)
        expect(c[:expected_agent]).to be_present
        expect(c[:question]).to be_present
        expect(c[:must_include]).to be_an(Array)
        expect(c[:must_not_include]).to be_an(Array)
      end
    end

    it 'includes all six agent categories' do
      skip 'fixture missing' unless fixture_path.exist?
      cases = described_class.load_questions(fixture_path)
      agents = cases.map { |c| c[:expected_agent].to_sym }.uniq
      expect(agents).to contain_exactly(
        :support_faq,
        :security_compliance,
        :developer_onboarding,
        :operational,
        :reconciliation_analyst,
        :reporting_calculation
      )
    end
  end

  describe '.run_one' do
    it 'returns structured result with passed_* and metadata' do
      case_hash = {
        id: 'test-1',
        question: 'What can you help me with?',
        expected_agent: :support_faq,
        must_include: [],
        must_not_include: [],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:id]).to eq('test-1')
      expect(result[:question]).to be_present
      expect(result[:expected_agent]).to eq(:support_faq)
      expect(result).to include(:actual_agent, :passed_agent_match, :passed_required_content,
                               :passed_forbidden_content, :passed_citations, :passed_overall,
                               :response_excerpt, :citations_count, :metadata)
      expect(result[:passed_overall]).to be(true).or be(false)
    end

    it 'passes agent match when router returns expected agent' do
      case_hash = {
        id: 'test-2',
        question: 'How do refunds work?',
        expected_agent: :operational,
        must_include: [],
        must_not_include: [],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_agent_match]).to be(true)
      expect(result[:actual_agent]).to eq(:operational)
    end

    it 'fails agent match when injected router returns different agent' do
      case_hash = {
        id: 'test-3',
        question: 'How do refunds work?',
        expected_agent: :support_faq,
        must_include: [],
        must_not_include: [],
        require_citations: false,
        deterministic: false
      }
      router = ->(_msg) { :operational }
      result = described_class.run_one(case_hash, merchant_id: merchant.id, router: router)
      expect(result[:passed_agent_match]).to be(false)
      expect(result[:actual_agent]).to eq(:operational)
      expect(result[:passed_overall]).to be(false)
    end

    it 'passes required_content when reply contains all must_include phrases' do
      case_hash = {
        id: 'rep-test',
        question: 'How much last 7 days?',
        expected_agent: :reporting_calculation,
        must_include: ['Charges', 'Net'],
        must_not_include: [],
        require_citations: false,
        deterministic: true
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_required_content]).to be(true)
      expect(result[:response_excerpt]).to include('Charges')
      expect(result[:response_excerpt]).to include('Net')
    end

    it 'fails required_content when reply misses a must_include phrase' do
      case_hash = {
        id: 'stub-miss',
        question: 'What can you help with?',
        expected_agent: :support_faq,
        must_include: ['DefinitelyNotInStubReply123'],
        must_not_include: [],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_required_content]).to be(false)
      expect(result[:passed_overall]).to be(false)
    end

    it 'passes forbidden_content when reply contains none of must_not_include' do
      case_hash = {
        id: 'stub-forbidden-ok',
        question: 'What can you help with?',
        expected_agent: :support_faq,
        must_include: [],
        must_not_include: ['NeverSayThisWordXYZ'],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_forbidden_content]).to be(true)
    end

    it 'fails forbidden_content when reply contains must_not_include phrase' do
      groq_with_bad = instance_double(
        Ai::GroqClient,
        chat: { content: 'Here is NeverSayThisWordXYZ in the reply.', model_used: 'eval', fallback_used: false }
      )
      allow(Ai::GroqClient).to receive(:new).and_return(groq_with_bad)
      case_hash = {
        id: 'stub-forbidden-fail',
        question: 'What can you help with?',
        expected_agent: :support_faq,
        must_include: [],
        must_not_include: ['NeverSayThisWordXYZ'],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_forbidden_content]).to be(false)
      expect(result[:passed_overall]).to be(false)
    end

    it 'citation requirement: require_citations true with no citations fails' do
      retrieval = ->(_msg, _agent_key) { { context_text: nil, citations: [] } }
      case_hash = {
        id: 'cite-fail',
        question: 'What is authorize vs capture?',
        expected_agent: :operational,
        must_include: [],
        must_not_include: [],
        require_citations: true,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id, retrieval: retrieval)
      expect(result[:passed_citations]).to be(false)
      expect(result[:citations_count]).to eq(0)
    end

    it 'overall pass is true only when all checks pass' do
      case_hash = {
        id: 'all-pass',
        question: 'What can you help me with?',
        expected_agent: :support_faq,
        must_include: [],
        must_not_include: [],
        require_citations: false,
        deterministic: false
      }
      result = described_class.run_one(case_hash, merchant_id: merchant.id)
      expect(result[:passed_overall]).to eq(
        result[:passed_agent_match] && result[:passed_required_content] &&
        result[:passed_forbidden_content] && result[:passed_citations]
      )
    end
  end

  describe '.run_all' do
    it 'executes all cases and returns array of results' do
      skip 'fixture missing' unless fixture_path.exist?
      results = described_class.run_all(merchant_id: merchant.id, path: fixture_path)
      expect(results.size).to eq(described_class.load_questions(fixture_path).size)
      results.each do |r|
        expect(r).to include(:id, :passed_overall, :expected_agent, :actual_agent)
      end
    end
  end

  describe '.print_summary' do
    it 'returns summary hash with total, passed, failed, failed_by_category' do
      results = [
        { id: '1', passed_overall: true, expected_agent: :support_faq, actual_agent: :support_faq, question: 'Q1', metadata: {} },
        { id: '2', passed_overall: false, expected_agent: :operational, actual_agent: :support_faq, question: 'Q2', metadata: { failure_reasons: ['agent_mismatch'] } }
      ]
      summary = described_class.print_summary(results)
      expect(summary[:total]).to eq(2)
      expect(summary[:passed]).to eq(1)
      expect(summary[:failed]).to eq(1)
      expect(summary[:failed_by_category]).to be_a(Hash)
      expect(summary[:results]).to eq(results)
    end
  end
end
