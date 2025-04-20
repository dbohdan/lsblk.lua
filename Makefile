FILES := lsblk.lua

.PHONY: check
check: format lint

.PHONY: format
format:
	stylua $(FILES)

.PHONY: lint
lint:
	luacheck --std lua53 $(FILES)
	luacheck --std lua54 $(FILES)
