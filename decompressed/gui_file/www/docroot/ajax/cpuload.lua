local json = require("dkjson")
local proxy = require("datamodel")
local readfile = require("web.content_helper").readfile
local post_helper = require("web.post_helper")
local ngx = ngx

local ram_data = proxy.get("sys.mem.RAMUsed")
local ram = (ram_data and ram_data[1] and tonumber(ram_data[1].value)) or 0
local function get_current_cpu_usage()
	local f = io.open("/proc/stat", "r")
	if not f then
		local c = proxy.get("sys.proc.CurrentCPUUsage")
		return (c and c[1] and c[1].value) or "0"
	end
	local line = f:read("*l")
	f:close()
	if not line then
		return "0"
	end
	local user, nice, sys, idle, iowait, irq, softirq, steal = line:match("^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
	if not user then
		return "0"
	end
	local cur_idle = tonumber(idle) + tonumber(iowait)
	local cur_total = cur_idle + tonumber(user) + tonumber(nice) + tonumber(sys) + tonumber(irq) + tonumber(softirq) + tonumber(steal)

	local up_f = io.open("/proc/uptime", "r")
	local now = up_f and up_f:read("*n")
	if up_f then up_f:close() end
	if not now then now = os.time() end

	local usage = nil
	local prev_file = io.open("/tmp/.cpu_prev", "r")
	if prev_file then
		local prev_total = prev_file:read("*n")
		local prev_idle = prev_file:read("*n")
		local prev_time = prev_file:read("*n")
		prev_file:close()
		if prev_total and prev_idle and cur_total > prev_total then
			local elapsed = (prev_time and (now - prev_time)) or 999
			-- Only trust delta if the sample interval is fresh (between 1s and 12s, normal poll is 5s)
			if elapsed >= 1 and elapsed <= 12 then
				local dt = cur_total - prev_total
				local di = cur_idle - prev_idle
				if dt > 0 and di >= 0 and di <= dt then
					usage = math.floor(((dt - di) / dt) * 100)
				end
			end
		end
	end

	local out_file = io.open("/tmp/.cpu_prev", "w")
	if out_file then
		out_file:write(string.format("%d %d %.2f\n", cur_total, cur_idle, now))
		out_file:close()
	end

	if usage then
		return tostring(usage)
	end

	local c = proxy.get("sys.proc.CurrentCPUUsage")
	if c and c[1] and c[1].value and c[1].value ~= "" then
		return c[1].value
	end
	local c_old = proxy.get("sys.proc.CPUUsage")
	if c_old and c_old[1] and c_old[1].value and c_old[1].value ~= "" then
		return c_old[1].value
	end
	return "0"
end

local cpu_usage = get_current_cpu_usage()

local data = {
	cpuusage = cpu_usage .. "%",
	ram_used = math.floor(ram / 1024),
	uptime = post_helper.secondsToTime(readfile("/proc/uptime","number",floor)),
	connection = readfile("/proc/sys/net/netfilter/nf_conntrack_count"),
	system_time = os.date("%d/%m/%Y %Hh:%Mm:%Ss",os.time()),
	cpuload = readfile("/proc/loadavg","string"):sub(1,14),
}

local buffer = {}
if json.encode (data, { indent = false, buffer = buffer }) then
	ngx.say(buffer)
else
	ngx.say("{}")
end
ngx.exit(ngx.HTTP_OK)
