# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::RequestPlanner do
  let(:merchant_id) { 1 }

  describe '.plan' do
    context 'when intent is present (deterministic path)' do
      it 'returns deterministic_only plan with skip_retrieval and skip_memory' do
        intent = { tool_name: 'get_payment_intent', args: { payment_intent_id: 123 } }
        resolution = { intent: intent, followup: {} }

        plan = described_class.plan(
          message: 'What is the status of pi_123?',
          intent_resolution: resolution,
          agent_key: nil
        )

        expect(plan.execution_mode).to eq(:deterministic_only)
        expect(plan.skip_retrieval).to be true
        expect(plan.skip_memory).to be true
        expect(plan.skip_orchestration).to be false
        expect(plan.reason_codes).to include('intent_present', 'deterministic_sufficient')
        expect(plan.metadata[:tool_name]).to eq('get_payment_intent')
      end

      it 'returns deterministic plan for get_ledger_summary intent' do
        intent = { tool_name: 'get_ledger_summary', args: { start_date: '2024-01-01', end_date: '2024-01-31' } }
        resolution = { intent: intent, followup: { followup_detected: false } }

        plan = described_class.plan(message: 'Net volume yesterday?', intent_resolution: resolution)

        expect(plan.execution_mode).to eq(:deterministic_only)
        expect(plan.skip_retrieval).to be true
        expect(plan.skip_memory).to be true
      end

      it 'returns deterministic plan for get_merchant_account' do
        intent = { tool_name: 'get_merchant_account', args: {} }
        plan = described_class.plan(
          message: 'Show my account info',
          intent_resolution: { intent: intent, followup: {} }
        )
        expect(plan.execution_mode).to eq(:deterministic_only)
        expect(plan.skip_retrieval).to be true
      end
    end

    context 'when no intent (agent path)' do
      it 'returns agent_full for docs question without followup' do
        resolution = { intent: nil, followup: { followup_detected: false } }

        plan = described_class.plan(
          message: 'How do refunds work?',
          intent_resolution: resolution,
          agent_key: :support_faq
        )

        expect(plan.execution_mode).to eq(:agent_full)
        expect(plan.skip_retrieval).to be false
        expect(plan.skip_memory).to be false
        expect(plan.skip_orchestration).to be true
      end

      it 'skips memory for standalone reporting_calculation request' do
        resolution = { intent: nil, followup: { followup_detected: false } }

        plan = described_class.plan(
          message: 'What was my net volume last month?',
          intent_resolution: resolution,
          agent_key: :reporting_calculation
        )

        expect(plan.skip_memory).to be true
        expect(plan.reason_codes).to include('standalone_no_followup')
      end

      it 'skips retrieval for agent with supports_retrieval false (reporting_calculation)' do
        resolution = { intent: nil, followup: { followup_detected: false } }

        plan = described_class.plan(
          message: 'What was my net volume last month?',
          intent_resolution: resolution,
          agent_key: :reporting_calculation
        )

        expect(plan.skip_retrieval).to be true
        expect(plan.reason_codes).to include('agent_no_retrieval')
      end

      it 'skips memory for standalone operational request' do
        resolution = { intent: nil, followup: { followup_detected: false } }

        plan = described_class.plan(
          message: 'How do I set up webhooks?',
          intent_resolution: resolution,
          agent_key: :operational
        )

        expect(plan.skip_memory).to be true
      end

      it 'does not skip memory for follow-up request' do
        resolution = {
          intent: nil,
          followup: {
            followup_detected: true,
            followup_type: :time_range_adjustment,
            inherited_time_range: { range_label: 'yesterday' }
          }
        }

        plan = described_class.plan(
          message: 'What about yesterday?',
          intent_resolution: resolution,
          agent_key: :reporting_calculation
        )

        expect(plan.skip_memory).to be false
        expect(plan.execution_mode).to eq(:agent_full)
      end

      it 'uses concise_rewrite_only for short explanation_rewrite follow-up' do
        resolution = {
          intent: nil,
          followup: {
            followup_detected: true,
            followup_type: :explanation_rewrite,
            prior_intent: 'support_faq',
            inherited_entities: {}
          }
        }

        plan = described_class.plan(
          message: 'shorter',
          intent_resolution: resolution,
          agent_key: :support_faq
        )

        expect(plan.execution_mode).to eq(:concise_rewrite_only)
        expect(plan.retrieval_budget_reduced).to be true
        expect(plan.reason_codes).to include('concise_rewrite')
      end

      it 'uses concise_rewrite for "bullet points"' do
        resolution = {
          intent: nil,
          followup: {
            followup_detected: true,
            followup_type: :explanation_rewrite,
            prior_intent: 'support_faq'
          }
        }

        plan = described_class.plan(
          message: 'give me bullet points',
          intent_resolution: resolution,
          agent_key: :support_faq
        )

        expect(plan.retrieval_budget_reduced).to be true
        expect(plan.reason_codes).to include('concise_rewrite')
      end

      it 'does not use concise_rewrite when message is too long' do
        resolution = {
          intent: nil,
          followup: {
            followup_detected: true,
            followup_type: :explanation_rewrite,
            prior_intent: 'support_faq'
          }
        }

        long_msg = 'Could you please rephrase that in a simpler way with more detail and bullet points and summarize the key takeaways?'
        plan = described_class.plan(message: long_msg, intent_resolution: resolution, agent_key: :support_faq)

        expect(plan.execution_mode).to eq(:agent_full)
        expect(plan.retrieval_budget_reduced).to be false
      end

      it 'does not use concise_rewrite when followup_type is not explanation_rewrite' do
        resolution = {
          intent: nil,
          followup: {
            followup_detected: true,
            followup_type: :time_range_adjustment,
            prior_intent: 'get_ledger_summary'
          }
        }

        plan = described_class.plan(message: 'shorter', intent_resolution: resolution, agent_key: :reporting_calculation)

        expect(plan.execution_mode).to eq(:agent_full)
        expect(plan.retrieval_budget_reduced).to be false
      end

      it 'infers agent_key when not provided' do
        allow(Ai::Router).to receive(:new).and_return(double(call: :support_faq))
        resolution = { intent: nil, followup: { followup_detected: false } }

        plan = described_class.plan(message: 'How do refunds work?', intent_resolution: resolution, agent_key: nil)

        expect(Ai::Router).to have_received(:new)
        expect(plan).to be_present
      end
    end

    context 'conservative behavior when ambiguous' do
      it 'does not skip retrieval for conceptual docs question' do
        plan = described_class.plan(
          message: 'What is 3DS and how does it work?',
          intent_resolution: { intent: nil, followup: {} },
          agent_key: :support_faq
        )
        expect(plan.skip_retrieval).to be false
      end

      it 'does not skip memory for support_faq when standalone (support_faq keeps memory)' do
        plan = described_class.plan(
          message: 'How do I handle chargebacks?',
          intent_resolution: { intent: nil, followup: { followup_detected: false } },
          agent_key: :support_faq
        )
        expect(plan.skip_memory).to be false
      end
    end
  end
end
