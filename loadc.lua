-- 6-May-2020 RJM Added file argument
local loadc = {};

function loadc.load(file)
   conf = {}
   
   fp = io.open( file or "mqtt-lua.cfg", "r" )
   
   for line in fp:lines() do
      line = line:match( "%s*(.+)" )
      if line and line:sub( 1, 1 ) ~= "#" and line:sub( 1, 1 ) ~= ";" then
	 option = line:match( "%S+" ):lower()
	 value  = line:match( "%S*%s*(.*)" )
	 
	 if not value then
	    conf[option] = true
	 else
	    if not value:find( "," ) then
	       conf[option] = value
	    else
	       value = value .. ","
	       conf[option] = {}
	       for entry in value:gmatch( "%s*(.-)," ) do
		  conf[option][#conf[option]+1] = entry
	       end
	    end
	 end
	 
      end
   end
   
   fp:close()
   return conf
end

return loadc;
