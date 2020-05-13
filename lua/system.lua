#!/usr/bin/lua
--[[
   Lua program - ecotrack.lua
   Copyright (C) 2020 R.J.Middleton   e-mail: dick@lingbrae.com
   GPL3 - GNU General Public License version 3 or later

   Original:   6-May-20

   Last-modified: 2020-05-12  16:45:07 on penguin.lingbrae"

--]]

local M = { _version = "0.1.0" }
local sys = require "posix.unistd"
local syswait = require 'posix.sys.wait'
local signal = require "posix.signal"

local signals = { "SIGINT", "SIGHUP", "SIGTERM", "SIGQUIT" }
for i,v in ipairs(signals) do
   signal.signal(signal[v],
	      function(signum)
		 io.write("trapped " .. v);
		 io.write("\n")
		 -- put code to save some stuff here
		 os.exit(128 + signum)
	      end
   )
end

function M.forkme()
   local pid1 = sys.fork()
   if pid1 ~= 0 then
      syswait.wait()
      os.exit()
   else
      local pid2 = sys.fork()
      if pid2 ~= 0 then
	 os.exit()
      end
   end
end

return M

--[[
 Local Variables:
 mode: lua
 time-stamp-pattern: "30/Last-modified:[ \t]+%:y-%02m-%02d  %02H:%02M:%02S on %h"
 End:
--]]
