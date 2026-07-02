local _, NS = ...

-- ---------------------------------------------------------------------
-- Range module — approximate distance band to the target.
--
-- Prefers LibRangeCheck-3.0/2.0 when ANY loaded addon provides it (it's embedded in
-- many popular addons): the lib mixes interaction-, item-, and class-spell-based
-- checkers for much finer, self-maintaining brackets and returns a min/max band.
--
-- When the lib isn't present we fall back to our own implementation: a yard ->
-- item-list table where each item's C_Item.IsItemInRange flips true at <= that
-- yardage. Binary-searching the sorted list finds the smallest range that returns
-- true (the upper bound); the bracket just below it is the lower bound, giving a
-- min/max band independent of the player's class/spells.
--
-- Optimization notes (per the project rules):
--   * Item data isn't always cached at login, so we pick the first ready item per
--     range and retry the rest on a C_Timer.After loop (no OnUpdate polling) with
--     an attempt cap, rebuilding the sorted list as more items resolve.
--   * GetTargetRange is the only hot-path entry; it does a log2(n) binary search
--     over a tiny presorted array and bails out on secret/!attackable up front.
-- Secret-value notes: IsItemInRange can be secret in combat; a secret result
--   can't be compared, so we treat it as "no data" and stop (returns nil).
-- ---------------------------------------------------------------------

local Range = {}
NS.Range = Range

local C_Item_GetItemInfo = NS.C_Item_GetItemInfo
local C_Item_IsItemInRange = NS.C_Item_IsItemInRange
local C_Item_RequestLoadItemDataByID = NS.C_Item_RequestLoadItemDataByID
local C_Timer_After = NS.C_Timer_After
local UnitExists = NS.UnitExists
local UnitIsDead = NS.UnitIsDead
local UnitCanAttack = NS.UnitCanAttack
local issecretvalue = NS.issecretvalue
local ipairs = NS.ipairs
local pairs = NS.pairs
local math_floor = NS.math_floor
local LibStub = NS.LibStub

-- Resolve LibRangeCheck lazily and cache only the hit: the lib may be embedded in an
-- addon that loads after us, so we keep re-querying LibStub (a cheap table lookup)
-- until it appears, then stop. nil result => use our own item-table fallback.
local libRangeCheck
local function GetLibRangeCheck()
	if libRangeCheck then
		return libRangeCheck
	end
	if LibStub then
		libRangeCheck = LibStub("LibRangeCheck-3.0", true) or LibStub("LibRangeCheck-2.0", true)
	end
	return libRangeCheck
end

-- yards -> candidate item IDs (multiple per range = fallbacks if one isn't cached).
-- These are public, long-standing "harm" item ranges; the same well-known IDs any
-- range checker uses. Curated to the brackets that matter for melee (5) through
-- ranged/caster play (30-40) and a few long ones for utility.
Range.HARM_ITEMS = {
	[5] = { 8149, 17117, 22432 },
	[8] = { 34368, 33278 },
	[10] = { 32321, 17626, 10699 },
	[15] = { 33069, 46722, 32907 },
	[20] = { 1191, 4388, 10645 },
	[25] = { 24268, 31463, 32408 },
	[30] = { 835, 7734, 34191 },
	[35] = { 24269, 24501, 18904 },
	[40] = { 4945, 28767, 33581 },
	[45] = { 23836, 32698, 28369 },
	[50] = { 116139, 134836, 147017 },
	[60] = { 32825, 37877 },
	[70] = { 41265 },
	[80] = { 35278, 42769, 35506 },
	[100] = { 33119, 44212, 41058 },
}

-- { {range=, itemID=}, ... } ascending by range; rebuilt as items finish caching.
Range._sorted = nil
Range._totalRanges = nil
Range._initDone = false

local RETRY_INTERVAL = 1.0
local MAX_RETRIES = 30
local retryScheduled = false
local retryAttempts = 0

local function CountRanges()
	if Range._totalRanges then
		return Range._totalRanges
	end
	local n = 0
	for _ in pairs(Range.HARM_ITEMS) do
		n = n + 1
	end
	Range._totalRanges = n
	return n
end

-- Builds the sorted (range -> ready itemID) list from whatever item data is cached
-- right now. Returns how many ranges currently have a usable checker.
local function Rebuild()
	local list = {}
	local cached = 0

	for range, items in pairs(Range.HARM_ITEMS) do
		local picked
		for _, itemID in ipairs(items) do
			if C_Item_GetItemInfo and C_Item_GetItemInfo(itemID) then
				picked = itemID
				break
			end
		end
		if picked then
			cached = cached + 1
			list[#list + 1] = { range = range, itemID = picked }
		elseif C_Item_RequestLoadItemDataByID then
			-- Nudge the client to load these so a later rebuild can use them.
			for _, itemID in ipairs(items) do
				C_Item_RequestLoadItemDataByID(itemID)
			end
		end
	end

	table.sort(list, function(a, b)
		return a.range < b.range
	end)
	Range._sorted = list
	return cached
end

local ScheduleRetry -- forward declaration

local function RetryTick()
	retryScheduled = false
	retryAttempts = retryAttempts + 1

	local cached = Rebuild()
	if cached >= CountRanges() then
		return -- fully cached; stop retrying
	end
	if retryAttempts < MAX_RETRIES then
		ScheduleRetry()
	end
end

function ScheduleRetry()
	if retryScheduled or not C_Timer_After then
		return
	end
	retryScheduled = true
	C_Timer_After(RETRY_INTERVAL, RetryTick)
end

-- Lazily build the table on first use, kicking off the retry loop if needed.
function Range.Init()
	if Range._initDone then
		return
	end
	Range._initDone = true
	local cached = Rebuild()
	if cached < CountRanges() then
		retryAttempts = 0
		ScheduleRetry()
	end
end

-- Item-table fallback (used when LibRangeCheck isn't available). Returns a min/max
-- yard band to `unit`: the binary search finds the smallest bracket whose item
-- reports "in range" (the upper bound) and the bracket just below it is the lower
-- bound (range checks are monotonic, so everything below is out of range). Returns
-- nil when we can't measure (no data, secret result, or not a live unit), or
-- (longest, nil) when the unit is beyond our longest checker.
function Range.GetRange(unit)
	if not C_Item_IsItemInRange or not unit or not UnitExists(unit) then
		return nil
	end

	if not Range._sorted then
		Range.Init()
	end
	local list = Range._sorted
	if not list or #list == 0 then
		return nil
	end

	local lo, hi, bestIdx = 1, #list, nil
	while lo <= hi do
		local mid = math_floor((lo + hi) / 2)
		local inRange = C_Item_IsItemInRange(list[mid].itemID, unit)
		-- A secret result can't be compared; abandon the estimate rather than guess.
		if issecretvalue and issecretvalue(inRange) then
			return nil
		end
		if inRange then
			bestIdx = mid
			hi = mid - 1
		else
			lo = mid + 1
		end
	end

	if not bestIdx then
		-- Beyond the longest bracket we can check.
		return list[#list].range, nil
	end
	local maxR = list[bestIdx].range
	local minR = bestIdx > 1 and list[bestIdx - 1].range or 0
	return minR, maxR
end

-- Min/max yard band to the current target for the on-screen readout, or nil when
-- there's no live attackable target to measure. Prefers LibRangeCheck (finer, self-
-- maintaining) and falls back to our item table. maxRange may be nil ("beyond X").
function Range.GetTargetRange()
	if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
		return nil
	end

	local lib = GetLibRangeCheck()
	if lib then
		local fn = lib.GetRange or lib.getRange
		if fn then
			-- Third-party call: pcall-guarded so a lib error or signature change can
			-- never break our tick. checkVisible=true stops it guessing on unseen units.
			local ok, minR, maxR = NS.pcall(fn, lib, "target", true)
			if ok and minR then
				return minR, maxR
			end
		end
	end

	return Range.GetRange("target")
end
