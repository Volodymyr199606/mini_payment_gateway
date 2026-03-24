# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Loads explicit per-agent role expectations (YAML) and asserts profiles/registry did not drift.
      class AgentSkillExpectations
        DEFAULT_PATH = Rails.root.join('spec/fixtures/ai/agent_skill_expectations.yml')

        class << self
          def load(path = nil)
            p = path || DEFAULT_PATH
            return {} unless p.exist?

            raw = YAML.load_file(p.to_s)
            (raw['agent_skill_expectations'] || raw[:agent_skill_expectations] || {}).deep_symbolize_keys
          end

          # @return [Array<String>] violation messages (empty if none)
          def violations(expectations = {})
            expect = expectations.presence || load
            return [] if expect.blank?

            out = []
            expect.each do |agent_key, rules|
              rules = rules.is_a?(Hash) ? rules.deep_symbolize_keys : {}
              profile = Ai::Skills::AgentProfiles.for(agent_key.to_sym)
              allowed = profile.allowed_skill_keys.map(&:to_sym)

              Array(rules[:must_not_allow]).map(&:to_sym).each do |sk|
                out << "agent #{agent_key}: must_not_allow skill #{sk} is present in AgentProfiles allowlist" if allowed.include?(sk)
              end

              Array(rules[:must_allow]).map(&:to_sym).each do |sk|
                out << "agent #{agent_key}: must_allow skill #{sk} is missing from AgentProfiles allowlist" unless allowed.include?(sk)
              end
            end
            out
          end

          def satisfied?(expectations = {})
            violations(expectations).empty?
          end
        end
      end
    end
  end
end
