#! /usr/libexec/flua
-- Tests for lsblk.lua.
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

local lester = require("vendor/lester/lester")
local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

local function run(cmd)
	local f = io.popen(cmd .. " 2>&1", "r")
	local output = f:read("*a")
	local _, _, code = f:close()
	return code, output
end

describe("lsblk.lua", function()
	describe("CLI options", function()
		it("should show help", function()
			local code, output = run("./lsblk.lua -h")

			expect.equal(code, 0)
			expect.truthy(output:find("List information about block devices"))
			expect.truthy(output:find("--help"))
			expect.truthy(output:find("--version"))
		end)

		it("should show version", function()
			local code, output = run("./lsblk.lua -V")

			expect.equal(code, 0)
			expect.truthy(output:match("^%d+%.%d+%.%d+\n$"))
		end)

		it("should reject invalid options", function()
			local code, output = run("./lsblk.lua -Q")

			expect.equal(code, 2)
			expect.truthy(output:find("invalid option"))
		end)

		it("should reject positional arguments", function()
			local code, output = run("./lsblk.lua /dev/ada0")

			expect.equal(code, 2)
			expect.truthy(output:find("arguments"))
		end)
	end)

	describe("output formats", function()
		it("should show default output", function()
			local code, output = run("./lsblk.lua")

			expect.equal(code, 0)
			expect.truthy(
				output:find("NAME +MAJ:MIN +SIZE +TYPE +FSTYPE +MOUNTPOINTS\n")
			)
			expect.truthy(output:find("disk"))
			expect.truthy(output:find("part"))
		end)

		it("should show byte output", function()
			local code, output = run("./lsblk.lua -b")

			expect.equal(code, 0)
			expect.truthy(output:find(" %d+ disk"))
		end)

		it("should show geom output", function()
			local code, output = run("./lsblk.lua -g")

			expect.equal(code, 0)
			expect.truthy(output:find("NAME"))
			expect.truthy(output:find("disk"))
			-- Should filter out ZFS.
			expect.falsy(output:find("zfs"))
		end)

		it("should show ZFS output", function()
			local code, output = run("./lsblk.lua -z")

			-- Only compare the code and the header
			-- because the test machine may not have ZFS pools.
			expect.equal(code, 0)
			expect.truthy(output:find("NAME"))
		end)
	end)
end)

lester.report()
lester.exit()
