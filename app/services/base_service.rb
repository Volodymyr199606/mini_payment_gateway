# frozen_string_literal: true

class BaseService
  attr_reader :result, :errors

  def self.call(*, **)
    new(*, **).call
  end

  def initialize(*_args, **_kwargs)
    @errors = []
    @result = nil
  end

  def call
    raise NotImplementedError, 'Subclasses must implement #call'
  end

  def success?
    @errors.empty?
  end

  def failure?
    !success?
  end

  protected

  def add_error(message)
    @errors << message
  end

  def set_result(value)
    @result = value
  end
end
