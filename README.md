# Sensu SNMP Trap Extension

Creates an SNMP trap listening to all incoming traps on the configured interface and triggers events into sensu as JIT events when specifying the source of the event.

[![Build Status](https://travis-ci.org/warmfusion/sensu-extension-snmptrap.svg)](https://travis-ci.org/warmfusion/sensu-extension-snmptrap)

[![Gem Version](https://badge.fury.io/rb/sensu-plugins-snmptrap-extension.svg)](https://badge.fury.io/rb/sensu-plugins-snmptrap-extension)


# Installation

As sensu extensions cannot be dynamically loaded by sensu at runtime, you must
install the extension manually once the gem has installed.

If you're using the EMBEDDED_RUBY from sensu;

```
sensu-install -p sensu-plugins-snmptrap-extension

ln -s /opt/sensu/embedded/lib/ruby/gems/*/gems/sensu-plugins-snmptrap-extension-*/bin/extension-snmptrap.rb /etc/sensu/extensions/extension-snmptrap.rb
```

If using standalone ruby;

```
gem install sensu-plugins-snmptrap-extension

ln -s $(gem environment gemdir)/gems/sensu-plugins-snmptrap-extension*/bin/extension-snmptrap.rb /etc/sensu/extensions/extension-snmptrap.rb
```

## Configuration

The SNMPTrap configuration is defined in a json file inside conf.d/extensions (or anywhere sensu consumes configuration)
and includes a traps configuration element that describes:

* An array of traps that the extension will monitor for events (from any host) which includes
    * `trap_oid` - the identity of the trap
    * `trap` - A hash of key/value pairs that can be used as template values in the event
    * `event` - The template event to send to Sensu, including {template} variables for customisation based on the message


### Trap Configuration

Each SNMP Trap is configured in its own configuration file. This lets you easily create configuration through Puppet/Chef etc without having to manipulate the same configuration file.

Simply create a uniquely named json file in `/etc/sensu/traps.d` containing the definition of the trap(s) you wish to capture and act upon.

```
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
          "handler": "default",
          "client": "{hostname}"
         }
       },
       ...
     ]
```

The JSON file is an array of trap definitions containing:

* trap_oid
  * Definition: (String) The OID to monitor for events on
* trap
  * Definition: (Array) Key/Value pairs representing named variables (key)
  against the OID values of the message elements (value) which can then be
  used as template values in the event section
* event
  * Definition: (Hash) The event to trigger if the SNMP trap is received - Accepts any
  value that will then get sent to sensu as a normal check event - this includes
  handlers, subdues, or custom key/value pairs as you require.
  * name
    * Definition: (String) The name of the sensu check that is sent to the
    sensu-client - ALPHANUMERIC and should be fairly unique (Required)
  * status
    * Definition: (Numeric) The numeric status of the status
    (0-OK, 1-Warning, 2-Critical, 3-Unknown) (Required)
  * output
    * Definition: (String) The message to send to the sensu client (Required)
  * handler
    * Definition: (String) The handler that the sensu-server should use to process this event (Optional)

#### Templating

Any value defined in `trap` that contains an OID that is included in the incoming trap can be used as part of any element of the
event being sent to Sensu. This includes handlers, names (Only AlphaNumeric allow), status etc etc.

Simply wrap your template in braces and it will be automatically replaced during processing. See the heartbeatrate in the example
below.

> Note: The 'source' and 'hostname' variables are automatically provided to you. Hostname contains the FQDN name of the server (or the IP if it
> can't get resolved) and 'source' contains the IP address (with no lookups)

### Override SNMP default configuration

The SNMPTrap extension provides some simple configuration options which are shown
below;

     {
      "snmp": {
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
     }

|param|type|default|description|
|----|----|----|---|
|:bind|:string|0.0.0.0| IP to bind the SNMPTrap listener to |
|:port|:integer|1062| Port to bind the SNMPTrap listener to |
|:community|:string|"public"| *NOT USED* |
|:handler|:string|"default"| *NOT USED* |
|:send_interval|:integer|60| *NOT USED* |
|:trapdefs_dir|:string|"/etc/sensu/traps.d"| Path to directory containing trap.json files to watch for |
|:mibs_dir|:string|"/etc/sensu/mibs"| *NOT USED* - Loading MIBs causes the extension to lock up |
|:client_socket_bind|:string| `settings[:client][:socket][:bind]` | IP to send events to when handled |
|:client_socket_port|:integer| `settings[:client][:socket][:port]` | Port to send events to when handled|

#### client_socket_xxx

SNMPTrap has to use the sensu client socket to emit events when traps arrive.
This is because there does not appear to be an asynchronous mechanism to send
event objects into sensu-client directly, so instead a brief TCP connection
to the sensu-client is made.

The extension tries to get the configuration from the sensu config.json, so
this should not require changing, but if you'd like to send events to another
sensu-client you can do so here.


## Appendix

### snmp-mibs-downloader - My SNMP doesn't work

If youre using a Debian/Ubuntu based distro, you may find it hard to get SNMP working
as it doens't include the set of MIB definitions required for alot of common systems.

This is because those definitions have been copyrighted by various organisations and
as such can only be obtained on the 'non-free' channels.

To help get setup without having to install the non-free distribution, you can use
the following few commands to get updated (and therefore working) MIB lists


```
apt-get install smistrip snmp
wget http://ftp.uk.debian.org/debian/pool/non-free/s/snmp-mibs-downloader/snmp-mibs-downloader_1.1_all.deb
dpkg -i snmp-mibs-downloader_1.1_all.deb
```


### Testing your configuration

Add a configuration file like this into `/etc/sensu/traps.d/example_heartbeat.json`

```
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
   }
 ]
```

And then run the following command;

```
    snmptrap -v 2c -c public localhost:1062 "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification  netSnmpExampleHeartbeatRate i 123456
```

> Requires the `snmp` package to be installed

# License

Released under the same terms as Sensu (the MIT license).
