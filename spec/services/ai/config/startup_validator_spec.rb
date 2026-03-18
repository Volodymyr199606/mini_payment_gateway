# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Config::StartupValidator do
  def with_env(key, value)
    orig = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = orig
  end

  describe '#call' do
    context 'in development' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'does not raise when config is valid' do
        with_env('AI_DEBUG', '') do
          expect { described_class.call }.not_to raise_error
        end
      end
    end

    context 'in test' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:test?).and_return(true)
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'does not raise when AI_DEBUG is off' do
        with_env('AI_DEBUG', '') do
          result = described_class.call
          expect(result.valid?).to be true
        end
      end
    end

    context 'in production' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'does not raise when AI_DEBUG is off' do
        with_env('AI_DEBUG', '') do
          result = described_class.call
          expect(result.valid?).to be true
        end
      end

      it 'does not raise when AI_DEBUG is on but AI_DEBUG_ALLOWED_IN_PRODUCTION=true' do
        with_env('AI_DEBUG', 'true') do
          with_env('AI_DEBUG_ALLOWED_IN_PRODUCTION', 'true') do
            result = described_class.call
            expect(result.valid?).to be true
            expect(result.warnings).to include(match(/AI_DEBUG is enabled in production/))
          end
        end
      end

      it 'adds error when AI_DEBUG on and AI_DEBUG_ALLOWED_IN_PRODUCTION not set' do
        with_env('AI_DEBUG', 'true') do
          with_env('AI_DEBUG_ALLOWED_IN_PRODUCTION', '') do
            result = described_class.call
            expect(result.valid?).to be false
            expect(result.errors).to include(match(/AI_DEBUG must not be enabled/))
          end
        end
      end

      it 'raises when AI_CONFIG_STRICT=true and validation has errors' do
        with_env('AI_DEBUG', 'true') do
          with_env('AI_DEBUG_ALLOWED_IN_PRODUCTION', '') do
            with_env('AI_CONFIG_STRICT', 'true') do
              expect { described_class.call }.to raise_error(described_class::ValidationError, /AI_DEBUG must not be enabled/)
            end
          end
        end
      end
    end
  end
end
