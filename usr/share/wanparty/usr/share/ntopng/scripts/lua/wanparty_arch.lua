--
-- (C) 2017-11 Sohaib LAFIFI - Wan party
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local discover = require("discover_utils")

sendHTTPContentTypeHeader('text/json')

-- Table parameters
all = _GET["all"]
currentPage = _GET["currentPage"]
perPage     = _GET["perPage"]
sortColumn  = _GET["sortColumn"]
sortOrder   = _GET["sortOrder"]
protocol    = _GET["protocol"]
long_names  = _GET["long_names"]
criteria    = _GET["criteria"]

-- Host comparison parameters
mode        = _GET["mode"]
tracked     = _GET["tracked"]
ipversion   = _GET["version"]

-- Used when filtering by ASn, VLAN or network
asn          = _GET["asn"]
vlan         = _GET["vlan"]
network      = _GET["network"]
pool         = _GET["pool"]
country      = _GET["country"]
os_    	     = _GET["os"]
mac          = _GET["mac"]

-- Get from redis the throughput type bps or pps
throughput_type = getThroughputType()

if(long_names == nil) then
   long_names = false
else
   if(long_names == "1") then
      long_names = true
   else
      long_names = false
   end
end

criteria_key = nil
sortPrefs = "hosts"
if(criteria ~= nil) then
   criteria_key, criteria_format = label2criteriakey(criteria)
   sortPrefs = "localhosts_"..criteria
   mode = "local"
end
sortColumn = getDefaultTableSort(sortPrefs)
tablePreferences("sort_"..sortPrefs,sortColumn)

if(currentPage == nil) then
   currentPage = 1
else
   currentPage = tonumber(currentPage)
end

perPage = 100000
tablePreferences("rows_number",perPage)


if(tracked ~= nil) then tracked = tonumber(tracked) else tracked = 0 end

if((mode == nil) or (mode == "")) then mode = "all" end

interface.select(ifname)

to_skip = 0

if(sortOrder == "desc") then sOrder = false else sOrder = true end

local filtered_hosts = false

hosts_retrv_function = interface.getHostsInfo
if mode == "local" then
   hosts_retrv_function = interface.getLocalHostsInfo
elseif mode == "remote" then
   hosts_retrv_function = interface.getRemoteHostsInfo
elseif mode == "filtered" then
   filtered_hosts = true
end

hosts_stats = hosts_retrv_function(false, sortColumn, perPage, to_skip, sOrder,
	                           country, os_, tonumber(vlan), tonumber(asn),
				   tonumber(network), mac,
				   tonumber(pool), tonumber(ipversion), tonumber(protocol), filtered_hosts) -- false = little details

-- tprint(hosts_stats)
--io.write("---\n")
if(hosts_stats == nil) then total = 0 else total = hosts_stats["numHosts"] end
hosts_stats = hosts_stats["hosts"]
-- for k,v in pairs(hosts_stats) do io.write(k.." ["..sortColumn.."]\n") end


if(all ~= nil) then
   perPage = 0
   currentPage = 0
end

print ("{ \"data\" : [\n")

now = os.time()
vals = {}

num = 0
if(hosts_stats ~= nil) then
   for key, value in pairs(hosts_stats) do
	 num = num + 1
	 vals[key] = key -- hosts_stats[key]["ipkey"]
   end
end

num = 0
for _key, _value in pairsByKeys(vals, asc) do
   key = vals[_key]

   value = hosts_stats[key]

   if(num > 0) then print ",\n" end
   print ('{ ')
   symkey = hostinfo2jqueryid(hosts_stats[key])


   print ("\"ip\" : \"")
   print(mapOS2Icon(stripVlan(key)))

   local host = interface.getHostInfo(hosts_stats[key].ip, hosts_stats[key].vlan)
   print("\", ")

   if(url ~= nil) then
      print("\"url\" : \""..url.."\", ")
   end

   print("\"name\" : \"")

   if(value["name"] == nil) then
      value["name"] = getResolvedAddress(hostkey2hostinfo(key))
   end

   if(value["name"] == "") then
      value["name"] = key
   end

   if(long_names) then
      print(value["name"])
   else
      print(shortHostName(value["name"]))
   end

   if(value["ip"] ~= nil) then
      local label = getHostAltName(value["ip"], value["mac"])
      if(label ~= value["ip"]) then
	 print (" ["..label.."]")
      end
   end


   if value["has_blocking_quota"] or value["has_blocking_shaper"] then
      print("blocking_quota")
   end

   --   print("</div>")

   if((value["httpbl"] ~= nil) and (string.len(value["httpbl"]) > 2)) then print("\", \"httpbl\" : \"".. value["httpbl"]) end

   if(value["vlan"] ~= nil) then

      if(value["vlan"] ~= 0) then
	 print("\", \"vlan\" : "..value["vlan"])
      else
	 print("\", \"vlan\" : \"0\"")
      end

   else
      print("\", \"vlan\" : \"\"")
   end

 
   print(", \"since\" : \"" .. secondsToTime(now-value["seen.first"]+1) .. "\", ")
   print("\"last\" : \"" .. secondsToTime(now-value["seen.last"]+1) .. "\", ")


   if((criteria_key ~= nil) and (value["criteria"] ~= nil)) then
      print("\""..criteria.."\" : \"" .. criteria_format(value["criteria"][criteria_key]) .. "\", ")
   end

   if((value["throughput_trend_"..throughput_type] ~= nil) and
      (value["throughput_trend_"..throughput_type] > 0)) then

      if(throughput_type == "pps") then
	 print ("\"thpt\" : \"" .. pktsToSize(value["throughput_pps"]).. " ")
      else
	 print ("\"thpt\" : \"" .. bitsToSize(8*value["throughput_bps"]).. " ")
      end

     

      print("\",")
   else
      print ("\"thpt\" : \"0 "..throughput_type.."\",")
   end

   print("\"traffic\" : \"" .. bytesToSize(value["bytes.sent"]+value["bytes.rcvd"]) .. "\"")
   print("\"traffic_sent\" : \"" .. bytesToSize(value["bytes.sent"]) .. "\"")
   print("\"traffic_rcvd\" : \"" .. bytesToSize(value["bytes.rcvd"]) .. "\"")

   print("\"alerts\" : \"")
   if((value["num_alerts"] ~= nil) and (value["num_alerts"] > 0)) then
      print(""..value["num_alerts"])
   else
      print("0")
   end
   -- io.write("-------------------------\n")
   -- tprint(value)
   if(value["localhost"] ~= nil or value["systemhost"] ~= nil) then
      print ("\", \"location\" : \"")
      if value["localhost"] == true --[[or value["systemhost"] == true --]] then
	 print("local") else print("remote")
      end
      if value["is_blacklisted"] == true then
	 print(" blacklisted")
      end
   end
   print("\" } ")
   num = num + 1
end -- for

print ("\n] \n}")