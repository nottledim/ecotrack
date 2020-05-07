# ecotrack
### Shell script ecotrack.sh

## Installation
 You'll need root access to the Prism to install these programs.

 Shell script ecotrack.sh can be run from the shell or at startup from /etc/rc.local.
  It's best to detach it as in

        $(./ecotrack.sh &> /dev/null &)&

  You need to install the jq program

        opkg install jq

## Configuration

  Configuration is in ecotrack.sh.cfg


  Mostly self explanatory.  You need to provide IP address of external
MQTT broker.  The various values are in amps and should be set to
match your installation.  The Hysteresis value is a ratio intended to increase
the range that the feed has to change before the charge current is changed in
order to reduce hunting between current levels.
    
    MQTT_BROKER="xxx.xxx.xxx.xxx"
    TOPIC_DATA="emon/data"
    TOPIC_CONTROL="cmnd/prism/mode"
    
    MIN_CURR=6    # min allowed by evse
    MAX_CURR=16   # max avail from solar
    MAX_UVSE=32   # max from evse
    HYSTERESIS="0.93"  #flow reduction to provide hysteresis 
    START_MODE="auto" # initial mode at start
