# ecotrack

ecotrack is a simple program that adds to the capability of the Prism
EVSE by setting the charge current to track the surplus current generated
by solar panels. The data it uses is supplied externally by MQTT
messages.

There are two different versions of this program: a shell script and a
lua program.  The functions of both are much the same.

        git clone https://github.com/nottledim/ecotrack.git

### Origin
ecotrack.lua: a mash of the original:

1 github.com/mastrogippo/Prism-UBUS-MQTT-LUA-daemon, 
1 MQTT example https://github.com/karlp/lua-mosquitto-examples
1 and my own site needs

## Prism

Prism is an electric vehicle charge point created by Cartender of
Padova Italy. It's an open hardware design originally featured on
![Hackaday](https://hackaday.io/project/166859-prism) and made
available by ![Crowd
Supply](https://www.crowdsupply.com/cartender/prism).

## MQTT Messages

I use a early version of the ![Open
EnergyMonitor](https://openenergymonitor.org/) arduino shield to
measure my house feed, solar generation and EV charge current. Your
source of data is likely to be different and you'll have to modify the
script/program to suit.  The essential data is the house feed power
and voltage (or current). My device generates data every 3.6s.

N.B. If you monitor your house feed by direct connection to the Prism then
this program is not required.

Control of the program is by simply sending an MQTT message. This is
quite easy to send from "home assistant" for example.  It may not be
necessary to change the mode from "auto" if that is your preference..

1 TOPIC_CONTROL (cmnd/prism/mode) allows you to change the operation
mode from "auto" where it tracks the house feed current to a fixed
maximum current value.

* "full" set current to EVSE maximum (32A)
* "half" set current to maximum from the solar panels (16A)
* "min"  set the current to the minimum permitted (6A)
* number set the max current to given value

2 TOPIC_DATA (emon/data) is a message from your monitoring device. It
expects a JSON encoded message comprising the following properties:

* "type" is the type of message and only "power" is used (other types are ignored)
* "pwr1" is the house feed power in watts. Positive is import, negative is export.
* "volts" is the mains voltage at the time of the measurement.  It's used to compute the current.
* Other values are not used at this time.

### Notes
The following debug features currently exist:

+ Any MQTT message received by ecotrack.lua with message "quit" will terminate the program.
+ Sending topic cmnd/prism/status will cause ecotrack.lua to emit the EVSE status on stderr.

Modifications to the lua program will most likely be in function
handle_ON_MESSAGE where the MQTT messages are processed.
