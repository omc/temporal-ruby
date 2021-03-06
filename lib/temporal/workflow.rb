require 'temporal/concerns/executable'
require 'temporal/workflow/convenience_methods'
require 'temporal/thread_local_context'

module Temporal
  class Workflow
    extend Concerns::Executable
    extend ConvenienceMethods

    def self.execute_in_context(context, input)
      Temporal::ThreadLocalContext.set(context)

      workflow = new(context)
      result = workflow.execute(*input)

      context.complete(result)
    rescue StandardError, ScriptError => error
      Temporal.logger.error("Workflow execution failed with: #{error.inspect}")
      Temporal.logger.debug(error.backtrace.join("\n"))

      context.fail(error.class.name, error.message)
    end

    def initialize(context)
      @context = context
    end

    def execute
      raise NotImplementedError, '#execute method must be implemented by a subclass'
    end

    private

    def workflow
      @context
    end

    def logger
      workflow.logger
    end
  end
end
