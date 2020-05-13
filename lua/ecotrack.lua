#!/usr/bin/lua
--[[
   Lua program - ecotrack.lua
   Copyright (C) 2020 R.J.Middleton   e-mail: dick@lingbrae.com
   GPL3 - GNU General Public License version 3 or later

   Original:   6-May-20
--]]
local VERSION = [[
   Last-modified: 2020-05-13  10:22:08 on penguin.lingbrae" ]]
--[[
   Description :  ecotrack: a mash of the original:
   a) github.com/mastrogippo/Prism-UBUS-MQTT-LUA-daemon, 
   b) MQTT example https://github.com/karlp/lua-mosquitto-examples
   c) and my own site needs
--]]

require "pl"       -- penlight (app, lapp, config, utils)
require "pl.strict"

local bit = require "bit"    -- bitop
local ubus = require "ubus" 
local uloop = require "uloop"
local mosq = require "mosquitto"

app.require_here()
local log = require "log"
local system = require "system" -- signal and fork
local ect = require "ect"       -- ecotrack functions

local MOSQ_IDLE_LOOP_MS = 250
local UBUS_IDLE_LOOP_MS = 250

uconn = nil
mqtt = nil

local state = { mqtt_reconnection_count = 0 }

local function setup_ubus()
   --connect UBUS
   local conn = ubus.connect(nil, UBUS_IDLE_LOOP_MS)
   if not conn then
      error("Failed to connect to ubusd")
      do return end
   end
   conn:subscribe( "evse.control", {notify = function(msg) log.trace(pretty.write(msg)) end  })
   return conn
end

local function cleanup_mqtt()
   state.mqtt_fdr:delete()
   state.mqtt_fdw:delete()
   state.mqtt_idle_timer:cancel()
end

local function handle_mqtt_status(tag, rc, errno, errstr)
   if errno then
      log.warn("Unexpected MQTT Status(%s):%d-> %s", tag, errno, errstr)
      cleanup_mqtt()
   end
end

local function handle_ON_LOG(level, string)
   log.debug("mq log: %d->%s", level, string)
end

local function handle_ON_DISCONNECT(was_clean, rc, str)
   if was_clean then
      log.warn("Client explicitly requested disconnect")
   else
      log.error("Unexpected disconnection: %d -> %s", rc, str)
   end
   state.mqtt_connected = false
end

local function handle_ON_CONNECT(success, rc, str)
   state.mqtt_working = false
   --log.trace("on connect ->", success, rc, str)
   if not success then
      log.error("Failed to connect: %d : %s", rc, str)
      return
   end
   state.mqtt_connected = true
   for _,v in pairs(ect.topics) do
      if not mqtt:subscribe(v, 0) then
	 -- An abort here is probably wildly overagressive.  could just call cleanup_mqtt() and let it try again.
	 -- kinda hard to test this? maybe insert a delay in this handler? and stop broker in the meantime?
	 log.fatal("Aborting, unable to subscribe to MQTT: %s", v)
	 os.exit(1)
      end
   end
end

--- Socket event handers
-- @param ufd unused, but would be the mosquitto socket
-- @param events read/write

local function mqtt_fd_handler(ufd, events)
   if bit.band(events, uloop.ULOOP_READ) == uloop.ULOOP_READ then
      handle_mqtt_status("read", mqtt:loop_read())
   elseif bit.band(events, uloop.ULOOP_WRITE) == uloop.ULOOP_WRITE then
      handle_mqtt_status("write", mqtt:loop_write())
   end
   -- We don't recurse here so we actually share cpu
   if mqtt:want_write() then
      uloop.timer(function()
		     -- fake it til you make it!
		     mqtt_fd_handler(ufd, uloop.ULOOP_WRITE)
		  end, 10) -- "now"
   end
end

--- Periodic task for maintaining connections and retries within client
--
local function mqtt_idle_handler()
   handle_mqtt_status("misc", mqtt:loop_misc())
   state.mqtt_idle_timer:set(MOSQ_IDLE_LOOP_MS)
end

--- Initiate a connection, and install event handlers
--
local function setup_mqtt()
   mqtt.ON_MESSAGE = ect.handle_ON_MESSAGE
   mqtt.ON_CONNECT = handle_ON_CONNECT
   --mqtt.ON_LOG = handle_ON_LOG
   mqtt.ON_DISCONNECT = handle_ON_DISCONNECT
   local _, errno, strerr = mqtt:connect_async(ect.conf["broker_ip"], ect.conf["broker_port"], 60)
   if errno then
      -- Treat this as "fatal", means internal syscalls failed.
      error("Failed to connect: " .. strerr)
   end
   state.mqtt_working = true

   state.mqtt_fdr = uloop.fd_add(mqtt:socket(), mqtt_fd_handler, uloop.ULOOP_READ)
   state.mqtt_fdw = uloop.fd_add(mqtt:socket(), mqtt_fd_handler, uloop.ULOOP_WRITE)
   state.mqtt_idle_timer = uloop.timer(mqtt_idle_handler, MOSQ_IDLE_LOOP_MS)
   if mqtt:want_write() then
      uloop.timer(function()
		     mqtt_fd_handler(mqtt:socket(), uloop.ULOOP_WRITE)
		  end, 10) -- "now"
   end

end

--- Backoff on reconnection attempts a little bit
-- (totally unnecessary for this demo)
local function mqtt_calculate_reconnect(st)
   if st.mqtt_reconnection_count < 5 then
      return 1500
   end
   if st.mqtt_reconnection_count < 20 then
      return 2500
   end
   return 5000
end

local function main()
   uloop.init()
   mosq.init()
   uconn = setup_ubus()
   ect.init(VERSION)
   mqtt = mosq.new()
   setup_mqtt()

   -- test the mqtt connection and trigger a reconnection if needed.
   state.mqtt_stay_alive = uloop.timer(
      function()
	 state.mqtt_stay_alive:set(mqtt_calculate_reconnect(state))
	 if not state.mqtt_connected then
	    if not state.mqtt_working then
	       uloop.timer(function()
			      if not pcall(setup_mqtt) then
				 state.mqtt_reconnection_count = state.mqtt_reconnection_count + 1
				 log.warn("Failed mqtt reconnection attempt: %d", state.mqtt_reconnection_count)
			      else
				 state.mqtt_reconnection_count = 0
			      end
			   end, 50) -- "now"
	    end
	 end
      end, mqtt_calculate_reconnect(state))
   
   uloop.run()
   log.info(">>>post uloop.run()")
   cleanup_mqtt()
end

-- ################################################## --


if ect.opts.daemon then
   system.forkme()
end
main()

--[[
Karl Palsson, 2016 <karlp@tweak.net.au>
   Demo of event based reconnecting mqtt client using OpenWrt''s uloop/libubox
Not entirely happy with how verbose it is, with flags, but uses only 
the async methods, and successfully reconnects well.
--]]

--[[
 Local Variables:
 mode: lua
 time-stamp-pattern: "30/Last-modified:[ \t]+%:y-%02m-%02d  %02H:%02M:%02S on %h"
 End:
--]]
