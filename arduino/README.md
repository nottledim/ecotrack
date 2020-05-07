# ecotrack
### Arduino sketch to control fron panel LEDs

## Front Panel

  Prism front panel is controlled messages sent via rs232 connection available for Front Panel connector on core.

Note:

1. All signals are 3v3 whereas power on the connector is 5v.
2. Tx is on pin 2 and Rx is on pin 3
3. Baud rate is 9600

## Hardware

I used a Arduino Pro Mini 3v3 8M to drive simple LEDs on my front
panel. Only Red and Green LEDs are available so an error signal is
displayed by flashing red and green. Ideally a blue LED should be used
for "charging" state.

+ Connect 5v to Arduino "raw" input.  Onboard regulator converts to 3v3.
+ If higher currents and/or voltages are needed to drive LEDs then an open collector buffer must be used.
  That will invert signal lines.

## Protocol
Command sequences start with 'a', end with 'z'
   
    a | command init   
    z | command end     
    b | brightness      b1-5
    c | charging       
    s | idle (default) 
    E | error   
    o | off

+ Real sequences contain a double zero before the 'z' as in 'ac00z'
