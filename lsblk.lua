#! /usr/libexec/flua
-- List information about block devices.
--
-- https://github.com/dbohdan/lsblk.lua
--
-- Copyright (c) 2025 D. Bohdan
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.

local lfs = require("lfs")

-----------------
--- Constants ---
-----------------

local MARKER_NONE = 0
local MARKER_MIDDLE = 1
local MARKER_LAST = 2

local TYPE_DISK = "disk"
local TYPE_PART = "part"

local VERSION = "0.3.0"

-------------------------
--- Utility functions ---
-------------------------

-- Print an error message to standard error and exit.
local function fail(exit_code, format_string, ...)
	io.stderr:write("lsblk: " .. format_string:format(...) .. "\n")
	os.exit(exit_code)
end

-- Execute a shell command and return its output as an array of lines.
local function run_cmd(cmd)
	local f = io.popen(cmd .. " 2>/dev/null", "r")
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	local result, _, status = f:close()
	if result == nil then
		fail(1, "command %q failed with status %d", cmd, status)
	end

	return lines
end

-- Get major/minor device numbers for a device name.
local function get_major_minor(dev)
	if dev == nil then
		return "-", "-"
	end

	local attr = lfs.attributes("/dev/" .. dev)
	if attr ~= nil then
		local major = math.floor(attr.rdev // 2 ^ 8)
		local minor = attr.rdev % 2 ^ 8
		return major, minor
	end

	return "-", "-"
end

-- Trim leading and trailing whitespace from a string.
local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

-- Format a device number, removing trailing `.0`.
local function format_device_num(number)
	return tostring(number):gsub("%.0$", "")
end

-- Convert a size in bytes to a human-readable string.
local function humanize_size(bytes)
	local units = { "B", "K", "M", "G", "T", "P", "E" }
	local i = 1

	while bytes >= 1024 and i < #units do
		bytes = bytes / 1024
		i = i + 1
	end

	local s = ("%.1f"):format(bytes)
	s = s:gsub("(%..-)0+$", "%1")
	s = s:gsub("%.$", "")
	return s .. units[i]
end

---------------
--- Parsing ---
---------------

-- Parse a value string from geom output (boolean, number, or string).
local function geom_parse_value(v)
	if v == "true" then
		return true
	end
	if v == "false" then
		return false
	end
	local num = tonumber(v)
	if num ~= nil then
		return num
	end
	return v
end

-- Parse the output of `geom <class> list`.
-- Tested on class `disk` and `part`.
local function geom_parse_list(geom_output)
	local geoms = {}

	local current_item
	local current_section
	local geom

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

		local geom_name = line:match("^Geom name:%s+(%S+)$")
		if geom_name ~= nil then
			new_geom()
			geom["geom name"] = geom_name
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
		if index ~= nil then
			current_item = {
				name = name,
			}
			current_section[tonumber(index)] = current_item
			goto continue
		end

		local k, v = line:match("^%s*([^:]+):%s+(.+)$")
		if k ~= nil then
			current_item[k:lower()] = geom_parse_value(v)
		end

		::continue::
	end

	return geoms
end

-- Parse the output of the `mount` command.
local function parse_mount(mount_output)
	local mounts = {}

	for _, line in ipairs(mount_output) do
		line = trim(line)
		if line == "" then
			goto continue
		end

		local device, mountpoint = line:match("^(.-) on (.-) %(")
		if device ~= nil and mountpoint ~= nil then
			if mounts[device] == nil then
				mounts[device] = {}
			end
			table.insert(mounts[device], mountpoint)
		end

		::continue::
	end

	return mounts
end

-- Parse lines of text into tables of whitespace-separated fields, awk-style.
local function parse_fields(lines)
	local parsed_lines = {}

	for _, line in ipairs(lines) do
		local fields = {}

		for field in line:gmatch("%S+") do
			table.insert(fields, field)
		end

		table.insert(parsed_lines, fields)
	end

	return parsed_lines
end

-- Extract the bytes value from a geom mediasize string.
local function parse_mediasize(mediasize)
	return tonumber(mediasize:match("^(%d+)"))
end

---------------------------
--- Data transformation ---
---------------------------

-- Take convert the result of `geom_parse_list` to our custom device format.
-- Add information from the system
-- (major and minor device number, mountpoints).
local function geom_device_info(geoms, dev_mounts)
	local devices = {}

	for _, geom in ipairs(geoms) do
		local geom_name = geom["geom name"]
		local geom_major, geom_minor = get_major_minor(geom_name)
		local geom_mounts = dev_mounts(geom_name) or {}

		local geom_size = 0
		for _, provider in ipairs(geom.providers) do
			geom_size = geom_size + parse_mediasize(provider.mediasize)
		end

		table.insert(devices, {
			name = geom_name,
			major = geom_major,
			minor = geom_minor,
			size = geom_size,
			type = TYPE_DISK,
			fstype = "-",
			mountpoints = geom_mounts,
		})

		for i, provider in ipairs(geom.providers) do
			local last = i == #geom.providers
			local name = provider["name"]
			local major, minor = get_major_minor(name)
			local mounts = dev_mounts(name) or {}

			table.insert(devices, {
				last = last,
				name = name,
				major = major,
				minor = minor,
				size = parse_mediasize(provider.mediasize),
				type = TYPE_PART,
				fstype = provider.type,
				mountpoints = mounts,
			})
		end
	end

	return devices
end

-- Convert the output of zpool(8) and zfs(8) parsed with `parse_fields`
-- to our custom device information format.
-- Unlike `geom_device_info`, this is a pure function.
local function zfs_device_info(pools, datasets)
	local dataset_index = {}
	local devices = {}

	for _, dataset in ipairs(datasets) do
		local pool = dataset[1]:match("^[^/]+")

		if dataset_index[pool] == nil then
			dataset_index[pool] = { dataset }
		else
			table.insert(dataset_index[pool], dataset)
		end
	end

	for _, pool in ipairs(pools) do
		table.insert(devices, {
			name = pool[1],
			major = "-",
			minor = "-",
			size = tonumber(pool[2]),
			type = TYPE_DISK,
			fstype = "-",
			mountpoints = "-",
		})

		local pool_datasets = dataset_index[pool[1]]
		for i, dataset in ipairs(pool_datasets) do
			table.insert(devices, {
				last = i == #pool_datasets,
				name = dataset[1],
				major = "-",
				minor = "-",
				size = tonumber(dataset[2]),
				type = TYPE_PART,
				fstype = "zfs",
				mountpoints = { dataset[3] },
			})
		end
	end

	return devices
end

-- Calculate the maximum display width needed for certain fields.
local function max_field_lengths(devices, humanize)
	local max_lens = { fstype = 1, name = 1, size = 6 }

	for _, device in ipairs(devices) do
		-- Use byte length for `string.format`.
		local len_fstype = #device.fstype
		if len_fstype > max_lens.fstype then
			max_lens.fstype = len_fstype
		end

		local size_text = humanize and humanize_size(device.size)
			or tostring(device.size)
		local len_size = #size_text
		if len_size > max_lens.size then
			max_lens.size = len_size
		end

		local len_name = #device.name
		if len_name > max_lens.name then
			max_lens.name = len_name
		end
	end

	return max_lens
end

--------------
--- Output ---
--------------

-- Print a single formatted row (device or header).
local function print_item(
	max_lens,
	marker,
	name,
	major,
	minor,
	size,
	type,
	fstype,
	mountpoints
)
	local function format_str(prefix)
		-- `string.format` counts bytes, not Unicode characters.
		local name_padding = max_lens.name + math.max(2, #prefix)
		return "%-"
			.. name_padding
			.. "s %3s%1s%-3s %"
			.. max_lens.size
			.. "s %4s %"
			.. max_lens.fstype
			.. "s %s"
	end

	local prefix = ""
	local prefix_rest = ""
	if type == TYPE_PART then
		if marker == MARKER_MIDDLE then
			prefix = "├─"
			prefix_rest = "│ "
		elseif marker == MARKER_LAST then
			prefix = "└─"
			prefix_rest = "  "
		end
	end

	local formatted = format_str(prefix):format(
		prefix .. name,
		major,
		":",
		minor,
		size,
		type,
		fstype,
		mountpoints[1] or ""
	)
	print(formatted)

	-- Print additional mountpoints on subsequent lines.
	for i = 2, #mountpoints do
		formatted = format_str(prefix_rest):format(
			prefix_rest,
			"",
			"",
			"",
			" ",
			"",
			"",
			"",
			mountpoints[i]
		)
		print(formatted)
	end
end

-- Fetch data, process it, and print the device tree.
local function print_tree(humanize, enable_geoms, enable_zfs)
	local devices = {}

	-- Gather GEOM device info if enabled.
	if enable_geoms then
		local geom_list = run_cmd("geom part list")
		local geoms = geom_parse_list(geom_list)

		local mount_list = run_cmd("mount")
		local mounts = parse_mount(mount_list)

		local function dev_mounts(dev)
			return mounts[dev] or mounts["/dev/" .. dev]
		end

		local geom_devices = geom_device_info(geoms, dev_mounts)
		table.move(geom_devices, 1, #geom_devices, #devices + 1, devices)
	end

	-- Gather ZFS device info if enabled.
	if enable_zfs then
		local zpool_list = run_cmd("zpool list -H -o name,size -p")
		local zfs_pools = parse_fields(zpool_list)

		local zfs_list = run_cmd("zfs list -H -o name,used,mountpoint -p")
		local zfs_datasets = parse_fields(zfs_list)

		local zfs_devices = zfs_device_info(zfs_pools, zfs_datasets)
		table.move(zfs_devices, 1, #zfs_devices, #devices + 1, devices)
	end

	local max_lens = max_field_lengths(devices, humanize)

	print_item(
		max_lens,
		MARKER_NONE,
		"NAME",
		"MAJ",
		"MIN",
		"SIZE",
		"TYPE",
		"FSTYPE",
		{ "MOUNTPOINTS" }
	)

	-- Print each device row.
	for _, device in ipairs(devices) do
		print_item(
			max_lens,
			device.last and MARKER_LAST or MARKER_MIDDLE,
			device.name,
			format_device_num(device.major),
			format_device_num(device.minor),
			humanize and humanize_size(device.size) or device.size,
			device.type,
			device.fstype,
			device.mountpoints
		)
	end
end

-- Print the help message.
local function print_help()
	local name = arg[0]:match("([^/]+)$")
	print("usage: " .. name .. " [-h] [-V] [-b] [-g] [-z]")
	print([[

List information about block devices.

options:
  -h, --help
          Print this help message and exit

  -V, --version
          Print version number and exit

  -b, --bytes
          Print sizes in bytes instead of human-readable format

  -g, --geom
          Only output information about geoms of class "disk" and "part"

  -z, --zfs
          Only output information about ZFS pools and datasets]])
end

------------
--- Main ---
------------

local function main()
	local humanize = true
	local geom = true
	local zfs = true

	-- Parse command-line arguments.
	for _, argument in ipairs(arg) do
		if argument == "-b" or argument == "--bytes" then
			humanize = false
		elseif argument == "-g" or argument == "--geom" then
			geom = true
			zfs = false
		elseif argument == "-h" or argument == "--help" then
			print_help()
			os.exit(0)
		elseif argument == "-V" or argument == "--version" then
			print(VERSION)
			os.exit(0)
		elseif argument == "-z" or argument == "--zfs" then
			geom = false
			zfs = true
		elseif argument:match("^-") then
			-- Reject unknown options.
			fail(2, "invalid option %q", argument)
		else
			-- Reject any positional argument.
			fail(2, "too many arguments")
		end
	end

	print_tree(humanize, geom, zfs)
end

main()
