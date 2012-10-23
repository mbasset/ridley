module Ridley
  # @author Jamie Winsor <jamie@vialstudios.com>
  class Bootstrapper
    autoload :Context, 'ridley/bootstrapper/context'

    class << self
      def templates_path
        Ridley.root.join('bootstrappers')
      end

      # @return [String]
      def default_template
        templates_path.join('omnibus.erb').to_s
      end
    end

    include Celluloid
    include Celluloid::Logger

    attr_reader :hosts
    attr_reader :contexts

    # @param [Ridley::Connection] connection
    # @param [Array<String>, Array<Ridley::Node>] nodes
    # @param [Hash] options
    def initialize(connection, hosts, options = {})
      @connection = connection
      @hosts      = hosts

      @contexts = hosts.collect do |host|
        Context.new(host, connection, options)
      end
    end

    # @param [String] command
    #
    # @return [Array]
    def run
      workers = Array.new
      workers = contexts.collect do |context|
        worker = SSH::Worker.new_link(current_actor, context.node_name, connection.ssh)
        worker.async.run(context.boot_command)
        worker
      end

      [].tap do |responses|
        until responses.length == workers.length
          receive { |msg|
            status, response = msg
            
            case status
            when :ok, :error
              responses << msg
            else
              error "No match for status: '#{status}'. terminating..."
              terminate
            end
          }
        end
      end
    ensure
      workers.collect(&:terminate)
    end

    private

      attr_reader :connection
  end
end
