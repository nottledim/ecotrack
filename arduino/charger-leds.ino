// 17-Apr-20 RJM
#include "elapsedMillis.h"

#define LED_GREEN 10
//#define LED_BLUE  11
#define LED_RED   11
#define LED_BUILTIN 13

#define LEDON  LOW
#define LEDOFF HIGH

enum Lamp {off, idle, charging, error};
int state = 0;
bool blinkr = false;
bool blink = false;
elapsedMillis blinkt;
const long interval = 400;

#define DEBUG 0
#define PRINT(m) \
  do { if (DEBUG) Serial.print(m); } while (0)
#define PRINTLN(m) \
  do { if (DEBUG) Serial.println(m); } while (0)

void setup() {
 Serial.begin(9600);
 pinMode(LED_GREEN, OUTPUT);
 // pinMode(LED_BLUE, OUTPUT);
 pinMode(LED_RED, OUTPUT);
 pinMode(LED_BUILTIN, OUTPUT);
 digitalWrite(LED_BUILTIN, LOW);
 setLED(idle);
 PRINTLN("Front display is ready");
}

elapsedMillis flasht;
bool flashb = false;
long flashi = 0;
int fmode = 0;
int flashtab[4][2] = {0,0,
		      1,9,
		      14,1,
		      1,1};

void loop() {
  static char chr, cmnd, brt;

  if (flasht >= flashi) {
    flasht = 0;
    flashb = !flashb;
    int onoff = flashtab[fmode][flashb?1:0];
    if (onoff) {
      flashi = onoff * 100;
      digitalWrite(LED_BUILTIN, flashb?LEDON:LEDOFF);
    }
    else {
      flashi = 250;
      digitalWrite(LED_BUILTIN, LOW);
	}
  }
  if (blinkt >= interval) {
    blinkt = blinkt - interval;
    blinkr = !blinkr;

    if (blink) {
      if (blinkr) {
	digitalWrite(LED_RED, LEDON);
	digitalWrite(LED_GREEN, LEDOFF);
      }
      else {
	digitalWrite(LED_RED, LEDOFF);
	digitalWrite(LED_GREEN, LEDON);
      }
    }
  }
  
  if (Serial.available() > 0) {
    chr = Serial.read();
    PRINT(chr);
    switch (state) {
    case 0:    // wait for 'a'
      brt = 0;
      if (chr == 'a') state = 1;
      break;
      
    case 1:  // wait for command char
      if (chr == 'c' || chr == 's' || chr == 'o' || chr == 'E') {
	cmnd = chr;
	state = 2;
      }
      else if (chr == 'b') {
	cmnd = chr;
	state = 3;
      }
      else state = 0;
      break;
      
    case 2:   // wait for 'z'
      if (chr == 'c' || chr == 's' || chr == 'o' || chr == 'E') {
	cmnd = chr;
	state = 2;
      }
      else if (chr == '0') { // ignore
	state = 2;
      }
      else if (chr == 'b') {
	state = 3;
      }
      else if (chr == 'z') {
	PRINT("Command is: ");
	switch (cmnd) {
	case 'c':
	  PRINTLN("Charging");
	  setLED(charging);
	  break;
	case 's':
	  PRINTLN("Idle");
	  setLED(idle);
	  break;
	case 'o':
	  PRINTLN("Off");
	  setLED(off);
	  break;
	case 'E':
	  PRINTLN("Error");
	  setLED(error);
	  break;
	}
	if (brt) {
	  PRINT("Brightness: ");
	  PRINTLN(brt);
	}
	PRINTLN();
	state = 0;
      }
      else state = 0;
      break;
    case 3:  // wait for number 1..5
      if (chr >= '1' && chr <= '5') {
	brt = chr;
	state = 2;
      }
      else state = 0;
      break;
    }
  }
}

void setLED(Lamp ledid) {
  //  digitalWrite(LED_BLUE, LEDOFF);
  blink = false;
  fmode = ledid;
  switch(ledid) {
  case 0:   // off
    digitalWrite(LED_RED, LEDOFF);
    digitalWrite(LED_GREEN, LEDOFF);
    break;
  case 1:   // Green Idle
    digitalWrite(LED_RED, LEDOFF);
    digitalWrite(LED_GREEN, LEDON);
    PRINTLN("Green");
    break;
  case 2:   // Red Charging
    digitalWrite(LED_GREEN, LEDOFF);
    digitalWrite(LED_RED, LEDON);
    PRINTLN("Red");
    break;
  case 3:   // Red/Green Error
    blink = true;
    PRINTLN("Blink");
    break;
  }
}
