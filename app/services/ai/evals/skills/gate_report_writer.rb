# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Writes human-readable regression/perf reports under tmp/ai_skills/
      class GateReportWriter
        DEFAULT_DIR = Rails.root.join('tmp/ai_skills')

        class << self
          def write(name:, body:)
            dir = DEFAULT_DIR
            FileUtils.mkdir_p(dir)
            path = dir.join("#{name}.txt")
            File.write(path, body.to_s)
            path
          end

          def write_json(name:, data:)
            dir = DEFAULT_DIR
            FileUtils.mkdir_p(dir)
            path = dir.join("#{name}.json")
            File.write(path, JSON.pretty_generate(data))
            path
          end
        end
      end
    end
  end
end
