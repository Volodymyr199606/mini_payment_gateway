# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Runs skill-focused scenarios. Loads from skill_scenarios.yml and delegates
      # to ScenarioRunner for execution. Scenarios assert on expected_skill_keys
      # and expected_skill_affected_response.
      class SkillScenarioRunner
        DEFAULT_FIXTURE_PATH = Rails.root.join('spec/fixtures/ai/skill_scenarios.yml')

        class << self
          def load_scenarios(path = nil)
            Ai::Evals::ScenarioRunner.load_scenarios(path || DEFAULT_FIXTURE_PATH, scenarios_key: 'skill_scenarios')
          end

          def run_one(scenario, merchant_id:, entity_ids: {})
            Ai::Evals::ScenarioRunner.run_one(scenario, merchant_id: merchant_id, entity_ids: entity_ids)
          end

          def run_all(merchant_id:, path: nil, entity_factory: nil)
            scenarios = load_scenarios(path)
            scenarios.map do |s|
              ids = entity_factory.respond_to?(:call) ? entity_factory.call(s, merchant_id) : {}
              run_one(s, merchant_id: merchant_id, entity_ids: ids)
            end
          end

          def print_summary(results)
            total = results.size
            passed = results.count { |r| r[:passed_overall] }
            failed = total - passed
            puts "\nSkill scenario eval: #{passed}/#{total} passed, #{failed} failed"
            results.reject { |r| r[:passed_overall] }.each do |r|
              puts "  [#{r[:scenario_id]}] #{r[:failure_summary] || r[:error]}"
            end
            { total: total, passed: passed, failed: failed, results: results }
          end
        end
      end
    end
  end
end
