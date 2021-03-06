require 'temporal/workflow/executor'
require 'temporal/workflow/history'
require 'temporal/workflow/serializer'
require 'temporal/metadata'

module Temporal
  class Workflow
    class DecisionTaskProcessor
      def initialize(task, namespace, workflow_lookup, client, middleware_chain)
        @task = task
        @namespace = namespace
        @task_token = task.task_token
        @workflow_name = task.workflow_type.name
        @workflow_class = workflow_lookup.find(workflow_name)
        @client = client
        @middleware_chain = middleware_chain
      end

      def process
        start_time = Time.now

        Temporal.logger.info("Processing a workflow task for #{workflow_name}")
        Temporal.metrics.timing('decision_task.queue_time', queue_time_ms, workflow: workflow_name)

        unless workflow_class
          fail_task('Workflow does not exist')
          return
        end

        history = Workflow::History.new(task.history.events)
        # TODO: For sticky workflows we need to cache the Executor instance
        executor = Workflow::Executor.new(workflow_class, history)
        metadata = Metadata.generate(Metadata::DECISION_TYPE, task, namespace)

        commands = middleware_chain.invoke(metadata) do
          executor.run
        end

        complete_task(commands)
      rescue StandardError => error
        Temporal.logger.error("Workflow task for #{workflow_name} failed with: #{error.inspect}")
        Temporal.logger.debug(error.backtrace.join("\n"))
      ensure
        time_diff_ms = ((Time.now - start_time) * 1000).round
        Temporal.metrics.timing('decision_task.latency', time_diff_ms, workflow: workflow_name)
        Temporal.logger.debug("Workflow task processed in #{time_diff_ms}ms")
      end

      private

      attr_reader :task, :namespace, :task_token, :workflow_name, :workflow_class, :client, :middleware_chain

      def queue_time_ms
        scheduled = task.scheduled_time.to_f
        started = task.started_time.to_f
        ((started - scheduled) * 1_000).round
      end

      def serialize_commands(commands)
        commands.map { |(_, command)| Workflow::Serializer.serialize(command) }
      end

      def complete_task(commands)
        Temporal.logger.info("Workflow task for #{workflow_name} completed")

        client.respond_workflow_task_completed(
          task_token: task_token,
          commands: serialize_commands(commands)
        )
      end

      def fail_task(message)
        Temporal.logger.error("Workflow task for #{workflow_name} failed with: #{message}")

        client.respond_workflow_task_failed(
          task_token: task_token,
          cause: Temporal::Api::Enums::V1::WorkflowTaskFailedCause::WORKFLOW_TASK_FAILED_CAUSE_UNHANDLED_COMMAND,
          details: { message: message }
        )
      end
    end
  end
end
