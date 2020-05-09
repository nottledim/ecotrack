# ecotrack
#### lua program ecotrack.lua

## Installation
 You'll need root access to the Prism to install these programs.

 Lua program ecotrack.lua requires penlight, bit logic, cjson and posix which must be installed:

        opkg install penlight
        opkg install luabitop
        opkg install lua-cjson
	opkg install luaposix

  Ecotrack can run as a daemon: `ecotrack -dq` otherwise it runs in the foreground. 

## Program
  Ecotrack accepts the following options:

  +  -d,--daemon   Run as daemon
  +  -q,--quiet    Suppress messages  (set level to warn)
  +  -c,--config (optional string) Path to config file
  +  -l,--level (optional level default info) log level (fatal, error, warn, info, debug, trace)
  +  -v,--version  Version

The config file is expected to be in same directory as the main script
unless otherwise specified on the command line.

- Quiet option supresses informational message. Errors are written to stderr anyway.
- Version option prints current configuration and version string. If Quiet then only
  version string is printed.
- Log messages are printed to /tmp/ecotrack.log when in daemon mode. The level for the log file is 'warn'.

The program can be terminated with SIGINT or by sending 'eXit' as the
message to topic-control.

## Configuration

   Configuration is in ecotrack.cfg unless -c path is given.

   Mostly self explanatory.  You need to provide IP address of external
MQTT broker.  The various values are in amps and should be set to
match your installation.  The Hysteresis value is a ratio intended to increase
the range that the feed has to change before the charge current is changed in
order to reduce hunting between current levels.

The file is organised as key:value pairs with space separator.

    broker-ip xxx.xxx.xxx.xxx
    broker-port 1883
    
    # receives data on these topics
    topic-data emon/data
    topic-control cmnd/prism/mode
    
    # emits data on these topics
    topic-pub-ca stat/prism/cA
    topic-pub-status stat/prism/status
    
    # min current allowed by evse
    min-curr 6
    # max current avail from solar
    max-curr 16
    # max current from evse
    max-uvse 32
    # flow reduction to provide hysteresis 
    hysteresis 0.93
    # initial mode at start
    start-mode auto

+ topic-pub-cA is emitted when the max current value is changed.
+ topic-pub-status is emitted every minute initiated by receipt of
  emon/data message with type "day".

### Notes
The following debug features currently exist:

+ The message "eXit" sent to topic-control will terminate the program.
+ The message "sTatus" sent to topic-control will cause ecotrack.lua
  to emit the EVSE status on stderr.

Modifications to the lua program will most likely be in function
handle_ON_MESSAGE where the MQTT messages are processed.
