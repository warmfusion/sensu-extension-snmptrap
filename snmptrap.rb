# SNMP
# ===
#
# Creates an SNMP trap listening to all incoming traps on any interface
# and triggers events into sensu as JIT clients specifying the source
# of the event.
#
# Also able to run as a 'polling' service in either Check or Metrics mode
# where values can be directly compared against expectations (eg value > 10)
# or where values are sent to Sensu as metrics values for charting or
# other purposes.
#
# {
#  "snmp": { }
# }
#
# ## Trap Configuration
#
#  Traps are configured in /etc/sensu/traps.d directory, one json file containing one or more trap configurations
#  as described in the README.md that accompanies this script.
#
#
# ##############################
# Handy Test script:
# snmptrap -v 2c -c public localhost:1062 "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification  netSnmpExampleHeartbeatRate i 123456
#
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# Useful SNMP browser to help find things:
# http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.2.1.1.5
#
# http://www.net-snmp.org/docs/mibs/ucdavis.html#laTable
# Load Average Last Minute -  .1.3.6.1.4.1.2021.10.1.3.1
require 'net/http'
require 'snmp'
require 'json'
include SNMP

module Sensu
  module Extension
    class SNMPTrapHandler < Check

      # assume the /etc/sensu/extensions folder as location for relative
      data_path = File.expand_path(File.dirname(__FILE__) + "/../mibs")
      DEFAULT_MIB_PATH = if (File.exist?(data_path))
        data_path
      else
        @logger.info "Could not find default MIB directory, tried:\n  #{data_path}"
        nil
      end

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
          mibs_dir: '/etc/sensu/mibs'
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

      def post_init
        # Setup SNMPTrap
        @logger.debug "Loading SNMPTrap definitions from #{options[:trapdefs_dir]}"
        @trapdefs = []
        Dir.glob (options[:trapdefs_dir] + "/*.json") { |file|
          # do something with the file here
          @logger.info file
          @trapdefs.concat Array(JSON.parse(File.read(file)))
        }
        @logger.debug @trapdefs.to_json

        @mibs = []
        Dir.glob(options[:mibs_dir] + "/*.yaml") {|file|
          # do something with the file here
          @logger.debug "Reading MIB configuration from #{File.basename(file, '.yaml')}"
          @mibs << File.basename(file, '.yaml')
        }
        @logger.debug @mibs.to_json

        start_trap_listener
      end

      def run(data=nil, options={}, &callback)
        @logger.warn('SNMP Trap: Run called as a check - this is not supported')
        output = 'SNMPHandler extension should not be called as a standalone check'
        callback.call(output, 3)
      end

      def start_trap_listener

        @logger.info("Starting SNMP Trap listener...")

        m = SNMP::TrapListener.new(:Host => options[:bind], :Port => options[:port]) do |manager|

          # Need patched Gem to allow the following functions/lookups
          # Need to copy the MIBs from somewhere to the Gem location needed (or fix the importing mechanism too)

          # If the following MIB code is used, SNMPTrap hangs up and stops working... dont know why - possibly
          # an implicit .join() somewhere locking things up ?
          # SNMP::MIB.import_modules(@mibs)
          # manager.load_modules(@mibs, DEFAULT_MIB_PATH)
          # @mib = manager.mib

          manager.on_trap_v1 do |trap|
            @logger.info('v1-Trap caught')
            @logger.info trap.to_json
          end

          manager.on_trap_v2c do |trap|
            @logger.info('v2-Trap caught')
            @logger.info( trap.to_json )

            processed = false
            @trapdefs.each do |trapdef|
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
                  @logger.info "Processing known v2 trap #{trap.trap_oid.to_s}"
                  process_v2c_trap trap, trapdef
                  processed = true
                  break
                end
              end
              @logger.debug "Ignoring unrecognised trap: #{trap.trap_oid.to_s}" +  unless processed
            end
          end
        end

        @logger.info("SNMP Trap listener has started on #{options[:bind]}:#{options[:port]}")

      end

      private

      # Doesn't appear to be possible to ping Sensu directly for async event triggering
      # even though we're inside Sensu right now...
      def publish_check_result (check)
        # a little risky: we're assuming Sensu-Client is listening on Localhost:3030
        # for submitted results : https://sensuapp.org/docs/latest/clients#client-socket-input
          @logger.info "Sending SNMP check event: #{check.to_json}"

          host = settings[:client][:bind] ||= '127.0.0.1'
          port = settings[:client][:port] ||= '3030'
          t = TCPSocket.new host, port
          t.write(check.to_json + "\n")
      end

      def process_v2c_trap(trap, trapdef)

        fields = Hash.new
        fields[:source] = trap.source_ip
        fields[:hostname] = ( Resolv.getname(trap.source_ip) rescue trap.source_ip)
       
        @logger.debug('Checking trap definition for key/value template pairs')
        Array(trapdef['trap']).each do |key,value|
          value = SNMP::ObjectId.new(value) rescue SNMP::ObjectId.new(@mib.oid(value))
          @logger.debug key.inspect + ', ' + value.inspect
          @logger.debug trap.varbind_list.inspect
          val = trap.varbind_list.find{|vb| vb.name == value}
          if (val.nil?){
            @logger.warn("trap.#{key} has OID(#{value}) that was not found in incoming trap - Check your configuration")
          }
          @logger.debug("Discovered value of #{key} is '#{val}'")
          fields[key] = val.value unless val.nil?
        end

        @logger.debug("Template fields are: #{fields.inspect}")

        # Replace any {template} values in the event with the value of
        # snmp values defined in the traps configuration
        fields.each do |key,value|
          trapdef['event'].each{|k,v|
            @logger.debug("Looking for #{key} in #{trapdef['event'][k]}")
            trapdef['event'][k] = v.gsub("{#{key}}", value.to_s.gsub('/','-') ) rescue v
          }
        end

        @logger.debug trapdef['event']
        publish_check_result trapdef['event']

      end

    end
  end
end