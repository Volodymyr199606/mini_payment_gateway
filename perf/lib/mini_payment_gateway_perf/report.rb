# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module MiniPaymentGatewayPerf
  class Report
    attr_reader :scenarios, :meta

    def initialize(meta = {})
      @meta = meta
      @scenarios = []
    end

    def add_scenario(row)
      @scenarios << row.stringify_keys
    end

    def write!(root: Rails.root.join('tmp', 'perf'))
      FileUtils.mkdir_p(root)
      ts = Time.now.utc.strftime('%Y%m%d_%H%M%S')
      base = root.join("run_#{ts}")
      FileUtils.mkdir_p(base)
      json_path = base.join('results.json')
      md_path = base.join('summary.md')

      payload = {
        recorded_at: Time.now.utc.iso8601,
        meta: @meta,
        scenarios: @scenarios
      }
      File.write(json_path, JSON.pretty_generate(payload))

      File.write(md_path, render_markdown(payload))
      { json: json_path, markdown: md_path, directory: base }
    end

    def render_markdown(payload)
      lines = []
      lines << '# Performance run summary'
      lines << ''
      lines << "- **Recorded:** #{payload[:recorded_at]}"
      lines << "- **Rails env:** #{payload.dig(:meta, 'rails_env')}"
      lines << "- **Iterations (default):** #{payload.dig(:meta, 'iterations')}"
      lines << "- **Concurrency:** #{payload.dig(:meta, 'concurrency')}"
      lines << ''
      lines << '| Scenario | runs | errors | median_ms | p95_ms | throughput_rps | cache_state | notes |'
      lines << '|----------|-----:|-------:|----------:|-------:|---------------:|-------------|-------|'
      payload[:scenarios].each do |s|
        lines << [
          s['scenario'],
          s['runs'],
          s['errors'],
          s['median_ms'],
          s['p95_ms'],
          s['throughput_rps'],
          s['cache_state'].to_s.tr('|', '/'),
          s['notes'].to_s.tr('|', '/')[0, 60]
        ].join(' | ')
      end
      lines << ''
      lines.join("\n")
    end
  end
end
