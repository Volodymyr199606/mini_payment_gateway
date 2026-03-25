# frozen_string_literal: true

module Ai
  module Skills
    module ValueAnalysis
      # Evidence from checked-in YAML eval scenarios (skill + regression) — which skills are
      # contract-tested and how often. Does not measure runtime; complements audit metrics.
      class ScenarioScorecard
        DEFAULT_FIXTURES = %w[
          spec/fixtures/ai/skill_scenarios.yml
          spec/fixtures/ai/skill_regression_scenarios.yml
        ].freeze

        class << self
          # @return [Hash] coverage: skill_key => { scenario_ids:, scenario_count: }
          def coverage_from_fixtures(fixture_relative_paths: DEFAULT_FIXTURES)
            skill_refs = Hash.new { |h, k| h[k] = [] }

            fixture_relative_paths.each do |rel|
              path = Rails.root.join(rel)
              next unless File.exist?(path)

              data = YAML.load_file(path)
              scenarios = Array(data['skill_scenarios']) + Array(data['skill_regression_scenarios'])
              scenarios.each do |s|
                id = s['id'] || s[:id]
                next if id.blank?

                Array(s['expected_skill_keys'] || s[:expected_skill_keys]).each do |sk|
                  skill_refs[sk.to_s] << id.to_s
                end
              end
            end

            skill_refs.transform_values do |ids|
              u = ids.uniq
              { scenario_ids: u, scenario_count: u.size }
            end
          end

          # @param results [Array<Hash>] e.g. from batch eval runner: { scenario_id:, passed_overall: ... }
          # @return [Hash] pass rates per scenario id
          def eval_pass_rates_by_scenario(results)
            return {} if results.blank?

            results.each_with_object({}) do |r, h|
              id = r[:scenario_id] || r['scenario_id']
              next if id.blank?

              h[id.to_s] = !!r[:passed_overall] || !!r['passed_overall']
            end
          end

          def summary
            cov = coverage_from_fixtures
            {
              skills_covered: cov.keys.sort,
              total_scenario_skill_slots: cov.values.sum { |v| v[:scenario_count] },
              fixture_paths_resolved: DEFAULT_FIXTURES.count { |rel| File.exist?(Rails.root.join(rel)) }
            }
          end

        end
      end
    end
  end
end
