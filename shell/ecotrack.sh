#!/bin/sh
# 18-Apr-20 RJM
# emon/data record:  {"type":"power","volts":238.4,"pwr1":2777.7,"pwr2":1679.6,"ev":1390.4,"used":3066.8}
# pwr1 is flow from utility
# pwr2 is pv
# Read configuration variable file if it is present

CONFIG="$(dirname $0)/ecotrack.sh.cfg"
[ -r $CONFIG ] && . $CONFIG
echo "config: $CONFIG"

broker="${MQTT_BROKER:-192.168.46.7}"
emonflow="${TOPIC_DATA:-emon/data}"
control="${TOPIC_CONTROL:-cmnd/prism/rate}"

cmin=${MIN_CURR:-6}
cmax=${MAX_CURR:-16}   # max avail from solar
umax=${MAX_UVSE:-32}   # max from evse
hyst="${HYSTERESIS:-0.93}"

last=-1
curr=0
mode="auto"

###
 
change_current() {
    if [ $curr -ne $last ]; then
	last=$curr 
	tm=`date +%T`
	echo "$tm - Setting current to ${curr}A" 
	ubus call evse.control set_current "{\"port\":1, \"current_max\":$curr}"  &>/dev/null
    fi
}

set_mode() {
    case "$1" in
	"min")
	    curr=$cmin
	    mode="manual"
	    change_current
	    ;;
	"full")
	    curr=$umax
	    mode="manual"
	    change_current
	    ;;
	"half")
	    curr=$cmax
	    mode="manual"
	    change_current
	    ;;
	"auto")
	    mode="auto"
	    ;;
    esac
}    

####

set_mode "${START_MODE:=auto}"

#echo "broker: $broker"
#echo "emonflow: $emonflow"
#echo "control: $control"
#echo "cmin: $cmin"
#echo "cmax: $cmax"
#echo "umax: $umax"
#echo "hyst: $hyst"

mosquitto_sub -h $broker -v -t $emonflow -t $control | \
    while read topic message
    do
	if [ $topic = $emonflow ]
	then
	    if [ $mode = "auto" ]
	    then
		ready=`ubus call evse.control get_status {} | jq '.result.ports[]|.status == "charging" and .connected'`
#		ready="true"
 		if [ "$ready" = "true" ]; then
		    incr=`echo $message | jq --unbuffered ".|select(.type==\"power\")|(.pwr1 *-$hyst/.volts +64|floor -63)"`
		    if [ -n "$incr" ]
		    then
			curr=$(( $last + $incr ))
			if [ $curr -lt $cmin ]; then
			    curr=$cmin
			elif [ $curr -gt $cmax ]; then
			    curr=$cmax
			fi
			change_current
		    fi
		fi
	    fi
	elif [ $topic = $control ]
	then
	    set_mode "$message"
	fi
    done
