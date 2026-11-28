from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
    local createdFrames = {}
    UISpecialFrames = {}
    UIParent = {}
    inCombat = false
    timerCallbacks = {}
    C_Timer = {
        After = function(delay, fn)
            timerCallbacks[#timerCallbacks + 1] = { delay = delay, fn = fn }
        end,
    }
    function InCombatLockdown() return inCombat end
    function tinsert(t, v) table.insert(t, v) end
    local function makeWidget()
        local w = { shown = false, scripts = {}, children = {} }
        function w:SetSize(x, y) self.w, self.h = x, y end
        function w:SetPoint(...) self.point = {...} end
        function w:EnableMouse() end
        function w:SetMovable() end
        function w:RegisterForDrag() end
        function w:SetScript(ev, fn) self.scripts[ev] = fn end
        function w:RegisterEvent(ev) self.registered = self.registered or {}; self.registered[ev] = true end
        function w:Show() self.shown = true end
        function w:Hide()
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function w:IsShown() return self.shown end
        function w:SetText(t) self.text = t end
        function w:GetText() return self.text end
        function w:SetTextColor(...) end
        function w:SetJustifyH() end
        function w:SetJustifyV() end
        function w:SetWordWrap() end
        function w:SetTexture(p) self.texture = p end
        function w:CreateFontString()
            local fs = makeWidget()
            w.children[#w.children + 1] = fs
            return fs
        end
        function w:CreateTexture()
            local tex = makeWidget()
            w.children[#w.children + 1] = tex
            return tex
        end
        return w
    end
    function CreateFrame(_, name, parent)
        local f = makeWidget()
        if name then _G[name] = f end
        createdFrames[#createdFrames + 1] = f
        return f
    end
    shownPages = {}
    OldKraken = {
        version = '0.5.10-alpha.1',
        DB = { settings = { language = 'ukUA' } },
        UIStyle = {
            Colors = {
                brandGold = { 0.88, 0.69, 0.32 },
                mutedText = { 0.68, 0.74, 0.82 },
            },
            EmblemPath = function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenEmblem.tga' end,
            Window = function(f) f.windowStyled = true end,
            Panel = function() return nil end,
            PanelFrame = function(parent)
                local p = makeWidget()
                parent.children[#parent.children + 1] = p
                return p
            end,
            Font = function(fs, size, bold) fs.fontSize, fs.fontBold = size, bold end,
            Button = function(b, variant) b.variant = variant end,
        },
        UIHub = {
            ShowPage = function(_, key) shownPages[#shownPages + 1] = key end,
        },
    }
    _G.createdFrames = createdFrames
''')
lua.execute((ROOT / 'Locale.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'WhatsNew.lua').read_text(encoding='utf-8'))

lua.execute('''
    local wn = OldKraken.WhatsNew
    assert(wn ~= nil)
    assert(#wn:GetCards() == 6)

    -- 1. PLAYER_ENTERING_WORLD schedules C_Timer.After(1.5), combat defers it, PLAYER_REGEN_ENABLED opens once, late timer does not reopen
    local evFrame = _G.createdFrames[1]
    assert(evFrame.registered.PLAYER_ENTERING_WORLD == true)
    assert(evFrame.registered.PLAYER_REGEN_ENABLED == true)
    inCombat = true
    assert(wn:ShouldAutoShow() == false)
    evFrame.scripts.OnEvent(evFrame, 'PLAYER_ENTERING_WORLD')
    assert(#timerCallbacks == 1 and timerCallbacks[1].delay == 1.5, 'must schedule C_Timer.After(1.5) on PLAYER_ENTERING_WORLD')
    timerCallbacks[1].fn()
    assert(OldKrakenWhatsNewFrame == nil, 'timer callback during combat must not open frame')
    inCombat = false
    assert(wn:ShouldAutoShow() == true)

    -- 2. PLAYER_REGEN_ENABLED auto-shows once combat ends for unseen version; late timer callback does not reopen
    evFrame.scripts.OnEvent(evFrame, 'PLAYER_REGEN_ENABLED')
    assert(OldKrakenWhatsNewFrame ~= nil and OldKrakenWhatsNewFrame:IsShown())
    assert(OldKrakenWhatsNewFrame.windowStyled == true)
    OldKrakenWhatsNewFrame:Hide()
    evFrame.scripts.OnEvent(evFrame, 'PLAYER_ENTERING_WORLD')
    assert(#timerCallbacks == 1, 'must not schedule a second timer after sessionChecked')
    timerCallbacks[#timerCallbacks].fn()
    assert(not OldKrakenWhatsNewFrame:IsShown(), 'late timer callback after seen must not reopen')

    -- 3. Second auto-check in same session does nothing
    OldKrakenWhatsNewFrame:Hide()
    assert(OldKraken.DB.settings.whatsNewSeenVersion == '0.5.10-alpha.1')
    assert(wn:ShouldAutoShow() == false)
    assert(wn:CheckAutoShow() == false)

    -- 4. Force show (/okr new) still opens after version was marked seen
    assert(wn:Show(true) == true)
    assert(OldKrakenWhatsNewFrame:IsShown() == true)

    -- 5. Clicking 'Відкрити' buttons hides WhatsNew and opens target UIHub pages ('settings' and 'workshop')
    local openButtons = {}
    for _, f in ipairs(_G.createdFrames) do
        if f.text == 'Відкрити' then openButtons[#openButtons + 1] = f end
    end
    assert(#openButtons == 3 and openButtons[1].scripts.OnClick ~= nil and openButtons[2].scripts.OnClick ~= nil)
    openButtons[1].scripts.OnClick(openButtons[1])
    assert(not OldKrakenWhatsNewFrame:IsShown())
    assert(#shownPages == 1 and shownPages[1] == 'settings')
    assert(wn:Show(true) == true)
    openButtons[2].scripts.OnClick(openButtons[2])
    assert(not OldKrakenWhatsNewFrame:IsShown())
    assert(#shownPages == 2 and shownPages[2] == 'workshop')

    -- 6. Nil DB guard
    local savedDB = OldKraken.DB
    OldKraken.DB = nil
    assert(wn:ShouldAutoShow() == false)
    assert(wn:MarkSeen() == false)
    OldKraken.DB = savedDB

    -- 7. English translations exist for all card titles & descriptions
    OldKraken.DB.settings.language = 'enUS'
    OldKraken.InitializeLocale(OldKraken.DB)
    for _, card in ipairs(wn:GetCards()) do
        assert(OldKraken.Translate(card.title) ~= card.title, 'missing EN title: ' .. card.title)
        assert(OldKraken.Translate(card.desc) ~= card.desc, 'missing EN desc: ' .. card.desc)
    end
    assert(OldKraken.Translate('Що нового') == "What's New")
    assert(OldKraken.Translate('Зрозуміло') == 'Got it')
''')

print('WhatsNew checks passed')
