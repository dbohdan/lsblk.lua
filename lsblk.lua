#! /usr/libexec/flua
-- https://github.com/dbohdan/freebsd-lsblk-lua

local VERSION = "0.1.0"

local function run_cmd(cmd)
	local f = io.popen(cmd .. " 2>/dev/null", "r")
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()
	return lines
end

local function get_major_minor(dev)
	if not dev then
		return "-", "-"
	end

	local attr = lfs.attributes("/dev/" .. dev)
	if attr then
		local major = math.floor(attr.rdev // 2 ^ 8)
		local minor = attr.rdev % 2 ^ 8
		return major, minor
	end

	return "-", "-"
end

local function geom_parse_value(v)
	if v == "true" then
		return true
	end
	if v == "false" then
		return false
	end
	local num = tonumber(v)
	if num then
		return num
	end
	return v
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

-- Parse the output of `geom <class> list`.
-- Tested on class `disk` and `part`.
local function geom_parse_list(geom_output)
	local geoms = {}

	local current_item = nil
	local current_section = nil
	local geom = nil

	local function new_geom()
		geom = {
			consumers = {},
			providers = {},
		}

		table.insert(geoms, geom)
		current_item = geom
		current_section = geom
		return geom
	end

	for _, line in ipairs(geom_output) do
		line = trim(line)
		if line == "" then
			goto continue
		end

		local name = line:match("^Geom name:%s+(%S+)$")
		if name then
			local geom = new_geom()
			geom["geom name"] = name
			goto continue
		end

		if line:lower():match("^providers:$") then
			current_section = geom.providers
			goto continue
		elseif line:lower():match("^consumers:$") then
			current_section = geom.consumers
			goto continue
		end

		local index, name = line:match("^(%d+)%.%s+Name:%s+(%S+)$")
		if index then
			current_item = {
				name = name,
			}
			current_section[tonumber(index)] = current_item
			goto continue
		end

		local k, v = line:match("^%s*([^:]+):%s+(.+)$")
		if k then
			current_item[k:lower()] = geom_parse_value(v)
		end

		::continue::
	end

	return geoms
end

local function print_item(
	format,
	level,
	final,
	name,
	major,
	minor,
	size,
	type,
	mountpoints
)
	local prefix = ""
	for _ = 1, level - 1 do
		prefix = prefix .. "  "
	end
	if level > 0 then
		if final then
			prefix = prefix .. "└─"
		else
			prefix = prefix .. "├─"
		end
	end

	print(
		string.format(format, prefix .. name, major, minor, size, type, mountpoints)
	)
end

local function parse_mount(mount_output)
	local mounts = {}

	for _, line in ipairs(mount_output) do
		line = trim(line)
		if line == "" then
			goto continue
		end

		local device, mountpoint = line:match("^(.-) on (.-) %(")
		if device and mountpoint then
			if not mounts[device] then
				mounts[device] = {}
			end
			table.insert(mounts[device], mountpoint)
		end

		::continue::
	end

	return mounts
end

local function format_device_num(number)
	return tostring(number):gsub("%.0$", "")
end

local function print_rest_of_mounts(format, mounts)
	local first = true
	for _, mount in ipairs(mounts) do
		if first then
			first = false
			goto continue
		end

		print_item(format:gsub(":", " "), 0, false, "", "", "", "", "", mount)

		::continue::
	end
end

-- Convert a size in bytes to a human‑readable string, dropping `.0`.
local function humanize_size(bytes)
	local units = { "B", "K", "M", "G", "T", "P", "E" }
	local i = 1

	while bytes >= 1024 and i < #units do
		bytes = bytes / 1024
		i = i + 1
	end

	local s = string.format("%.1f", bytes)
	s = s:gsub("(%..-)0+$", "%1")
	s = s:gsub("%.$", "")
	return s .. units[i]
end

local function parse_mediasize(mediasize)
	return tonumber(mediasize:match("^(%d+)"))
end

local function print_tree()
	local geom_list = run_cmd("geom part list")
	local geoms = geom_parse_list(geom_list)

	local mount_list = run_cmd("mount")
	local mounts = parse_mount(mount_list)

	local function dev_mounts(dev)
		return mounts[dev] or mounts["/dev/" .. dev]
	end

	local longest = 0
	for _, geom in ipairs(geoms) do
		if #geom["geom name"] > longest then
			longest = #geom["geom name"]
		end

		for _, provider in ipairs(geom.providers) do
			if #provider.name > longest then
				longest = #provider.name
			end
		end
	end
	longest = longest + 2
	local format = "%-" .. longest .. "s %3s:%-3s %6s %4s %s"

	print_item(format, 0, nil, "NAME", "MAJ", "MIN", "SIZE", "TYPE", "MOUNTPOINTS")

	for _, geom in ipairs(geoms) do
		local geom_name = geom["geom name"]
		local major, minor = get_major_minor(geom_name)

		local geom_size = 0
		for _, provider in ipairs(geom.providers) do
			geom_size = geom_size + parse_mediasize(provider.mediasize)
		end

		local geom_mounts = dev_mounts(geom_name) or {}
		print_item(
			format,
			0,
			nil,
			geom_name,
			format_device_num(major),
			format_device_num(minor),
			humanize_size(geom_size),
			"disk",
			geom_mounts[1] or ""
		)
		print_rest_of_mounts(format, geom_mounts)

		for i, provider in ipairs(geom.providers) do
			local name = provider["name"]
			local major, minor = get_major_minor(name)

			local provider_mounts = dev_mounts(name) or {}
			print_item(
				format,
				1,
				i == #geom.providers,
				name,
				format_device_num(major),
				format_device_num(minor),
				humanize_size(parse_mediasize(provider.mediasize)),
				"part",
				provider_mounts[1] or ""
			)
			print_rest_of_mounts(format, provider_mounts)
		end
	end
end

local function main()
	if #arg == 1 then
		if arg[1] == "-h" or arg[1] == "--help" then
			local name = arg[0]:match("([^/]+)$")
			print("usage: " .. name .. " [-h] [-V]")
			os.exit(0)
		elseif arg[1] == "-V" or arg[1] == "--version" then
			print(VERSION)
			os.exit(0)
		else
			print("unknown argument: " .. arg[1])
			os.exit(2)
		end
	end
	if #arg >= 2 then
		print("too many arguments")
		os.exit(2)
	end

	print_tree()
end

main()
