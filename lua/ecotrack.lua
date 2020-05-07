#!/usr/bin/lua
--[[ 6-May-2020 RJM - ecotrack: a mash of the original:
   a) github.com/mastrogippo/Prism-UBUS-MQTT-LUA-daemon, 
   b) MQTT example https://github.com/karlp/lua-mosquitto-examples
   c) and my own site needs
   ]]

local bit = require "bit"
local ins = require "inspect"
local ubus = require "ubus"
local cjson = require "cjson"
local uloop = require "uloop"
local mosq = require("mosquitto")
local loadc = require "loadc"
local signal = require("posix.signal")
local conf = loadc.load("ecotrack.cfg");

local cmin= tonumber(conf["min_curr"] or 6)
local cmax = tonumber(conf["max_curr"] or 16)   -- max avail from solar
local umax = tonumber(conf["max_uvse"] or 32)   -- max from evse
local hyst = tonumber(conf["hysteresis"] or 0.93)

local last = -1
local curr = 0
local mode = "auto"

local quiet = conf["quiet"]

signal.signal(signal.SIGINT,
	      function(signum)
		 io.write("trapped SIGINT");
		 io.write("\n")
		 -- put code to save some stuff here
		 os.exit(128 + signum)
	      end
	     )

local MOSQ_IDLE_LOOP_MS = 250
local topics = {
   data = conf["topic_data"] or "emon/data",
   mode = conf["topic_control"] or "cmnd/prism/mode",
   status = "cmnd/prism/status",
}

local function setup_ubus()
   --connect UBUS
   local conn = ubus.connect(null, 250)
   if not conn then
      error("Failed to connect to ubusd")
      do return end
   end
   conn:subscribe( "evse.control", {} )
   return conn
end

local printf = function(...)
   --print(string.format(...))
   io.stderr:write(string.format(...) .. "\n")
end
local printv = function(...)
   if not quiet then
      print(string.format(...))
   end
end

printv("Ecotrack starting")
uloop.init()
mosq.init()
local uconn = setup_ubus()
local mqtt
--printf(ins.inspect(conf))

local get_status = function()
   local status = uconn:call("evse.control", "get_status", {})--{ name = "eth0" })
   if status == nil then
      printf("UBUS ERROR - status: no answer from EVSE")
      do return end
   end
   return status.result.ports[1]
end

local change_current = function()
   if  curr ~= last  then
      last = curr 
      tm = os.date("%X") --`date +%T`
      local status = uconn:call("evse.control", "set_current", {port = 1, current_max = curr} )
      if status == nil then
	 printf("UBUS ERROR - no answer from EVSE")
	 do return end
      else
	 printv( "%s - Current set to %dA", tm, curr)
	 if conf["topic_pub_ca"] then
	    local mid = mqtt:publish(conf["topic_pub_ca"], tostring(curr), 0, false)
	 end
      end
   end
end

local cmdtab = {
   auto = function()
      mode="auto"
   end,
   full = function()
      curr = umax
      mode = "manual"
      change_current()
   end,
   half = function()
      curr = cmax
      mode = "manual"
      change_current()
   end,
   min = function()
      curr = cmin
      mode = "manual"
      change_current()
      end
}

-- Initial mode at start
last = get_status().current_max
local f = cmdtab[conf["start_mode"] or "auto"]
if f then f() end

local function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending 
end

local state = { mqtt_reconnection_count = 0 }

local function cleanup_mqtt()
   state.mqtt_fdr:delete()
   state.mqtt_fdw:delete()
   state.mqtt_idle_timer:cancel()
end

local function handle_mqtt_status(tag, rc, errno, errstr)
   if errno then
      printf("Unexpected MQTT Status(%s):%d-> %s\n", tag, errno, errstr)
      cleanup_mqtt()
   end
end

local function handle_ON_MESSAGE(mid, topic, payload, qos, retain)
   if payload == "quit" then
      printf("magic quit payload for valgrind!")
      uloop.cancel()
      
   elseif topic == topics.data then
      local emon = cjson.decode(tostring(payload))
      if emon.type == 'power' then
	 local incr = math.floor(emon.pwr1 *-hyst/emon.volts +64) -63
	 local surplus = emon.ev - emon.pwr1
	 if mode == "auto" then
	    local status = get_status()
	    if (status) then
	       local charging = status.connected and status.status == 'charging'
	       if charging then
		  if incr then
		     curr = last + incr
		     if curr < cmin then
			curr = cmin
		     elseif curr >  cmax  then
			curr = cmax
		     end
		     change_current()
		  end
	       end
	    end
	 end
         --printf("Flow: %.1f Solar: %.1f  Surplus: %.1f  Incr: %s", emon.pwr1, emon.pwr2, surplus, incr)
      elseif emon.type == 'day' and conf["topic_pub_status"] then
	 local status = get_status()
	 if status then
	    local st = {}
	    if status.connected then
	       if status.status == 'charging' then
		  st.status = 'charging'
	       else
		  st.status = 'connected'
	       end
	    else
	       st.status = 'disconnected'
	    end
	    st.cmax = status.current_max
	    st.mode = mode
	    st.energy = string.format("%.1fkW.h", status.energy_session / 1000)
	    st.period = os.date("!%X", status._session_time_stm)
	    local mid = mqtt:publish(conf["topic_pub_status"], cjson.encode(st), 0, false)
	 end
      end
	 
   elseif topic == topics.mode then
      local f = cmdtab[tostring(payload)]
      if f then
	 printv("Change mode: %s", payload)
	 f()
      elseif tonumber(payload) ~= nil then
	 curr = tonumber(payload)
	 mode = "manual"
	 change_current()
      else
	 printf("ON_MESSAGE: topic:%s payload: %s", topic, payload)
      end
      
   elseif topic == topics.status then
      local status = get_status()
      printf("Status: " .. ins.inspect(status))

   else -- unexpected topic
      printf("ON_MESSAGE: topic:%s", topic)
   end
end

local function handle_ON_LOG(level, string)
   printf("mq log: %d->%s\n", level, string)
end

local function handle_ON_DISCONNECT(was_clean, rc, str)
   if was_clean then
      printf("Client explicitly requested disconnect\n")
   else
      printf("Unexpected disconnection: %d -> %s\n", rc, str)
   end
   state.mqtt_connected = false
end

local function handle_ON_CONNECT(success, rc, str)
   state.mqtt_working = false
   --printf("on connect ->", success, rc, str)
   if not success then
      printf("Failed to connect: %d : %s\n", rc, str)
      return
   end
   state.mqtt_connected = true
   for _,v in pairs(topics) do
      if not mqtt:subscribe(v, 0) then
	 -- An abort here is probably wildly overagressive.  could just call cleanup_mqtt() and let it try again.
	 -- kinda hard to test this? maybe insert a delay in this handler? and stop broker in the meantime?
	 printf("Aborting, unable to subscribe to MQTT: %s\n", v)
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
   mqtt.ON_MESSAGE = handle_ON_MESSAGE
   mqtt.ON_CONNECT = handle_ON_CONNECT
   --mqtt.ON_LOG = handle_ON_LOG
   mqtt.ON_DISCONNECT = handle_ON_DISCONNECT
   local _, errno, strerr = mqtt:connect_async(conf["broker_ip"], conf["broker_port"], 60)
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

--UBUS notify
local sub = {
   notify = function( msg, a, b )

      -- Ho la roba  su a!!!
      printf("got ubus=" .. ins.inspect(msg));
      printf("a=" .. ins.inspect(a));
      printf("b=" .. ins.inspect(b));

      if msg['voltage_now'] == nil then
	 printf("status_message");
	 do return end
      end

      --printf("MSG: "  .. ins.inspect(msg));
      if msg["port"] == 1 then
	 if msg['status'] == "error" then
	    printf("Error in SUB");
	 end
      end

      -- printf("Count: ", msg["status"])
   end,

   remove = function( a, b)
      --faccio partire un timer che riprova a collegardsi con subscribe
      printf("a=" .. ins.inspect(a));
      printf("b=" .. ins.inspect(b));

   end,
}


local function main()
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
				 printf("Failed mqtt reconnection attempt: %d\n", state.mqtt_reconnection_count)
			      else
				 state.mqtt_reconnection_count = 0
			      end
			   end, 50) -- "now"
	    end
	 end
      end, mqtt_calculate_reconnect(state))
   
   uloop.run()
   printf(">>>post uloop.run()\n")
   cleanup_mqtt()
end

main()

--[[
Karl Palsson, 2016 <karlp@tweak.net.au>
   Demo of event based reconnecting mqtt client using OpenWrt''s uloop/libubox
Not entirely happy with how verbose it is, with flags, but uses only 
the async methods, and successfully reconnects well.
]]
