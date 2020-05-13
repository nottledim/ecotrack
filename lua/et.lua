#!/usr/bin/lua
--[[
   Lua program - ecotrack.lua
   Copyright (C) 2020 R.J.Middleton   e-mail: dick@lingbrae.com
   GPL3 - GNU General Public License version 3 or later

   Original:   6-May-20

   Last-modified: 2020-05-12  12:17:05 on penguin.lingbrae"

--]]

local cjson = require "cjson" -- cjson
local srcdir = app.require_here()
local log = require "log"

local CONFIG_FILE_NAME = "ecotrack.cfg"
local LOG_FILE_NAME = "/tmp/ecotrack.log"
local ECO_OVER_LIMIT = 700      -- +ve surplus energy to change active state
local ECO_UNDER_LIMIT = 250     -- -ve surplus energy to change active state

lapp.add_type ("level", "string",
	       function(v)
		  lapp.assert(log.levels[v] ~= nil, "unknown level " .. v)
	       end
)

local opts = lapp [[
Controls the Prism EVSE
    -d,--daemon   Run as daemon
    -q,--quiet    Suppress messages (set level to warn)
    -c,--config (optional string) Path to config file
    -l,--level (optional level default info) log level (fatal, error, warn, info, debug, trace)
    -v,--version  Print version info
  ]]

log.level = opts.level or "warn"
if opts.quiet then   --  override level setting
   log.level = "warn"
end
if opts.daemon then
   log.outfile = LOG_FILE_NAME
end

local confile = opts.config or path.normpath(srcdir .. CONFIG_FILE_NAME)
local conf = config.read (confile, {keysep=' '})
if not conf then
   utils.quit("Failed to read config file: %s", confile)
end

local topics = {
   data = conf["topic_data"] or "emon/data",
   mode = conf["topic_control"] or "cmnd/prism/mode"
}

local stm_since = os.time()
local eco_since = 0

local STM_DWELL = 120   -- (s) delay between publishing status messages
local ECO_DWELL = 60    -- (s) delay between eco active state changes 

local cmin= tonumber(conf["min_curr"] or 6)
local cmax = tonumber(conf["max_curr"] or 16)   -- max avail from solar
local umax = tonumber(conf["max_evse"] or 32)   -- max from evse
local hyst = tonumber(conf["hysteresis"] or 0.93)

local last = -1
local curr = 0
local mode = nil                -- manual, auto, eco
local active = nil              -- active when enough surplus energy
local last_rq = nil

local get_status = function()
   local status = uconn:call("evse.control", "get_status", {})--{ name = "eth0" })
   if status == nil then
      log.error("UBUS ERROR - status: no answer from EVSE")
      do return end
   end
   return status.result.ports[1]
end

local function send_status_message()
   if conf["topic_pub_status"] then
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
	 st.enabled = active
	 st.energy = string.format("%.1fkW.h", status.energy_session / 1000)
	 st.period = os.date("!%X", status._session_time_stm)
	 local mid = mqtt:publish(conf["topic_pub_status"], cjson.encode(st), 0, false)
	 log.debug("status message")
      end
      stm_since = os.time()
   end
end

local change_current = function()
   if  curr ~= last  then
      last = curr 
      local rtn = uconn:call("evse.control", "set_current", {port = 1, current_max = curr} )
      if rtn == nil then
	 log.error("UBUS ERROR - no answer from EVSE")
	 do return end
      else
	 log.info( "Current set to %dA", curr)
	 if conf["topic_pub_ca"] then
	    local mid = mqtt:publish(conf["topic_pub_ca"], tostring(curr), 0, false)
	 end
	 send_status_message()
      end
   end
end

local cmdtab = {
   eco = function()
      mode = "eco"
   end,
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
function init(version)
   log.info("Ecotrack starting")

   last = get_status().current_max
   local f = cmdtab[conf["start_mode"] or "auto"]
   if f then f() end
   if mode == "eco" then
      active = false
   else
      active = true
   end
   last_rq = active

if opts.version and version then
   log.info("Config: %s", pretty.write(conf))
   local v = utils.split(version, "%s+")
   utils.quit("Version: %s %s", v[3], v[4])
end
end

local function charger_rq(rq)
   local charger_ctl = function(activate)
      active = activate
      last_rq = activate
      if active then
	 log.info("ECO mode: charging ON")
      else      
	 log.info("ECO mode: charging OFF")
      end
   end

   if mode == "eco" then
      if rq ~= nil then
	 if rq == active then
	    last_rq = active
	    log.debug("revert change")
	 elseif rq ~= active and active == last_rq then
	    last_rq = rq
	    eco_since = os.time()
	    log.debug("start timer")
	 elseif rq ~= active and active ~= last_rq and os.difftime(os.time(), eco_since) >= ECO_DWELL then
	    log.debug("timeout charger 1")
	    charger_ctl(rq)
	 end
      elseif active ~= last_rq and os.difftime(os.time(), eco_since) >= ECO_DWELL then
	 log.debug("timeout charger 2")
	 charger_ctl(last_rq)
      end
   elseif not active then
      log.debug("start charger not eco")
      charger_ctl(true)
   end
end

local function handle_ON_MESSAGE(mid, topic, payload, qos, retain)
   if topic == topics.data then
      local emon = cjson.decode(tostring(payload))
      if emon.type == 'power' then
	 local incr = math.floor(emon.pwr1 *-hyst/emon.volts +64) -63
	 local surplus = emon.ev - emon.pwr1
	 if mode ~= "manual" then  -- auto or eco
	    local status = get_status()
	    if (status) then
	       if status.connected then
		  if mode == "eco" then
		     if active and surplus < -ECO_UNDER_LIMIT then
			charger_rq(false)
		     elseif not active and (surplus > ECO_OVER_LIMIT) then
			charger_rq(true)
		     end
		  end
		  if status.status == 'charging' then 
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
	 end
	 charger_rq()
	 if os.difftime(os.time(), stm_since) >= STM_DWELL then
	    send_status_message()
	 end
         log.trace("Flow: %.1f Solar: %.1f  Surplus: %.1f  Incr: %s", emon.pwr1, emon.pwr2, surplus, incr)
      end

   elseif topic == topics.mode then
      if payload == "eXit" then
	 uloop.cancel()
	 utils.quit("Ecotrack terminated")
      
      elseif payload == "sTatus" then
	 local status = get_status()
	 log.info("Status: \n%s", pretty.write(status))

      else
	 local payl = tostring(payload)
	 local f = cmdtab[payl]
	 if f then
	    log.info("Change mode: %s", payl)
	    f()

	 elseif log.levels[payl] then
	    log.level = payl
	    log.log(payl, "Changed log level to: %s", payl)
	    
	 elseif tonumber(payload) ~= nil then
	    curr = tonumber(payload)
	    mode = "manual"
	    change_current()

	 else
	    log.warn("ON_MESSAGE: topic:%s payload: %s", topic, payload)
	 end
	 charger_rq()
      end

   else -- unexpected topic
      log.warn("ON_MESSAGE: topic:%s", topic)
   end
end
return { -- export
   _version = "0.1.0",
   topics = topics,
   conf = conf,
   opts = opts,
   handle_ON_MESSAGE = handle_ON_MESSAGE,
   init = init
}
--[[
 Local Variables:
 mode: lua
 time-stamp-pattern: "30/Last-modified:[ \t]+%:y-%02m-%02d  %02H:%02M:%02S on %h"
 End:
--]]
