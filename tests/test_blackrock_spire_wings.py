from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LOCALE = (ROOT / 'Locale.lua').read_text(encoding='utf-8')
CATALOG = (ROOT / 'ActivityCatalog.lua').read_text(encoding='utf-8')


def run_catalog(lang):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._lang = lang
    lua.execute('''
        OldKraken = { name = 'OldKraken' }
    ''')
    lua.execute(LOCALE)
    lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
    lua.execute(CATALOG)
    lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
    return lua


for lang, expected_lbrs, expected_ubrs in (
    ('ukUA', 'Нижній пік Чорної гори (LBRS)', 'Верхній пік Чорної гори (UBRS)'),
    ('enUS', 'Lower Blackrock Spire (LBRS)', 'Upper Blackrock Spire (UBRS)'),
):
    lua = run_catalog(lang)
    lua.globals()._exp_lbrs = expected_lbrs
    lua.globals()._exp_ubrs = expected_ubrs
    lua.execute('''
        local cat = OldKraken.ActivityCatalog
        assert(cat.IsValidActivity('dungeon', 'lbrs'))
        assert(cat.IsValidActivity('dungeon', 'ubrs'))
        local found = {}
        for _, entry in ipairs(cat.dungeon) do
            if entry.value == 'lbrs' or entry.value == 'ubrs' then
                found[entry.value] = entry
            end
        end
        assert(found.lbrs and found.lbrs.label == _exp_lbrs and found.lbrs.min == 55 and found.lbrs.max == 60)
        assert(found.ubrs and found.ubrs.label == _exp_ubrs and found.ubrs.min == 58 and found.ubrs.max == 60)
        assert(cat.IsCanonicalTitle('lbrs', _exp_lbrs))
        assert(cat.IsCanonicalTitle('ubrs', _exp_ubrs))
        assert(not cat.IsCanonicalTitle('lbrs', 'Пік Чорної гори (BRS)'))
        assert(not cat.IsCanonicalTitle('lbrs', 'Blackrock Spire (BRS)'))

        local texL, texU = {}, {}
        function texL:SetTexture(v) self.tex = v end
        function texL:SetTexCoord() end
        function texU:SetTexture(v) self.tex = v end
        function texU:SetTexCoord() end
        cat.SetArtwork(texL, 'lbrs')
        cat.SetArtwork(texU, 'ubrs')
        assert(texL.tex == 131825 and texU.tex == 131825)
    ''')

# Verify GroupFinder and GuildEvents accept both ubrs and lbrs (while preserving legacy BRS title)
lua_full = LuaRuntime(unpack_returned_tuples=True)
lua_full.execute('''
    now = 1700000000
    OldKraken = {
        name = 'OldKraken',
        DB = { settings = { language = 'ukUA' }, events = { guildCalendarV1 = {} } },
        Communication = { RegisterHandler = function() end, SendProtocol = function() return true end, queue = {} },
        UIStyle = { Colors = { brandGold = {0.88, 0.69, 0.32, 1}, mutedText = {0.6, 0.6, 0.6} }, Font = function() end },
    }
    function OldKraken:On() end
    function OldKraken:Fire() end
    function GetServerTime() return now end
    function GetTime() return 100 end
    function UnitName() return 'Leader', 'Tester' end
    function GetGuildInfo() return 'Guild' end
    function GetRealmName() return 'Realm' end
    function UnitClass() return 'Warrior', 'WARRIOR' end
    function date() return '23.11 20:00' end
    StaticPopupDialogs = {}
    UIParent = {}
    createdFrames = {}
    function CreateFrame()
        local frame = {
            scripts = {},
            RegisterEvent = function() end,
            SetScript = function(self, name, fn) self.scripts[name] = fn end,
            HookScript = function() end,
            Hide = function() end,
            Show = function() end,
        }
        createdFrames[#createdFrames + 1] = frame
        return frame
    end
''')
lua_full.execute(LOCALE)
lua_full.execute('OldKraken.InitializeLocale(OldKraken.DB)')
lua_full.execute(CATALOG)
lua_full.execute((ROOT / 'GroupFinder.lua').read_text(encoding='utf-8'))
lua_full.execute((ROOT / 'GuildEvents.lua').read_text(encoding='utf-8'))
lua_full.execute('''
    for _, frame in ipairs(createdFrames) do
        if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, 'PLAYER_LOGIN') end
    end

    local gf = OldKraken.GroupFinder
    gf.active, gf.identity, gf.groups, gf.sequence = true, 'Leader Tester', {}, 0
    gf.requestVersions, gf.reopenFloors, gf.lastActivity = {}, {}, {}
    gf.send = function() return true end

    local okU, idU = gf:Create('Верхній пік Чорної гори (UBRS)', 'dungeon', '', 5, 58, 60, 'tank', 'ubrs')
    assert(okU == true and gf.groups['Leader Tester\\001' .. idU].dungeon == 'ubrs')

    local okL, idL = gf:Create('Нижній пік Чорної гори (LBRS)', 'dungeon', '', 5, 55, 60, 'tank', 'lbrs')
    assert(okL == true and gf.groups['Leader Tester\\001' .. idL].dungeon == 'lbrs')

    local okLegacy, idLegacy = gf:Create('Пік Чорної гори (BRS)', 'dungeon', '', 5, 57, 60, 'tank', 'lbrs')
    assert(okLegacy == true and gf.groups['Leader Tester\\001' .. idLegacy].title == 'Пік Чорної гори (BRS)')

    local ev = OldKraken.GuildEvents
    local evL = ev:Create('Нижній пік Чорної гори (LBRS)', 'desc', now + 3600, 'dungeon', 5, 'lbrs')
    local evU = ev:Create('Верхній пік Чорної гори (UBRS)', 'desc', now + 7200, 'dungeon', 5, 'ubrs')
    assert(evL == true and evU == true, 'GuildEvents must accept both lbrs and ubrs')

    local stored = OldKraken.DB.events.guildCalendarV1['Realm\\001Guild\\001Leader Tester']
    assert(stored and stored.owned, 'GuildEvents storage must be initialized')
    local seen = {}
    for _, item in pairs(stored.owned) do
        seen[item.activity] = item
    end
    assert(seen.lbrs and seen.lbrs.activity == 'lbrs', 'Saved event must have activity lbrs')
    assert(seen.ubrs and seen.ubrs.activity == 'ubrs', 'Saved event must have activity ubrs')
''')

print('Blackrock Spire wings checks passed')
