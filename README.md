# Sensu SNMP Trap Extension

Creates an SNMP trap listening to all incoming traps on the configured interface and triggers events into sensu as JIT events when specifying the source of the event.

[![Build Status](https://travis-ci.org/warmfusion/sensu-extension-snmptrap.svg)](https://travis-ci.org/warmfusion/sensu-extension-snmptrap)

## TODO

Also able to run as a 'polling' service in either Check or Metrics mode where values can be directly compared against expectations (eg value > 10)
or where values are sent to Sensu as metrics values for charting or other purposes.


## Configuration

The SNMPTrap configuration is defined in a json file inside conf.d/extensions (or anywhere sensu consumes configuration)
and includes a traps configuration element that describes:

* An array of traps that the extension will monitor for events (from any host) which includes
    * `trap_oid` - the identity of the trap
    * `trap` - A hash of key/value pairs that can be used as template values in the event
    * `event` - The template event to send to Sensu, including {template} variables for customisation based on the message


### Templating

Any value defined in `trap` that contains an OID that is included in the incoming trap can be used as part of any element of the
event being sent to Sensu. This includes handlers, names (Only AlphaNumeric allow), status etc etc.

Simply wrap your template in braces and it will be automatically replaced during processing. See the heartbeatrate in the example
below.

> Note: The 'source' and 'hostname' variables are automatically provided to you. Hostname contains the FQDN name of the server (or the IP if it 
> can't get resolved) and 'source' contains the IP address (with no lookups)

### Basic Extension Configuration


     {
      "snmp": {
 
       }
     }

### Trap Configuration

Each SNMP Trap is configured in its own configuration file. This lets you easily create configuration through Puppet/Chef etc without
having to manipulate the same configuration file.

Simply create a uniquely named json file in `/etc/sensu/traps.d` containing the definition of the trap(s) you wish to capture and
act upon.


    [
      {
        "trap_oid": "1.3.6.1.4.1.8072.2.3.0.1",
        "trap": {
          "heartbeatrate": "1.3.6.1.4.1.8072.2.3.2.1" 
        },
        "event": {
          "name": "snmp-trap-{hostname}",
          "status": 1,
          "output": "Heartbeat Rate {heartbeatrate}", 
          "handler": "default"
         }
       },
       ...
     ]

The JSON file is an array of trap definitions containing:

* trap_oid
  * Definition: (String) The OID to monitor for events on
* trap
  * Definition: (Array) Key/Value pairs representing named variables (key) against the OID values of the message elements (value)
    which can then be used as template values in the event section
* event
  * Definition: (Hash) The event to trigger if the SNMP trap is recieved - Accepts any value that will then get sent to sensu
    as a normal check event - this includes handlers, subdues, or custom key/value pairs as you require.
  * name
    * Definition: (String) The name of the sensu check that is sent to the sensu-client - ALPHANUMERIC and should be fairly unique (Required)
  * status
    * Definition: (Numeric) The numeric status of the status (0-OK, 1-Warning, 2-Critical, 3-Unknown) (Required)
  * output
    * Definition: (String) The message to send to the sensu client (Required)
  * handler
    * Definition: (String) The handler that the sensu-server should use to process this event (Optional)


## Appendix 

Handy Test script:

    snmptrap -v 2c -c public localhost:1062 "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification  netSnmpExampleHeartbeatRate i 123456


Released under the same terms as Sensu (the MIT license). 
