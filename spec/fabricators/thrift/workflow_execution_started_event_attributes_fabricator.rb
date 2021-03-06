require 'gen/thrift/temporal_types'
require 'securerandom'

Fabricator(
  :worklfow_execution_started_event_attributes_thrift,
  from: TemporalThrift::WorkflowExecutionStartedEventAttributes
) do
  transient :headers

  workflowType { Fabricate(:workflow_type_thrift) }
  originalExecutionRunId { SecureRandom.uuid }
  attempt 1
  header { |attrs| Fabricate(:header_thrift, fields: attrs[:headers]) if attrs[:headers] }
end
