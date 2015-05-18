# Sensu SNMP Trap Extension

Creates an SNMP trap listening to all incoming traps on the configured interface and triggers events into sensu as JIT events when specifying the source of the event.

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

### Example

     {
      "snmp": {
        "traps": [
          {
            "trap_oid": "1.3.6.1.4.1.8072.2.3.0.1",
            "trap": {   This describes template variables (key) and the OID/MIB's to use for their values
              "heartbeatrate": "1.3.6.1.4.1.8072.2.3.2.1.0"   Will make heartbeatrate = valueOf(1.3.6...)
            },
            "event": {
              "name": "snmp-trap-{hostname}", # {hostname} and {source} (the ip) are automatically provided template variables
              "status": 1,
               "output": "Heartbeat Rate {heartbeatrate}",  {heartbeatrate} is a template variable described by [:trap][:heartbeatrate] above
               "handler": "default"
               }
             }
           }
         ]
       }
     }


## Appendix 

Handy Test script:

    snmptrap -v 2c -c public localhost:1062 "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification  netSnmpExampleHeartbeatRate i 123456


Released under the same terms as Sensu (the MIT license). 
