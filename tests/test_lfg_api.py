from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute("""
OldKraken = {}
printed = {}
searchCalls, createCalls, updateCalls = 0, 0, 0

function print(message)
    printed[#printed + 1] = message
end

C_LFGList = {
    GetAvailableCategories = function() return {9, 3, 6} end,
    GetAvailableActivities = function() return {70, 10, 40} end,
    GetActivityInfoTable = function() end,
    Search = function() searchCalls = searchCalls + 1 end,
    GetSearchResults = function() end,
    GetSearchResultInfo = function() end,
    GetSearchResultPlayerInfo = function() end,
    CreateListing = function() createCalls = createCalls + 1 end,
    UpdateListing = function() updateCalls = updateCalls + 1 end,
}
C_LFGInfo = {}
LFGListFrame = nil
C_ChatInfo = {
    AreOutgoingAddonChatMessagesRestricted = function() return true end,
}
""")

source = (root / "GroupFinderAPI.lua").read_text(encoding="utf-8")
lua.execute(source)

lua.execute("""
local api = OldKraken.GroupFinderAPI
local status = api:GetStatus()

assert(status.namespace == "table")
assert(status.infoNamespace == "table")
assert(status.frame == "nil")
assert(status.methods.Search == "function")
assert(status.methods.GetSearchResults == "function")
assert(status.methods.GetSearchResultInfo == "function")
assert(status.methods.RequestToJoin == "nil")
assert(#status.categories == 3)
assert(status.categories[1] == 3 and status.categories[3] == 9)
assert(#status.activities == 3)
assert(status.activities[1] == 10 and status.activities[3] == 70)
assert(status.addonMessagesRestricted == true)

assert(api:HandleCommand("group api"))
assert(not api:HandleCommand("group"))
assert(#printed > 0)

-- The diagnostic must never execute protected or state-changing operations.
assert(searchCalls == 0)
assert(createCalls == 0)
assert(updateCalls == 0)

-- Missing namespace/methods are reported without throwing.
C_LFGList = nil
local missing = api:GetStatus()
assert(missing.namespace == "nil")
assert(missing.categories == nil)
assert(missing.activities == nil)
""")

print("Native Group Finder API probe checks passed")
