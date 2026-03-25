# frozen_string_literal: true

require 'fileutils'

namespace :ai do
  namespace :skills do
    desc 'Generate evidence-based skill value report (audits + eval coverage). Example: bundle exec rake ai:skills:value_report'
    task value_report: :environment do
      report = Ai::Skills::ValueAnalysis::ReportBuilder.build
      out_dir = Rails.root.join('tmp/ai_skills')
      FileUtils.mkdir_p(out_dir)
      path = out_dir.join("value_report_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.md")
      File.write(path, report[:markdown])
      puts report[:markdown]
      puts ''
      puts "Wrote: #{path}"
    end
  end
end
