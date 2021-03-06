require 'temporal/activity/poller'
require 'temporal/middleware/entry'

describe Temporal::Activity::Poller do
  let(:client) { instance_double('Temporal::Client::ThriftClient') }
  let(:namespace) { 'test-namespace' }
  let(:task_queue) { 'test-task-queue' }
  let(:lookup) { instance_double('Temporal::ExecutableLookup') }
  let(:thread_pool) { instance_double(Temporal::ThreadPool, wait_for_available_threads: nil) }
  let(:middleware_chain) { instance_double(Temporal::Middleware::Chain) }
  let(:middleware) { [] }

  subject { described_class.new(namespace, task_queue, lookup, middleware) }

  before do
    allow(Temporal::Client).to receive(:generate).and_return(client)
    allow(Temporal::ThreadPool).to receive(:new).and_return(thread_pool)
    allow(Temporal::Middleware::Chain).to receive(:new).and_return(middleware_chain)
  end

  describe '#start' do
    it 'polls for activity tasks' do
      allow(subject).to receive(:shutting_down?).and_return(false, false, true)
      allow(client).to receive(:poll_for_activity_task).and_return(nil)

      subject.start

      # stop poller before inspecting
      subject.stop; subject.wait

      expect(client)
        .to have_received(:poll_for_activity_task)
        .with(namespace: namespace, task_queue: task_queue)
        .twice
    end

    context 'when an activity task is received' do
      let(:task_processor) { instance_double(Temporal::Activity::TaskProcessor, process: nil) }
      let(:task) { Fabricate(:activity_task_thrift) }

      before do
        allow(subject).to receive(:shutting_down?).and_return(false, true)
        allow(client).to receive(:poll_for_activity_task).and_return(task)
        allow(Temporal::Activity::TaskProcessor).to receive(:new).and_return(task_processor)
        allow(thread_pool).to receive(:schedule).and_yield
      end

      it 'schedules task processing using a ThreadPool' do
        subject.start

        # stop poller before inspecting
        subject.stop; subject.wait

        expect(thread_pool).to have_received(:schedule)
      end

      it 'uses TaskProcessor to process tasks' do
        subject.start

        # stop poller before inspecting
        subject.stop; subject.wait

        expect(Temporal::Activity::TaskProcessor)
          .to have_received(:new)
          .with(task, namespace, lookup, client, middleware_chain)
        expect(task_processor).to have_received(:process)
      end

      context 'with middleware configured' do
        class TestPollerMiddleware
          def initialize(_); end
          def call(_); end
        end

        let(:middleware) { [entry_1, entry_2] }
        let(:entry_1) { Temporal::Middleware::Entry.new(TestPollerMiddleware, '1') }
        let(:entry_2) { Temporal::Middleware::Entry.new(TestPollerMiddleware, '2') }

        it 'initializes middleware chain and passes it down to TaskProcessor' do
          subject.start

          # stop poller before inspecting
          subject.stop; subject.wait

          expect(Temporal::Middleware::Chain).to have_received(:new).with(middleware)
          expect(Temporal::Activity::TaskProcessor)
            .to have_received(:new)
            .with(task, namespace, lookup, client, middleware_chain)
        end
      end
    end

    context 'when client is unable to poll' do
      before do
        allow(subject).to receive(:shutting_down?).and_return(false, true)
        allow(client).to receive(:poll_for_activity_task).and_raise(StandardError)
      end

      it 'logs' do
        allow(Temporal.logger).to receive(:error)

        subject.start

        # stop poller before inspecting
        subject.stop; subject.wait

        expect(Temporal.logger)
          .to have_received(:error)
          .with('Unable to poll for an activity task: #<StandardError: StandardError>')
      end
    end
  end
end
