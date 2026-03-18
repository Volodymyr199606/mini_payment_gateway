# frozen_string_literal: true

# Run the same AI quality gates as CI locally. No external APIs; deterministic.
# See docs/AI_CI_QUALITY_GATES.md for what each gate protects.
namespace :ai do
  desc 'Run AI quality gates (contracts, scenarios, adversarial, policy, internal tooling, docs). Same as CI.'
  task ci: :environment do
    abort 'Use RAILS_ENV=test. Example: RAILS_ENV=test bundle exec rake ai:ci' unless Rails.env.test?

    require 'rspec/core'
    require 'rspec/core/rake_task'

    gates = [
      ['AI contracts', 'spec/ai/contracts/'],
      ['AI scenarios', 'spec/ai/end_to_end_scenarios_spec.rb'],
      ['AI adversarial', 'spec/ai/adversarial_scenarios_spec.rb'],
      ['AI policy', 'spec/ai/authorization_policy_spec.rb'],
      ['AI internal tooling', 'spec/requests/dev/ai_analytics_spec.rb spec/requests/dev/ai_health_spec.rb spec/requests/dev/ai_audits_spec.rb spec/requests/dev/ai_audits_replay_spec.rb spec/requests/dev/ai_playground_spec.rb'],
      ['AI docs', 'spec/docs/ai_platform_docs_spec.rb']
    ]

    failed = []
    gates.each do |name, path|
      puts "\n--- #{name} ---"
      exit_code = RSpec::Core::Runner.run(
        path.split(/\s+/) + ['--format', 'documentation']
      )
      failed << name if exit_code != 0
    end

    if failed.any?
      warn "\n❌ AI gates failed: #{failed.join(', ')}"
      exit 1
    end

    puts "\n✅ All AI quality gates passed."
  end

  desc 'Run AI contract regression tests only'
  task 'ci:contracts' => :environment do
    abort 'Use RAILS_ENV=test' unless Rails.env.test?
    exit RSpec::Core::Runner.run(['spec/ai/contracts/', '--format', 'documentation']) == 0 ? 0 : 1
  end

  desc 'Run AI scenario tests only'
  task 'ci:scenarios' => :environment do
    abort 'Use RAILS_ENV=test' unless Rails.env.test?
    exit RSpec::Core::Runner.run(['spec/ai/end_to_end_scenarios_spec.rb', '--format', 'documentation']) == 0 ? 0 : 1
  end

  desc 'Run AI adversarial tests only'
  task 'ci:adversarial' => :environment do
    abort 'Use RAILS_ENV=test' unless Rails.env.test?
    exit RSpec::Core::Runner.run(['spec/ai/adversarial_scenarios_spec.rb', '--format', 'documentation']) == 0 ? 0 : 1
  end

  desc 'Run AI policy tests only'
  task 'ci:policy' => :environment do
    abort 'Use RAILS_ENV=test' unless Rails.env.test?
    exit RSpec::Core::Runner.run(['spec/ai/authorization_policy_spec.rb', '--format', 'documentation']) == 0 ? 0 : 1
  end

  desc 'Run AI internal tooling smoke tests only'
  task 'ci:internal_tooling' => :environment do
    abort 'Use RAILS_ENV=test' unless Rails.env.test?
    paths = %w[
      spec/requests/dev/ai_analytics_spec.rb
      spec/requests/dev/ai_health_spec.rb
      spec/requests/dev/ai_audits_spec.rb
      spec/requests/dev/ai_audits_replay_spec.rb
      spec/requests/dev/ai_playground_spec.rb
    ]
    exit RSpec::Core::Runner.run(paths + ['--format', 'documentation']) == 0 ? 0 : 1
  end

  desc 'Run AI docs consistency checks only'
  task 'ci:docs' => :environment do
    exit RSpec::Core::Runner.run(['spec/docs/ai_platform_docs_spec.rb', '--format', 'documentation']) == 0 ? 0 : 1
  end
end
