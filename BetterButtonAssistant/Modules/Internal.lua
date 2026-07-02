-- Shared mutable state for companion modules (avoids polluting _G).
local _, NS = ...

NS.Internal = {
	interruptFrame = nil,
	interruptSpellID = nil,
	interruptCastMode = {},
	counterText = nil,
	rangeReadout = nil,
	trinketFrames = nil,
	queueFrames = nil,
	defensiveFrames = nil,
	lastCounterText = nil,
	lastRangeText = nil,
	lastRangeColor = nil,
	lastCompanionLayoutSig = nil,
}
