# frozen_string_literal: true

# Skill-layer quality gates: regression, contracts, drift, noise, perf smoke.
# Deterministic; no external APIs. See docs/AI_SKILLS_FRAMEWORK.md and docs/AI_CI_QUALITY_GATES.md
namespace :ai do
  namespace :skills do
    desc 'Run all skill quality gates (same paths as CI ai_skills_quality job)'
    task ci: :environment do
      abort 'Use RAILS_ENV=test. Example: RAILS_ENV=test bundle exec rake ai:skills:ci' unless Rails.env.test?

      require 'rspec/core'

      paths = %w[
        spec/ai/skills/
        spec/ai/evals/skills/
      ]

      exit_code = RSpec::Core::Runner.run(paths + ['--format', 'documentation'])
      exit(exit_code == 0 ? 0 : 1)
    end

    desc 'Skill regression scenarios only'
    task regression: :environment do
      abort 'Use RAILS_ENV=test' unless Rails.env.test?

      require 'rspec/core'
      exit RSpec::Core::Runner.run(['spec/ai/skills/regression/', '--format', 'documentation']) == 0 ? 0 : 1
    end

    desc 'Skill metadata / contract specs only'
    task contracts: :environment do
      abort 'Use RAILS_ENV=test' unless Rails.env.test?

      require 'rspec/core'
      exit RSpec::Core::Runner.run(['spec/ai/skills/contracts/', '--format', 'documentation']) == 0 ? 0 : 1
    end

    desc 'Skill perf smoke (CI-safe structural checks)'
    task perf: :environment do
      abort 'Use RAILS_ENV=test' unless Rails.env.test?

      require 'rspec/core'
      exit RSpec::Core::Runner.run(
        ['spec/ai/skills/performance/', '--tag', '~perf_local', '--format', 'documentation']
      ) == 0 ? 0 : 1
    end

    desc 'Agent profile drift + noise rule specs'
    task drift: :environment do
      abort 'Use RAILS_ENV=test' unless Rails.env.test?

      require 'rspec/core'
      exit RSpec::Core::Runner.run(
        %w[spec/ai/skills/drift/ spec/ai/skills/noise/ --format documentation]
      ) == 0 ? 0 : 1
    end

    desc 'Local wall-clock perf ratio (set RUN_PERF_LOCAL=1); see spec/ai/skills/performance/'
    task 'perf:local' => :environment do
      abort 'Use RAILS_ENV=test' unless Rails.env.test?
      ENV['RUN_PERF_LOCAL'] = '1'

      require 'rspec/core'
      exit RSpec::Core::Runner.run(
        ['spec/ai/skills/performance/', '--tag', 'perf_local', '--format', 'documentation']
      ) == 0 ? 0 : 1
    end
  end
end
