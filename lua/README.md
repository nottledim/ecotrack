# ecotrack
#### lua program ecotrack.lua

## Installation
 You'll need root access to the Prism to install these programs.

 Lua program ecotrack.lua requires bit logic, cjson and posix which must be installed:

        opkg install luabitop
        opkg install lua-cjson
	opkg install luaposix

  It's best to detach it as in

        $(./ecotrack.lua  &)&

  to run in the background.

## Configuration

   Configuration is in ecotrack.cfg

   Mostly self explanatory.  You need to provide IP address of external
MQTT broker.  The various values are in amps and should be set to
match your installation.  The Hysteresis value is a ratio intended to increase
the range that the feed has to change before the charge current is changed in
order to reduce hunting between current levels.
    
    BROKER_IP xxx.xxx.xxx.xxx
    BROKER_PORT 1883
    
    # receives data on these topics:
    TOPIC_DATA emon/data
    TOPIC_CONTROL cmnd/prism/mode
    
    # emits data on these topics
    TOPIC_PUB_CA stat/prism/cA
    TOPIC_PUB_STATUS stat/prism/status
    
    # min current allowed by evse
    MIN_CURR 6
    # max current avail from solar
    MAX_CURR 16
    # max current from evse
    MAX_UVSE 32
    #flow reduction to provide hysteresis 
    HYSTERESIS 0.93
    # initial mode at start
    START_MODE auto
    
    # To stop output on stdout set QUIET flag
    QUIET
