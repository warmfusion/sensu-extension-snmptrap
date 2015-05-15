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
#   "checks": {
#     "snmp": {
#       "extension": "snmp",
#       "subscribers": [],
#       "interval": 50,
#       "handler": "default"
#       "traps": [
# THIS BIT IN JSON
#  - trap_oid: 1.3.6.1.4.1.6876.4.3.0.203
#    trap:
#      old_state_oid: 1.3.6.1.4.1.6876.4.3.304.0
#      new_state_oid: 1.3.6.1.4.1.6876.4.3.305.0
#      message_oid: 1.3.6.1.4.1.6876.4.3.306.0
#      state_oid: 1.3.6.1.4.1.6876.4.3.308.0
#    event:  # This overrides the event with soem specific extra stuff if you want it
#      name: "VMWARE-EVENT::alarm.LicenseNonComplianceAlarm-{hostname}"
#      status: "1"
#      output: "{message_oid}"
#      handler: "default"
#      team: "wpi"
#     }
#   }
# }
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
include SNMP

module Sensu
  module Extension
    class SNMPHandler < Check
      def name
        'snmp'
      end

      # Get the list of traps supported for this handler
      def traps
        Array(options['traps'])
      end

      def description
        'SNMP Extension that can check or (passivly) trap SNMP events'
      end

      def options
        return @options if @options
        @options = {
          bind: '0.0.0.0',
          port: 1062,
          community: 'public',
          handler: 'default',
          send_interval: 60
        }
        @options.merge!(@settings[:snmp]) if @settings[:snmp].is_a?(Hash)
        @options
      end

      def definition
        {
          type: 'extension',
          name: name,
          interval: options[:send_interval],
          standalone: true,
          handler: options[:handler]
        }
      end

      def post_init
        # Setup SNMPTraps
        start_trap
      end

      def run(data=nil, options={}, &callback)
        @logger.info('SNMP Trap: Run called')
        output = 'No Test here yet...'
        callback.call(output, 0)
      end

      def start_trap()
        @logger.info('Starting SNMP Trap listener.')
        m = SNMP::TrapListener.new(:Port => 1062) do |manager|

#Don't try and do anything clever with MIBs just yet
          # SNMP::MIB.import_modules(@mibs)
#          manager.load_modules(Array(@mibs), SNMP::MIB::DEFAULT_MIB_PATH)
#          @mib = manager.mib

          manager.on_trap_v1 do |trap|
            @logger.info format_v1_trap(trap)
          end

          manager.on_trap_v2c do |trap|
            @logger.info('v2-Trap caught')

            processed = false
            traps.each do |trapdef|
#              if !trapdef['trap_oid'].nil?
                trapdef_oid = SNMP::ObjectId.new(trapdef['trap_oid'])
#              else
#                trapdef_oid = SNMP::ObjectId.new(@mib.oid(trapdef['trap_name']))
#              end
              @logger.debug 'trapdef ' + trapdef_oid.inspect
              @logger.debug 'trap ' + trap.trap_oid.inspect
              # only accept configured traps
              if trap.trap_oid == trapdef_oid
                @logger.info 'processing trap: ' + trap.trap_oid.to_s
                process_v2c_trap trap, trapdef
                processed = true
                break
              end
            end

            @logger.info 'ignoring unconfigured trap: ' + trap.trap_oid.to_s unless processed

          end
          @logger.info "Logging started"
        end
      end


      private

      # Doesn't appear to be possible to ping Sensu directly for async event triggering
      # even though we're inside Sensu right now...
      def publish_check_result (check)
        # a little risky: we're assuming Sensu-Client is listening on Localhost:3030
        # for submitted results : https://sensuapp.org/docs/latest/clients#client-socket-input
          @log.info "Sending check result: #{check.to_json}"
          t = TCPSocket.new '127.0.0.1', 3030
          t.write(check.to_json + "\n")
      end

      def process_v2c_trap(trap, trapdef)
        fields = Hash.new

        fields['hostname'] = trap.source_ip
        fields['source'] = ( Resolv.getname(trap.source_ip) rescue trap.source_ip)
        trapdef['trap'].each do |key,value|
          if key.include?('_oid')
            value = SNMP::ObjectId.new(value)
          else
            value = SNMP::ObjectId.new(@mib.oid(value))
          end
          @logger.debug key.inspect + ', ' + value.inspect
          @logger.debug trap.varbind_list.inspect
          fields[key] = trap.varbind_list.find{|vb| vb.name == value}.value
        end

        @logger.debug fields
        fields.each do |key,value|
          trapdef['event'].each{|k,v| trapdef['event'][k] = v.gsub("{#{key}}", value )}
        end

        @logger.debug trapdef['event']

        publish_check_result trapdef['event'].to_json

      end



    end
  end
end