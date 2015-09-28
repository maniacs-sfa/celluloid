require "thread"

module Celluloid
  class Group
    class Spawner < Group
      attr_accessor :finalizer

      def initialize
        super
      end

      def get(&block)
        assert_active
        fail ArgumentError.new("No block sent to Spawner.get()") unless block_given?
        instantiate block
      end

      def shutdown
        @running = false
        queue = []
        @mutex.synchronize do
          loop do
            break if @group.empty?
            th = @group.shift
            th.kill
            queue << th
          end
        end
        loop do
          break if queue.empty?
          queue.pop.join
        end
      end

      def idle?
        to_a.select { |t| t[:celluloid_meta] && t[:celluloid_meta][:state] == :running }.empty?
      end

      def busy?
        to_a.select { |t| t[:celluloid_meta] && t[:celluloid_meta][:state] == :running }.any?
      end

      private

      def instantiate(proc)
        thread = Thread.new do
          Thread.current[:celluloid_meta] = {
            started: Time.now,
            state: :running,
          }

          begin
            proc.call
          rescue ::Exception => ex
            Internals::Logger.crash("thread crashed", ex)
            Thread.current[:celluloid_meta][:state] = :error
          ensure
            unless Thread.current[:celluloid_meta][:state] == :error
              Thread.current[:celluloid_meta][:state] = :finished
            end
            @mutex.synchronize { @group.delete Thread.current }
          end
        end

        @mutex.synchronize { @group << thread }
        thread
      end
    end
  end
end
