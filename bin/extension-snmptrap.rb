#! /usr/bin/env ruby
#
#   extension-snmptrap.rb
#
# DESCRIPTION:
#   Handles incoming SNMP Traps and emits sensu events
#   Creates an SNMP trap listening to all incoming traps on any interface and
#   triggers events into sensu as JIT clients specifying the source of the event.
#
#
#       {
#        "snmp": { }
#       }
#
#   Default options are;
#      {
#        "snmp": {
#          bind: '0.0.0.0',
#          port: 1062,
#          community: 'public',
#          handler: 'default',
#          send_interval: 60,
#          trapdefs_dir: '/etc/sensu/traps.d',
#          mibs_dir: '/etc/sensu/mibs',
#          client_socket_bind: settings[:client][:socket][:bind],
#          client_socket_port: settings[:client][:socket][:port]
#        }
#      }
#
# OUTPUT:
#   N/A - Extension submits multiple events of different types based on snmp configuration
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: snmp
#
# USAGE:
#  Traps are configured in /etc/sensu/traps.d directory, one json file containing one or more trap configurations
#  as described in the README.md that accompanies this script.
#
# NOTES:
#   No special notes. This should be fairly straight forward.
#
# LICENSE:
#   Toby Jackson <toby@warmfusion.co.uk>
#   Peter Daugavietis <pdaugavietis@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#
#
# ##############################
# Handy Test script:
# snmptrap -v 2c -c public localhost:1062 "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification  netSnmpExampleHeartbeatRate i 123456
#
# Useful SNMP browser to help find things:
# http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.2.1.1.5
#
# http://www.net-snmp.org/docs/mibs/ucdavis.html#laTable
# Load Average Last Minute -  .1.3.6.1.4.1.2021.10.1.3.1
#
require 'net/http'
require 'snmp'
require 'json'
include SNMP

module Sensu
  module Extension
    class SNMPTrapHandler < Check
      def name
        'SnmpTrapHandler'
      end

      def description
        'SNMP Extension that handles/traps SNMP events'
      end

      def options
        return @options if @options
        @options = {
          bind: '0.0.0.0',
          port: 1062,
          community: 'public',
          handler: 'default',
          send_interval: 60,
          trapdefs_dir: '/etc/sensu/traps.d',
          mibs_dir: '/etc/sensu/mibs',
          client_socket_bind: settings[:client][:socket][:bind],
          client_socket_port: settings[:client][:socket][:port]
        }
        @options.merge!(@settings[:snmp]) if @settings[:snmp].is_a?(Hash)
        @options
      end

      def definition
        {
          type: 'extension',
          name: name,
          publish: false # Don't run this extension as a check
        }
      end

      def validate

        if options[:client_socket_bind].nil?
          @logger.warn 'couldnt find client socket binding - is it defined? https://sensuapp.org/docs/latest/reference/clients.html#socket-attributes'
          false
        end
        true
      end

      def post_init
        if !validate
          @logger.error "failed to validate the #{name} extension"
        else
          # Setup SNMPTrap
          @logger.debug "loading SNMPTrap definitions from #{options[:trapdefs_dir]}"
          @trapdefs = []
          Dir.glob(options[:trapdefs_dir] + '/*.json') do |file|
            @logger.debug "Reading #{file}..."
            @trapdefs.concat Array(::JSON.parse(File.read(file)))
          end

          @logger.debug 'loaded trapdefs...'
          @logger.debug @trapdefs.to_json

          @mibs = []
          Dir.glob(options[:mibs_dir] + '/*.yaml') do |file|
            # do something with the file here
            @logger.debug "reading MIB configuration from #{File.basename(file, '.yaml')}"
            @mibs << File.basename(file, '.yaml')
          end
          @logger.debug @mibs.to_json

          start_trap_listener
        end
      end

      def run(_data = nil, _options = {}, &callback)
        @logger.warn('SNMP trap: run called as a check - this is not supported')
        output = 'SNMPHandler extension should not be called as a standalone check'
        callback.call(output, 3)
      end

      def start_trap_listener
        @logger.info('starting SNMPTrap listener...')

        SNMP::TrapListener.new(Host: options[:bind], Port: options[:port]) do |manager|
          # Need patched Gem to allow the following functions/lookups
          # Need to copy the MIBs from somewhere to the Gem location needed (or fix the importing mechanism too)

          # If the following MIB code is used, SNMPTrap hangs up and stops working... dont know why - possibly
          # an implicit .join() somewhere locking things up ?
          # SNMP::MIB.import_modules(@mibs)
          # manager.load_modules(@mibs, DEFAULT_MIB_PATH)
          # @mib = manager.mib

          manager.on_trap_v2c do |trap|
            @logger.debug('v2-Trap caught')

            processed = false
            @trapdefs.each do |trapdef|
              if !trapdef['trap_oid'].nil?
                trapdef_oid = SNMP::ObjectId.new(trapdef['trap_oid'])
              else
                trapdef_oid = SNMP::ObjectId.new(@mib.oid(trapdef[:trap_name]))
              end
              @logger.debug 'trapdef ' + trapdef_oid.inspect
              @logger.debug 'trap ' + trap.trap_oid.inspect
              # only accept configured traps
              if trap.trap_oid == trapdef_oid
                @logger.info "SNMPTrap is processing a defined snmp v2 trap oid:#{trap.trap_oid}"
                process_v2c_trap trap, trapdef
                processed = true
                break
              end
              @logger.debug "ignoring unrecognised trap: #{trap.trap_oid}" unless processed
            end
          end

          @logger.info("SNMPTrap listener has started on #{options[:bind]}:#{options[:port]}")
        end
      end

      private

      # Doesn't appear to be possible to ping Sensu directly for async event triggering
      # even though we're inside Sensu right now...
      def publish_check_result(check)
        # a little risky: we're assuming Sensu-Client is listening on Localhost:3030
        # for submitted results : https://sensuapp.org/docs/latest/clients#client-socket-input
        @logger.debug "sending SNMP check event: #{check.to_json}"

        host = options[:client_socket_bind]
        port = options[:client_socket_port]

        begin
          @logger.debug "opening connection to #{host}:#{port}"
          t = TCPSocket.new host, port
          t.write(check.to_json + "\n")
        rescue StandardError => e
          @logger.error(e)
        end
      end

      def process_v2c_trap(trap, trapdef)
        hostname = trap.source_ip
        begin
          hostname = Resolv.getname(trap.source_ip)
        rescue Resolv::ResolvError
          @logger.debug("unable to resolve name for #{trap.source_ip}")
        end

        fields = {}
        fields[:source] = trap.source_ip
        fields[:hostname] = hostname

        @logger.debug('checking trap definition for key/value template pairs')
        Array(trapdef['trap']).each do |key, value|
          begin
            value = SNMP::ObjectId.new(value)
          rescue
            value = SNMP::ObjectId.new(@mib.oid(value))
          end

          @logger.debug key.inspect + ', ' + value.inspect
          @logger.debug trap.varbind_list.inspect
          val = trap.varbind_list.find { |vb| vb.name == value }
          if val.nil?
            @logger.warn("trap.#{key} has OID(#{value}) that was not found in incoming trap - check your configuration")
          end
          @logger.debug("discovered value of #{key} is '#{val}'")
          fields[key] = val.value unless val.nil?
        end

        @logger.debug("template fields are: #{fields.inspect}")

        # Replace any {template} values in the event with the value of
        # snmp values defined in the traps configuration
        fields.each do |key, value|
          trapdef['event'].each do |k, v|
            @logger.debug("looking for #{key} in #{trapdef['event'][k]}")
            begin
              trapdef['event'][k] = v.gsub("{#{key}}", value.to_s.gsub('/', '-'))
            rescue
              trapdef['event'][k] = v
            end
          end
        end
        @logger.debug trapdef['event']
        publish_check_result trapdef['event']
      end
    end
  end
end
