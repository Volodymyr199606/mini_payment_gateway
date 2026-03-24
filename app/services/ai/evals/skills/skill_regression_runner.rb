# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Loads skill regression scenarios (YAML) and runs them through ScenarioRunner.
      # Scenarios may include must_not_include_skills, max_invoked_skills, etc.
      # See spec/fixtures/ai/skill_regression_scenarios.yml
      class SkillRegressionRunner
        DEFAULT_FIXTURE_PATH = Rails.root.join('spec/fixtures/ai/skill_regression_scenarios.yml')

        class << self
          def load_scenarios(path = nil)
            Ai::Evals::ScenarioRunner.load_scenarios(path || DEFAULT_FIXTURE_PATH, scenarios_key: 'skill_regression_scenarios')
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
            puts "\nSkill regression: #{passed}/#{total} passed, #{failed} failed"
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
