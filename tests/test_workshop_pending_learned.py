from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_workshop_orders import client, tick


def test_workshop_pending_learned():
    lua = client('PendingTester', embedded=True)
    tick(lua)
    lua.execute('''
        local infoPrints, errorPrints, sentProtocols = {}, {}, {}
        function OldKraken:Print(msg) infoPrints[#infoPrints + 1] = tostring(msg) end
        function OldKraken:PrintError(msg) errorPrints[#errorPrints + 1] = tostring(msg) end
        local origSend = OldKraken.Communication.SendProtocol
        function OldKraken.Communication:SendProtocol(kind, payload)
            sentProtocols[#sentProtocols + 1] = {kind = kind, payload = payload}
            return origSend(self, kind, payload)
        end

        local profMap = {
            [11001] = 185, -- Cooking (secondary)
            [11002] = 129, -- First Aid (secondary)
            [11003] = 186, -- Mining (gathering)
            [11004] = 182, -- Herbalism (gathering)
            [11005] = 393, -- Skinning (gathering)
            [11006] = 356, -- Fishing (secondary)
            [12001] = 171, -- Alchemy (primary crafting)
        }
        local delayedProf = {}
        GetProfessions = function() return 1, 2, 3, 4 end
        GetProfessionInfo = function(idx)
            local lines = {171, 185, 129, 186}
            return nil, nil, 300, 300, nil, nil, lines[idx]
        end
        C_TradeSkillUI = {
            GetProfessionInfoByRecipeID = function(id)
                local p = profMap[id] or delayedProf[id]
                return p and {parentProfessionID = p, professionID = p} or nil
            end,
            GetRecipeInfo = function(id)
                return {name = 'Recipe ' .. tostring(id), learned = false}
            end,
        }

        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local pname, psurname = UnitName('player')
        local identity = (psurname and psurname ~= '') and (pname .. ' ' .. psurname) or pname
        local pending = scope.pendingRecipes[identity]
        assert(type(pending) == 'table', 'pendingRecipes table missing')

        -- Pre-seed a stale secondary recipe in pendingLearned to verify cleanup.
        pending[11099] = true
        delayedProf[11099] = 185

        local eventFrame
        for _, f in ipairs(frames) do
            if f.scripts and f.scripts.OnEvent and f.events and f.events['NEW_RECIPE_LEARNED'] then
                eventFrame = f
                break
            end
        end
        assert(eventFrame, 'WorkshopRecipes event frame not found')

        -- 1. Secondary and gathering professions are ignored immediately on NEW_RECIPE_LEARNED.
        for _, id in ipairs({11001, 11002, 11003, 11004, 11005, 11006}) do
            eventFrame.scripts.OnEvent(eventFrame, 'NEW_RECIPE_LEARNED', id)
            assert(pending[id] == nil, 'ignored profession recipe must not enter pendingLearned: ' .. tostring(id))
        end

        -- 2. Primary crafting recipe enters pendingLearned; delayed secondary recipe is cleaned up on tick.
        eventFrame.scripts.OnEvent(eventFrame, 'NEW_RECIPE_LEARNED', 12001)
        assert(pending[12001] == true, 'primary crafting recipe must enter pendingLearned')

        _G.__testInfoPrints = infoPrints
        _G.__testErrorPrints = errorPrints
        _G.__testSentProtocols = sentProtocols
        _G.__testPending = pending
    ''')

    for _ in range(11):
        tick(lua)

    lua.execute('''
        assert(__testPending[11099] == nil, 'stale secondary recipe must be cleaned from pendingLearned')
        assert(#__testErrorPrints == 0, 'pending recipe notice must not use chatError, got: ' .. tostring(__testErrorPrints[1]))
        assert(#__testInfoPrints == 1, 'expected exactly 1 chatInfo notice for primary crafting recipe, got: ' .. tostring(#__testInfoPrints))
        assert(__testInfoPrints[1]:find('Алхімія', 1, true), 'notice must mention primary crafting profession: ' .. tostring(__testInfoPrints[1]))
        assert(not __testInfoPrints[1]:find('Кулінарія', 1, true) and not __testInfoPrints[1]:find('Перша допомога', 1, true) and not __testInfoPrints[1]:find('Гірництво', 1, true),
            'notice must not list secondary/gathering professions: ' .. tostring(__testInfoPrints[1]))
        for _, sent in ipairs(__testSentProtocols) do
            assert(sent.kind ~= 'WRLEARN', 'must not send WRLEARN for unlearned/ignored recipes')
        end
    ''')
    print('PASS: workshop pendingLearned filters secondary/gathering professions and uses chatInfo')


if __name__ == '__main__':
    test_workshop_pending_learned()
