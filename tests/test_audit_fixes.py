from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]


def run_task1_roster_uihub():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        local frames = {}
        local function makeFrame(kind, name, parent)
            local f = {
                _kind = kind, _name = name, _parent = parent,
                _scripts = {}, _shown = true, _text = '',
                _points = {}, _children = {},
            }
            if name then _G[name] = f end
            function f:SetSize() end
            function f:SetWidth() end
            function f:SetHeight() end
            function f:SetPoint(...) self._points[#self._points + 1] = {...} end
            function f:ClearAllPoints() self._points = {} end
            function f:SetAllPoints() end
            function f:SetMovable() end
            function f:EnableMouse() end
            function f:EnableMouseWheel() end
            function f:RegisterForDrag() end
            function f:SetClampedToScreen() end
            function f:SetFrameStrata() end
            function f:SetFrameLevel() end
            function f:SetScale() end
            function f:SetAlpha() end
            function f:GetFrameLevel() return 1 end
            function f:GetFrameStrata() return 'MEDIUM' end
            function f:SetBackdrop() end
            function f:SetBackdropColor() end
            function f:SetBackdropBorderColor() end
            function f:SetAutoFocus() end
            function f:SetTextInsets() end
            function f:SetJustifyH() end
            function f:SetNumeric() end
            function f:SetText(v) self._text = v or '' end
            function f:GetText() return self._text end
            function f:ClearFocus() end
            function f:SetNormalTexture() end
            function f:SetHighlightTexture() end
            function f:SetPushedTexture() end
            function f:SetDisabledTexture() end
            function f:SetNormalFontObject() end
            function f:SetHighlightFontObject() end
            function f:SetHitRectInsets() end
            function f:SetFontObject() end
            function f:RegisterForClicks() end
            function f:RegisterEvent() end
            function f:Enable() end
            function f:Disable() end
            function f:LockHighlight() end
            function f:UnlockHighlight() end
            function f:Show()
                self._shown = true
                if self._scripts.OnShow then self._scripts.OnShow(self) end
            end
            function f:Hide() self._shown = false end
            function f:SetShown(v) if v then self:Show() else self:Hide() end end
            function f:IsShown() return self._shown end
            function f:SetScript(ev, fn) self._scripts[ev] = fn end
            function f:GetScript(ev) return self._scripts[ev] end
            function f:HookScript(ev, fn)
                local prev = self._scripts[ev]
                self._scripts[ev] = function(...) if prev then prev(...) end fn(...) end
            end
            function f:SetScrollChild(child) self._scrollChild = child end
            function f:GetVerticalScroll() return 0 end
            function f:SetVerticalScroll() end
            function f:GetHeight() return 400 end
            function f:GetWidth() return 800 end
            function f:GetFontString()
                if not self._fs then self._fs = self:CreateFontString() end
                return self._fs
            end
            function f:CreateTexture()
                local t = {}
                function t:SetAllPoints() end
                function t:SetPoint() end
                function t:ClearAllPoints() end
                function t:SetSize() end
                function t:SetWidth() end
                function t:SetHeight() end
                function t:SetColorTexture() end
                function t:SetTexture() end
                function t:SetTexCoord() end
                function t:SetVertexColor() end
                function t:SetDesaturated() end
                function t:SetAlpha() end
                function t:Hide() end
                function t:Show() end
                function t:SetShown() end
                return t
            end
            function f:CreateFontString()
                local fs = { _text = '', _shown = true }
                function fs:SetPoint() end
                function fs:ClearAllPoints() end
                function fs:SetWidth() end
                function fs:SetHeight() end
                function fs:SetSize() end
                function fs:GetStringHeight() return 14 end
                function fs:SetJustifyH() end
                function fs:SetWordWrap() end
                function fs:SetJustifyV() end
                function fs:SetText(v) self._text = v or '' end
                function fs:GetText() return self._text end
                function fs:SetTextColor() end
                function fs:SetFontObject() end
                function fs:SetFont() end
                function fs:GetFont() return 'Font.ttf', 12, '' end
                function fs:SetShadowColor() end
                function fs:SetShadowOffset() end
                function fs:SetSpacing() end
                function fs:Show() self._shown = true end
                function fs:Hide() self._shown = false end
                function fs:SetShown(v) self._shown = v and true or false end
                function fs:IsShown() return self._shown end
                return fs
            end
            frames[#frames + 1] = f
            return f
        end

        createdFrames = {}
        UIParent = makeFrame('Frame', 'UIParent')
        UISpecialFrames = {}
        SlashCmdList = {}
        StaticPopupDialogs = {}
        CreateFrame = function(kind, name, parent)
            local f = makeFrame(kind, name, parent)
            createdFrames[#createdFrames + 1] = f
            return f
        end
        UIDropDownMenu_SetWidth = function() end
        UIDropDownMenu_JustifyText = function() end
        UIDropDownMenu_Initialize = function() end
        UIDropDownMenu_SetText = function() end
        UIDropDownMenu_CreateInfo = function() return {} end
        UIDropDownMenu_AddButton = function() end
        UnitName = function() return 'Tester', 'Realm' end
        GetRealmName = function() return 'Realm' end
        GetGuildInfo = function() return 'Old Kraken' end
        IsInGuild = function() return true end
        GetNumGuildMembers = function() return 0 end
        GetTime = function() return 100 end
        GetServerTime = function() return 1700000000 end
        date = os.date
        C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
        C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() return true end }

        hubPages = {}
        OldKraken = {
            name = 'OldKraken',
            version = '0.5.3-alpha.1',
            _listeners = {},
            UIHub = {
                RegisterPage = function(_, key, _, _, create) hubPages[key] = create end,
            },
            On = function(self, ev, fn)
                self._listeners[ev] = self._listeners[ev] or {}
                self._listeners[ev][#self._listeners[ev] + 1] = fn
            end,
            Fire = function(self, ev, ...)
                for _, fn in ipairs(self._listeners[ev] or {}) do fn(...) end
            end,
            DB = {
                settings = {
                    roster = { status = 'online', sort = 'name', ascending = true, class = '', search = 'Thrall' }
                },
                roster = { presence = {} },
            },
            Communication = { QueryPresence = function() end },
            UIStyle = {
                Colors = {
                    brandGold = {0.88, 0.69, 0.32, 1},
                    mutedText = {0.63, 0.67, 0.73},
                    text = {0.93, 0.94, 0.96},
                    zebra = {1, 1, 1, 0.035},
                    panelEdge = {0.20, 0.23, 0.29, 0.85},
                },
                Window = function() end,
                Button = function() end,
                Input = function() end,
                Dropdown = function() end,
                Panel = function() end,
                PanelFrame = function(parent) return makeFrame('Frame', nil, parent) end,
                Font = function() end,
                EmblemPath = function() return 'emblem' end,
            },
        }
        '''
    )
    lua.execute((root / 'UIHub.lua').read_text(encoding='utf-8'))
    lua.execute((root / 'GuildRoster.lua').read_text(encoding='utf-8'))
    lua.execute(
        '''
        OldKraken.UIHub:RegisterPage('group', 'Групи', '02', function(parent)
            return CreateFrame('Frame', 'DummyGroupPage', parent)
        end)
        OldKraken.UIHub:ShowPage('group')
        OldKraken.UIHub:ShowPage('roster')
        assert(OldKrakenRosterSearchBox ~= nil, 'Roster frame must be created')
        assert(OldKrakenRosterSearchBox:GetText() == 'Thrall', 'Saved search setting must be preserved')
        assert(OldKraken.DB.settings.roster.search == 'Thrall', 'DB setting must remain intact')

        -- Reopening must preserve settings
        OldKraken.UIHub:ShowPage('group')
        OldKraken.UIHub:ShowPage('roster')
        assert(OldKraken.DB.settings.roster.search == 'Thrall', 'Reopening must not overwrite saved settings')

        -- Missing DB.settings, missing roster, and partial roster must initialize in DB without overwriting
        OldKraken.DB.settings = nil
        assert(OldKraken.GuildRoster)
        OldKraken.GuildRoster:Show()
        assert(type(OldKraken.DB.settings) == 'table' and type(OldKraken.DB.settings.roster) == 'table', 'DB.settings.roster must be created')
        assert(OldKraken.DB.settings.roster.status == 'all', 'Default status must be populated')

        OldKraken.DB.settings = { roster = { search = 'Jaina' } }
        OldKraken.GuildRoster:Show()
        assert(OldKraken.DB.settings.roster.search == 'Jaina', 'Partial roster search must be preserved')
        assert(OldKraken.DB.settings.roster.sort == 'name', 'Missing partial roster fields must be filled')
        '''
    )


def run_task2_and_task6_group_finder():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        local now = 100
        local serverNow = 1700000000
        GetTime = function() return now end
        GetServerTime = function() return serverNow end
        IsInGuild = function() return true end
        GetGuildInfo = function() return 'Old Kraken' end
        GetRealmName = function() return 'Realm' end
        UnitName = function(u)
            if u == 'player' then return 'Alice', 'Sun' end
            return nil
        end
        UnitGetAvailableRoles = function() return true, true, true end
        UnitGroupRolesAssigned = function() return 'NONE' end
        GetNumGroupMembers = function() return 2 end
        IsInRaid = function() return true end
        gfFrames = {}
        CreateFrame = function()
            local f = { _scripts = {} }
            function f:RegisterEvent() end
            function f:SetScript(ev, fn) self._scripts[ev] = fn end
            gfFrames[#gfFrames + 1] = f
            return f
        end
        C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }

        local sent = {}
        hubPages = {}
        OldKraken = {
            name = 'OldKraken',
            version = '0.5.3-alpha.1',
            _listeners = {},
            UIHub = {
                RegisterPage = function(_, key, _, _, create) hubPages[key] = create end,
            },
            On = function(self, ev, fn)
                self._listeners[ev] = self._listeners[ev] or {}
                self._listeners[ev][#self._listeners[ev] + 1] = fn
            end,
            Fire = function(self, ev, ...)
                for _, fn in ipairs(self._listeners[ev] or {}) do fn(...) end
            end,
            DB = {
                groupFinder = {},
                settings = { groupFinderNotifications = true },
            },
            Communication = {
                handlers = {},
                queue = {},
                RegisterHandler = function(self, kind, fn) self.handlers[kind] = fn end,
                SendProtocol = function(self, kind, payload)
                    sent[#sent + 1] = { kind = kind, payload = payload }
                    return true
                end,
                ClearProtocolState = function() end,
            },
        }
        '''
    )
    lua.execute((root / 'GroupFinder.lua').read_text(encoding='utf-8'))
    lua.execute((root / 'GroupFinderIntegration.lua').read_text(encoding='utf-8'))
    lua.execute(
        '''
        local f = OldKraken.GroupFinder
        f:Initialize('Alice Sun', function(kind, payload) return OldKraken.Communication:SendProtocol(kind, payload) end)

        -- Create and delete 100 own groups
        local deletedPayloads = {}
        for i = 1, 100 do
            local ok, id = f:Create('Group ' .. i, 'other', 'Desc', 5, 1, 60, 'dps', '')
            assert(ok and id, 'Group creation ' .. i .. ' must succeed')
            local key = 'Alice Sun\001' .. id
            deletedPayloads[i] = f:EncodeGroup(f.groups[key])
            assert(f:Delete(id), 'Delete ' .. i .. ' must succeed')
        end

        -- 101st own group must still succeed
        local ok101, id101 = f:Create('Group 101', 'other', 'Desc', 5, 1, 60, 'dps', '')
        assert(ok101 and id101, '101st group creation must not be blocked by tombstones')

        -- Receiving another player's group must still succeed
        local remotePayload = f:EncodeGroup({
            id = '1700000000-999999-1', owner = 'Bob Moon', revision = 1, closed = false,
            title = 'Remote Group', category = 'other', description = 'Hi',
            maxSize = 5, minLevel = 1, maxLevel = 60, role = 'tank',
            members = {'Bob Moon'}, memberRoles = {['Bob Moon'] = 'tank'}, dungeon = '',
        })
        assert(f:ReceiveGroup('Bob Moon', remotePayload), 'Receiving remote group must succeed')

        -- Old ANNOUNCE for a deleted group must not resurrect it
        assert(not f:ReceiveGroup('Alice Sun', deletedPayloads[100]), 'Old ANNOUNCE must not resurrect deleted group')

        -- Prune after GROUP_TTL removes expired tombstones, while deletedGroups fence keeps blocking old ANNOUNCE
        local prevNow = GetTime()
        local t = prevNow + 3601
        GetTime = function() return t end
        local changed = f:Prune()
        assert(changed, 'Prune must report changed when expired tombstones are removed')
        local count = 0
        for _, g in pairs(f.groups) do
            if g.owner == 'Alice Sun' and g.closed and g.hidden then count = count + 1 end
        end
        assert(count == 0, 'Expired owner tombstones must be pruned')
        assert(not f:ReceiveGroup('Alice Sun', deletedPayloads[100]), 'Old ANNOUNCE must still be rejected after Prune')
        assert(not f:ReceiveGroup('Alice Sun', deletedPayloads[1]), 'Old ANNOUNCE beyond MAX_GROUPS must still be rejected')

        -- Stale/repeated CANCEL for deleted group is rejected, while new legitimate group with different ID is accepted
        local staleCancel = f:EncodeGroup({
            id = f._unpackFields(deletedPayloads[100], 215)[1],
            owner = 'Alice Sun', revision = 2, closed = true,
            title = 'Group 100', category = 'other', description = 'Desc',
            maxSize = 5, minLevel = 1, maxLevel = 60, role = 'dps',
            members = {'Alice Sun'}, memberRoles = {['Alice Sun'] = 'dps'}, dungeon = '',
        })
        assert(not f:ReceiveGroup('Alice Sun', staleCancel), 'Repeated/stale CANCEL must be rejected')
        local newRemote = f:EncodeGroup({
            id = '1700000000-888888-1', owner = 'Cara Sun', revision = 1, closed = false,
            title = 'Fresh Group', category = 'other', description = '',
            maxSize = 5, minLevel = 1, maxLevel = 60, role = 'healer',
            members = {'Cara Sun'}, memberRoles = {['Cara Sun'] = 'healer'}, dungeon = '',
        })
        assert(f:ReceiveGroup('Cara Sun', newRemote), 'Legitimate new group with different ID must be accepted')
        '''
    )

    # Test lastBump and roleCapabilities cleanup via integration + Finder
    lua.execute(
        '''
        local f = OldKraken.GroupFinder
        f:Initialize('Alice Sun', function(kind, payload) return OldKraken.Communication:SendProtocol(kind, payload) end)
        local now = 500
        GetTime = function() return now end
        local serverNow = 1700000500
        GetServerTime = function() return serverNow end

        -- Trigger PLAYER_LOGIN on integration frame
        OldKraken.DB = {
            groupFinder = {},
            settings = { groupFinderNotifications = true },
        }
        -- Test roleCapabilities pruning: add stale and active entries
        local ok, id = f:Create('Active Raid', 'other', '', 10, 60, 60, 'tank', '')
        assert(ok)
        local joinPayload = f._pack({'Alice Sun', id, 'healer', 'apply', '1700000500001', '010'})
        assert(f:ReceiveJoin('Carol Star', joinPayload))
        f.roleCapabilities['Stale Player'] = { tank = true, healer = false, dps = false }
        assert(f.roleCapabilities['Carol Star'] ~= nil, 'Active applicant must keep roleCapabilities')
        assert(f.roleCapabilities['Stale Player'] ~= nil)
        f:Prune()
        assert(f.roleCapabilities['Carol Star'] ~= nil, 'Active applicant roleCapabilities must survive Prune')
        assert(f.roleCapabilities['Stale Player'] == nil, 'Stale roleCapabilities must be pruned')

        -- Test GroupFinderIntegration reload + storage.lastBump pruning
        for _, gf in ipairs(gfFrames) do
            if gf._scripts.OnEvent then gf._scripts.OnEvent(gf, 'PLAYER_LOGIN') end
        end
        local okA, idA = f:Create('Group A', 'other', '', 5, 1, 60, 'tank', '')
        local okB, idB = f:Create('Group B', 'other', '', 5, 1, 60, 'dps', '')
        assert(okA and okB)
        f:Changed()
        local store = OldKraken.DB.groupFinder['Realm\001Old Kraken\001Alice']
        assert(store)
        store.lastBump = { [idA] = serverNow, [idB] = serverNow }
        assert(f:Cancel(idA))
        f:Changed()
        assert(store.lastBump[idA] == serverNow, 'Closed (non-hidden) group must keep lastBump for Reopen')
        assert(f:Delete(idB))
        f:Changed()
        assert(store.lastBump[idB] == nil, 'Deleted (hidden) group must prune lastBump')

        -- Simulate reload via PLAYER_LOGIN
        for _, gf in ipairs(gfFrames) do
            if gf._scripts.OnEvent then gf._scripts.OnEvent(gf, 'PLAYER_LOGIN') end
        end
        local restoredB = f.groups['Alice Sun\001' .. idB]
        assert(restoredB and restoredB.closed and restoredB.hidden, 'Deleted tombstone must remain closed and hidden after reload')
        -- Even after Prune + reload, old ANNOUNCE for deleted idB must be rejected
        local staleB = f:EncodeGroup({
            id = idB, owner = 'Alice Sun', revision = 1, closed = false,
            title = 'Group B', category = 'other', description = '',
            maxSize = 5, minLevel = 1, maxLevel = 60, role = 'dps',
            members = {'Alice Sun'}, memberRoles = {['Alice Sun'] = 'dps'}, dungeon = '',
        })
        now = now + 3601
        f:Prune()
        for _, gf in ipairs(gfFrames) do
            if gf._scripts.OnEvent then gf._scripts.OnEvent(gf, 'PLAYER_LOGIN') end
        end
        assert(not f:ReceiveGroup('Alice Sun', staleB), 'Old ANNOUNCE must remain rejected after Prune and reload')
        '''
    )


def run_task3_4_5_guild_events():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        local function makeFrame(kind, name, parent)
            local f = {
                _kind = kind, _name = name, _parent = parent,
                _scripts = {}, _shown = true, _text = '',
                _points = {}, borderEdges = {},
            }
            if name then _G[name] = f end
            function f:SetSize() end
            function f:SetWidth() end
            function f:SetHeight() end
            function f:SetPoint(...) self._points[#self._points + 1] = {...} end
            function f:ClearAllPoints() self._points = {} end
            function f:SetAllPoints() end
            function f:SetMovable() end
            function f:EnableMouse() end
            function f:EnableMouseWheel() end
            function f:RegisterForDrag() end
            function f:SetClampedToScreen() end
            function f:SetFrameStrata() end
            function f:SetFrameLevel() end
            function f:SetScale() end
            function f:SetAlpha() end
            function f:GetFrameLevel() return 1 end
            function f:GetFrameStrata() return 'MEDIUM' end
            function f:SetBackdrop() end
            function f:SetBackdropColor() end
            function f:SetBackdropBorderColor() end
            function f:SetAutoFocus() end
            function f:SetTextInsets() end
            function f:SetJustifyH() end
            function f:SetNumeric() end
            function f:SetMaxLetters() end
            function f:SetMultiLine() end
            function f:SetText(v)
                self._text = v or ''
                if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self) end
            end
            function f:GetText() return self._text end
            function f:ClearFocus() end
            function f:SetNormalTexture() end
            function f:SetHighlightTexture() end
            function f:SetPushedTexture() end
            function f:SetDisabledTexture() end
            function f:SetNormalFontObject() end
            function f:SetHighlightFontObject() end
            function f:SetHitRectInsets() end
            function f:SetFontObject() end
            function f:RegisterForClicks() end
            function f:RegisterEvent() end
            function f:Enable() self._enabled = true end
            function f:Disable() self._enabled = false end
            function f:SetEnabled(v) self._enabled = v and true or false end
            function f:LockHighlight() end
            function f:UnlockHighlight() end
            function f:Show() self._shown = true end
            function f:Hide() self._shown = false end
            function f:SetShown(v) self._shown = v and true or false end
            function f:IsShown() return self._shown end
            function f:SetScript(ev, fn) self._scripts[ev] = fn end
            function f:GetScript(ev) return self._scripts[ev] end
            function f:HookScript(ev, fn)
                local prev = self._scripts[ev]
                self._scripts[ev] = function(...) if prev then prev(...) end fn(...) end
            end
            function f:SetScrollChild() end
            function f:GetHeight() return 400 end
            function f:GetWidth() return 800 end
            function f:SetScale() end
            function f:SetAlpha() end
            function f:EnableMouseWheel() end
            function f:GetFontString()
                if not self._fs then self._fs = self:CreateFontString() end
                return self._fs
            end
            function f:CreateTexture()
                local t = {}
                function t:SetAllPoints() end
                function t:SetPoint() end
                function t:ClearAllPoints() end
                function t:SetSize() end
                function t:SetWidth() end
                function t:SetHeight() end
                function t:SetColorTexture() end
                function t:SetTexture() end
                function t:SetTexCoord() end
                function t:SetVertexColor() end
                function t:SetDesaturated() end
                function t:SetAlpha() end
                function t:Hide() end
                function t:Show() end
                function t:SetShown() end
                return t
            end
            function f:CreateFontString()
                local fs = { _text = '', _shown = true }
                function fs:SetPoint() end
                function fs:ClearAllPoints() end
                function fs:SetWidth() end
                function fs:SetHeight() end
                function fs:SetSize() end
                function fs:GetStringHeight() return 14 end
                function fs:SetJustifyH() end
                function fs:SetWordWrap() end
                function fs:SetJustifyV() end
                function fs:SetWordWrap() end
                function fs:SetText(v) self._text = v or '' end
                function fs:GetText() return self._text end
                function fs:SetTextColor() end
                function fs:SetFontObject() end
                function fs:SetFont() end
                function fs:GetFont() return 'Font.ttf', 12, '' end
                function fs:SetShadowColor() end
                function fs:SetShadowOffset() end
                function fs:SetSpacing() end
                function fs:Show() self._shown = true end
                function fs:Hide() self._shown = false end
                function fs:SetShown(v) self._shown = v and true or false end
                function fs:IsShown() return self._shown end
                return fs
            end
            return f
        end

        createdFrames = {}
        UIParent = makeFrame('Frame', 'UIParent')
        UISpecialFrames = {}
        SlashCmdList = {}
        StaticPopupDialogs = {}
        CreateFrame = function(kind, name, parent)
            local f = makeFrame(kind, name, parent)
            createdFrames[#createdFrames + 1] = f
            return f
        end

        dropdownInits = {}
        addedItems = {}
        UIDropDownMenu_SetWidth = function() end
        UIDropDownMenu_JustifyText = function() end
        UIDropDownMenu_Initialize = function(f, fn) dropdownInits[f._name or tostring(f)] = fn end
        UIDropDownMenu_SetText = function(f, text) f._menuText = text end
        UIDropDownMenu_CreateInfo = function() return {} end
        UIDropDownMenu_AddButton = function(item) addedItems[#addedItems + 1] = item end

        invited = {}
        InviteUnit = function(name) invited[#invited + 1] = name end
        GetNumGroupMembers = function() return 2 end
        IsInRaid = function() return true end
        InCombatLockdown = function() return false end
        UnitIsGroupLeader = function() return true end
        UnitIsGroupAssistant = function() return false end
        UnitName = function(u) if u == 'player' then return 'Alice', 'Sun' end end
        GetRealmName = function() return 'Realm' end
        GetGuildInfo = function() return 'Old Kraken' end
        IsInGuild = function() return true end
        GetTime = function() return 100 end
        GetServerTime = function() return 1700000000 end
        date = os.date
        C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }

        hubPages = {}
        OldKraken = {
            name = 'OldKraken',
            version = '0.5.3-alpha.1',
            _listeners = {},
            UIHub = {
                RegisterPage = function(_, key, _, _, create) hubPages[key] = create end,
            },
            On = function(self, ev, fn)
                self._listeners[ev] = self._listeners[ev] or {}
                self._listeners[ev][#self._listeners[ev] + 1] = fn
            end,
            Fire = function(self, ev, ...)
                for _, fn in ipairs(self._listeners[ev] or {}) do fn(...) end
            end,
            DB = { events = {}, settings = { guildEventNotifications = true } },
            Communication = {
                handlers = {},
                queue = {},
                RegisterHandler = function(self, kind, fn) self.handlers[kind] = fn end,
                SendProtocol = function() return true end,
            },
            UIStyle = {
                Colors = {
                    brandGold = {0.88, 0.69, 0.32, 1},
                    mutedText = {0.63, 0.67, 0.73},
                    text = {0.93, 0.94, 0.96},
                    success = {0.41, 0.86, 0.55, 1},
                    neutral = {0.63, 0.67, 0.73, 1},
                    sel = {0.20, 0.28, 0.62, 0.55},
                    selEdge = {0.55, 0.66, 1, 1},
                },
                Window = function() end,
                Button = function() end,
                Dropdown = function() end,
                Input = function() end,
                Panel = function() end,
                Font = function() end,
                PanelFrame = function(parent) return makeFrame('Frame', nil, parent) end,
                StepIndicator = function(parent, number, title)
                    local s = makeFrame('Frame', nil, parent)
                    s.number = s:CreateFontString(); s.title = s:CreateFontString()
                    function s:SetTitle(v) self.title:SetText(v or '') end
                    return s
                end,
                Chip = function(parent, text, options)
                    local c = makeFrame('Button', nil, parent)
                    c.label = c:CreateFontString(); c.label:SetText(text or '')
                    c.active = options and options.active and true or false
                    function c:SetLabel(v) self.label:SetText(v or '') end
                    function c:SetActive(a) self.active = a and true or false end
                    return c
                end,
            },
        }
        '''
    )
    lua.execute((root / 'ActivityCatalog.lua').read_text(encoding='utf-8'))
    lua.execute((root / 'GroupFinder.lua').read_text(encoding='utf-8'))
    lua.execute((root / 'GuildEvents.lua').read_text(encoding='utf-8'))
    lua.execute(
        '''
        local events = OldKraken.GuildEvents
        -- Activate module via PLAYER_LOGIN
        for _, f in ipairs(createdFrames) do
            if f._scripts.OnEvent then f._scripts.OnEvent(f, 'PLAYER_LOGIN') end
        end

        local future = GetServerTime() + 3600
        assert(events:Create('Event One', '', future, 'raid', 40, 'onyxia'))
        assert(events:Create('Event Two', '', future + 600, 'raid', 40, 'hyjalsummit'))
        local store = OldKraken.DB.events.guildCalendarV1['Realm\001Old Kraken\001Alice Sun']
        assert(store and store.owned)
        local k1, k2, id1, id2
        for key, e in pairs(store.owned) do
            if e.title == 'Event One' then k1, id1 = key, e.id
            elseif e.title == 'Event Two' then k2, id2 = key, e.id end
        end
        assert(k1 and k2)
        OldKraken.Communication.handlers.CEVRSVP('Bob Moon', '', OldKraken.GroupFinder._pack({'Alice Sun', id1, 'healer', '1'}))
        assert(events:Decide(k1, 'Bob Moon', 'accepted'))
        OldKraken.Communication.handlers.CEVRSVP('Carol Star', '', OldKraken.GroupFinder._pack({'Alice Sun', id2, 'dps', '1'}))
        assert(events:Decide(k2, 'Carol Star', 'accepted'))

        -- TASK-3a: InviteAll before window is created must not crash
        invited = {}
        assert(events:InviteAll(k1))
        assert(#invited == 1 and invited[1] == 'Bob Moon', 'Accepted participant of Event One must be invited before window exists')
        events:PumpRaidInvites()

        -- TASK-4: _G.allowed must not affect selectMinutes
        _G.allowed = function() return false end
        local page = hubPages.events(UIParent)
        assert(page, 'Events page must be created')

        local minInit = dropdownInits['OldKrakenEventsMinute']
        assert(minInit, 'Minute dropdown initializer must be registered')
        addedItems = {}
        minInit(OldKrakenEventsMinute, 2, 0)
        assert(#addedItems == 15, 'Minute submenu 00-14 must have 15 items')
        for _, item in ipairs(addedItems) do
            assert(not item.disabled, 'Minute item must not be disabled by global _G.allowed')
        end
        addedItems[6].func()
        assert(OldKrakenEventsMinute._menuText == '05', 'Minute selection must update dropdown text')

        -- TASK-3b: InviteAll with another key must not reuse roleFilter from selected event
        page.filterEvent = k1
        page.roleFilter = 'tank'
        invited = {}
        assert(events:InviteAll(k2))
        assert(page.filterEvent == k2, 'filterEvent must switch to passed key')
        assert(page.roleFilter == false, 'roleFilter must reset when InviteAll is called for different event')
        assert(#invited == 1 and invited[1] == 'Carol Star', 'Accepted participant of Event Two must be invited')

        -- TASK-5: Typing in f.title (OnTextChanged) must preserve manualTitle across activity/kind switches
        page:SetCreationMode(true)
        local autoTitle = page.title:GetText()
        assert(autoTitle ~= '', 'Auto-title must be populated in creation mode')
        -- Simulate keyboard typing (bypassing SetText hook, triggering OnTextChanged directly)
        page.title._text = 'Custom Guild Raid'
        page.title:GetScript('OnTextChanged')(page.title)
        -- Trigger syncAutoTitle via noLocationButton
        page.noLocationButton:GetScript('OnClick')(page.noLocationButton)
        assert(page.title:GetText() == 'Custom Guild Raid', 'Manual title must not be overwritten on activity change')
        -- Clear field via keyboard and trigger OnTextChanged
        page.title._text = ''
        page.title:GetScript('OnTextChanged')(page.title)
        page.noLocationButton:GetScript('OnClick')(page.noLocationButton)
        assert(page.title:GetText() ~= '', 'Clearing manual title must allow auto-title to resume')
        -- Simulate submit reset and re-opening creation mode
        page.title._text = 'Old Custom Event'
        page.title:GetScript('OnTextChanged')(page.title)
        page.title:SetText('')
        page:SetCreationMode(false)
        page:SetCreationMode(true)
        assert(page.title:GetText() ~= 'Old Custom Event' and page.title:GetText() ~= '', 'Re-opening after submit must reset manualTitle and fill auto-title')

        -- Cancel creation draft must clear manualTitle/autoFilledTitle/title/description
        page.title._text = 'Draft Before Cancel'
        page.title:GetScript('OnTextChanged')(page.title)
        page.cancelCreate:GetScript('OnClick')(page.cancelCreate)
        assert(page.title:GetText() == '', 'Cancel must clear title field')
        page:SetCreationMode(true)
        assert(page.title:GetText() ~= 'Draft Before Cancel' and page.title:GetText() ~= '', 'Re-opening after Cancel must start with fresh auto-title')
        '''
    )


if __name__ == '__main__':
    run_task1_roster_uihub()
    run_task2_and_task6_group_finder()
    run_task3_4_5_guild_events()
    print('PASS: all 6 audit regression checks passed')
