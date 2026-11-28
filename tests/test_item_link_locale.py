from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'ItemLinkLocale.lua').read_text(encoding='utf-8')
DATABASE_SRC = (ROOT / 'Database.lua').read_text(encoding='utf-8')
LOCALE_SRC = (ROOT / 'Locale.lua').read_text(encoding='utf-8')


def make_client(extra_setup=''):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        registered = {}
        registerCounts = {}
        getInfoCalls = 0
        requestCalls = 0
        requestedIds = {}
        itemNames = {}
        secretValues = {}
        inaccessibleValues = {}
        eventHandler = nil
        nowTime = 100

        function GetTime()
            return nowTime
        end

        OldKraken = {
            DB = {
                settings = {
                    localizeItemLinks = true,
                },
            },
        }

        function issecretvalue(v)
            return secretValues[v] == true
        end

        function canaccessvalue(v)
            return not inaccessibleValues[v]
        end

        C_Item = {
            GetItemInfo = function(arg)
                getInfoCalls = getInfoCalls + 1
                return itemNames[arg]
            end,
            RequestLoadItemDataByID = function(id)
                requestCalls = requestCalls + 1
                requestedIds[#requestedIds + 1] = id
            end,
        }

        ChatFrameUtil = {
            AddMessageEventFilter = function(event, fn)
                registered[event] = fn
                registerCounts[event] = (registerCounts[event] or 0) + 1
            end,
        }

        function CreateFrame()
            return {
                RegisterEvent = function() end,
                SetScript = function(_, script, fn)
                    if script == 'OnEvent' then
                        eventHandler = fn
                    end
                end,
            }
        end
        '''
        + extra_setup
    )
    lua.execute(SOURCE)
    return lua


# 1, 2, 3, 4: Name replacement preserving payload, color codes, multiple links, dedup, early exit, CHAT_MSG_LOOT
lua = make_client()
lua.execute(
    '''
    itemNames[19019] = 'Громовержець, Благословенний клинок Шукача Вітру'
    itemNames[17182] = 'Сульфурас, Рука Раґнароса'

    local filter = registered['CHAT_MSG_GUILD']
    assert(type(filter) == 'function')
    assert(registered['CHAT_MSG_WHISPER'] == filter)
    assert(registered['CHAT_MSG_RAID'] == filter)
    assert(registered['CHAT_MSG_LOOT'] == filter)

    -- 1 & 2: Color codes and payload preserved
    local msg1 = 'Поглянь на |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r!'
    local hide, out, sender, lang, chan, flag = filter(nil, 'CHAT_MSG_GUILD', msg1, 'Alice', 'Ukrainian', nil, 42)
    assert(hide == false)
    assert(out == 'Поглянь на |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Громовержець, Благословенний клинок Шукача Вітру]|h|r!')
    assert(sender == 'Alice' and lang == 'Ukrainian' and chan == nil and flag == 42)
    assert(getInfoCalls == 1)

    -- CHAT_MSG_LOOT works as well
    local hideLoot, outLoot = filter(nil, 'CHAT_MSG_LOOT', 'Ви отримуєте здобич: |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r.')
    assert(hideLoot == false)
    assert(outLoot == 'Ви отримуєте здобич: |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Громовержець, Благословенний клинок Шукача Вітру]|h|r.')

    -- 3: Multiple item links + duplicate link in same message
    getInfoCalls = 0
    local msg2 = '|cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r та |cffff8000|Hitem:17182:0:0:0:0:0:0:0|h[Sulfuras]|h|r і ще |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r'
    local hide2, out2 = filter(nil, 'CHAT_MSG_GUILD', msg2, 'Bob')
    assert(hide2 == false)
    assert(out2 == '|cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Громовержець, Благословенний клинок Шукача Вітру]|h|r та |cffff8000|Hitem:17182:0:0:0:0:0:0:0|h[Сульфурас, Рука Раґнароса]|h|r і ще |cffff8000|Hitem:19019:0:0:0:0:0:0:0|h[Громовержець, Благословенний клинок Шукача Вітру]|h|r')
    assert(getInfoCalls == 1)

    -- Modern sparse payload with >= 7 colons (empty optional fields)
    getInfoCalls = 0
    local hideSparse, outSparse = filter(nil, 'CHAT_MSG_GUILD', '|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r')
    assert(hideSparse == false and outSparse == '|cffff8000|Hitem:19019::::::::60:::::|h[Громовержець, Благословенний клинок Шукача Вітру]|h|r')
    assert(getInfoCalls == 0)

    -- 4: Early-exit when no |Hitem: is present (0 API calls)
    getInfoCalls = 0
    requestCalls = 0
    local nret = select('#', filter(nil, 'CHAT_MSG_GUILD', 'Звичайний текст без предметів |Hspell:1234|h[Spell]|h', 'Bob'))
    assert(nret == 1)
    assert(filter(nil, 'CHAT_MSG_GUILD', 'Звичайний текст', 'Bob') == false)
    assert(getInfoCalls == 0 and requestCalls == 0)
    '''
)


# 5, 6, 7, 8: Uncached passthrough, RequestLoadItemDataByID dedup, next message cached, no negative cache
lua = make_client()
lua.execute(
    '''
    local filter = registered['CHAT_MSG_SAY']
    local msg = 'Випав |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Blue Sword]|h|r!'

    -- 5: Uncached item is NOT hidden or delayed
    local nret = select('#', filter(nil, 'CHAT_MSG_SAY', msg, 'Bob'))
    local h = filter(nil, 'CHAT_MSG_SAY', msg, 'Bob')
    assert(nret == 1 and h == false)

    -- 6: RequestLoadItemDataByID deduplicated across repeated messages
    assert(requestCalls == 1 and requestedIds[1] == 12345)

    -- 8: Failed load does NOT negatively cache; item can still resolve later
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 12345, false)
    itemNames[12345] = 'Синій меч'

    -- 7: Next message resolves and caches
    local h2, out2 = filter(nil, 'CHAT_MSG_SAY', msg, 'Bob')
    assert(h2 == false)
    assert(out2 == 'Випав |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Синій меч]|h|r!')

    -- Subsequent message uses cache (0 extra GetItemInfo calls)
    getInfoCalls = 0
    local h3, out3 = filter(nil, 'CHAT_MSG_SAY', msg, 'Bob')
    assert(h3 == false and out3 == out2 and getInfoCalls == 0)
    '''
)


# 9: MAX_CACHE = 1024 FIFO eviction + queue compaction over long session
lua = make_client()
lua.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    for i = 1, 1024 do
        itemNames[i] = 'Предмет_' .. i
        local _, out = filter(nil, 'CHAT_MSG_GUILD', '|Hitem:' .. i .. ':0:0:0:0:0:0:0|h[Item_' .. i .. ']|h')
        assert(out == '|Hitem:' .. i .. ':0:0:0:0:0:0:0|h[Предмет_' .. i .. ']|h')
    end

    -- Item 1 and Item 2 are currently in cache
    getInfoCalls = 0
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1:0:0:0:0:0:0:0|h[Item_1]|h')
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:2:0:0:0:0:0:0:0|h[Item_2]|h')
    assert(getInfoCalls == 0)

    -- Insert 1025th item -> evicts Item 1 (oldest)
    itemNames[1025] = 'Предмет_1025'
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1025:0:0:0:0:0:0:0|h[Item_1025]|h')

    -- Item 2 is still cached
    getInfoCalls = 0
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:2:0:0:0:0:0:0:0|h[Item_2]|h')
    assert(getInfoCalls == 0)

    -- Item 1 was evicted, so GetItemInfo is called again
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1:0:0:0:0:0:0:0|h[Item_1]|h')
    assert(getInfoCalls == 1)
    '''
)


# 10: MAX_PENDING = 200 cap, event release, API error cleanup, and TTL expiration
lua = make_client()
lua.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    for i = 1, 205 do
        filter(nil, 'CHAT_MSG_GUILD', '|Hitem:' .. (50000 + i) .. ':0:0:0:0:0:0:0|h[U]|h')
    end
    assert(requestCalls == 200)

    -- Completing one frees a pending slot
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 50001, true)
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:60001:0:0:0:0:0:0:0|h[U]|h')
    assert(requestCalls == 201)

    -- Stale pending entries expire after PENDING_TTL (30s) without timers/OnUpdate
    nowTime = 131
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:60002:0:0:0:0:0:0:0|h[U]|h')
    assert(requestCalls == 202)

    -- Previously stale ID can be requested again after TTL
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:50002:0:0:0:0:0:0:0|h[U]|h')
    assert(requestCalls == 203)
    '''
)

lua_rerequest = make_client()
lua_rerequest.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    -- 1. Request ID 123 at t=100, then ID 456 at t=105
    nowTime = 100
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:123:0:0:0:0:0:0:0|h[A]|h')
    nowTime = 105
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:456:0:0:0:0:0:0:0|h[B]|h')
    assert(requestCalls == 2)

    -- 2. Complete ID 123 and re-request ID 123 at t=120
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 123, true)
    nowTime = 120
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:123:0:0:0:0:0:0:0|h[A]|h')
    assert(requestCalls == 3)

    -- 3. At t=136: old queue entry 123@100 is skipped without blocking 456@105 (expired)
    -- and without falsely clearing active 123@120
    nowTime = 136
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:456:0:0:0:0:0:0:0|h[B]|h')
    assert(requestCalls == 4) -- 456 expired and was re-requested

    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:123:0:0:0:0:0:0:0|h[A]|h')
    assert(requestCalls == 4) -- 123@120 is still pending, NOT re-requested
    '''
)

lua_same_tick = make_client()
lua_same_tick.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    -- 1. Request ID 123 at t=100, complete it, and re-request ID 123 in the SAME GetTime() tick (t=100)
    nowTime = 100
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:123:0:0:0:0:0:0:0|h[A]|h')
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 123, true)
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:123:0:0:0:0:0:0:0|h[A]|h')
    assert(requestCalls == 2)

    -- 2. Fill remaining 199 pending slots at t=105 (total active = 200)
    nowTime = 105
    for i = 1, 199 do
        filter(nil, 'CHAT_MSG_GUILD', '|Hitem:' .. (80000 + i) .. ':0:0:0:0:0:0:0|h[X]|h')
    end
    assert(requestCalls == 201)

    -- 3. At t=130: stale seq=1 (123@100) is skipped without decrementing pendingCount,
    -- while active seq=2 (123@100) expires -> exactly 1 slot freed (199 active)
    nowTime = 130
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:90001:0:0:0:0:0:0:0|h[Y]|h')
    assert(requestCalls == 202) -- 1 slot was freed

    -- Next request must be blocked because active count is back at 200 (no double-decrement)
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:90002:0:0:0:0:0:0:0|h[Z]|h')
    assert(requestCalls == 202)
    '''
)

lua_req_err = make_client(
    '''
    failNextRequest = true
    C_Item.RequestLoadItemDataByID = function(id)
        requestCalls = requestCalls + 1
        if failNextRequest then
            error('load failed')
        end
        requestedIds[#requestedIds + 1] = id
    end
    '''
)
lua_req_err.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    -- First attempt errors inside pcall -> slot must NOT stay occupied
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:70001:0:0:0:0:0:0:0|h[Err]|h')
    assert(requestCalls == 1)

    -- Second attempt succeeds for the same ID because the failed slot was freed
    failNextRequest = false
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:70001:0:0:0:0:0:0:0|h[Err]|h')
    assert(requestCalls == 2 and requestedIds[1] == 70001)
    '''
)


# 11: issecretvalue / canaccessvalue guards
lua = make_client()
lua.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    local secretMsg = '|Hitem:99:0:0:0:0:0:0:0|h[Secret]|h'
    secretValues[secretMsg] = true
    assert(select('#', filter(nil, 'CHAT_MSG_GUILD', secretMsg, 'Bob')) == 1)
    assert(getInfoCalls == 0)

    local inaccMsg = '|Hitem:100:0:0:0:0:0:0:0|h[Inacc]|h'
    inaccessibleValues[inaccMsg] = true
    assert(select('#', filter(nil, 'CHAT_MSG_GUILD', inaccMsg, 'Bob')) == 1)
    assert(getInfoCalls == 0)

    -- Secret return value from GetItemInfo is ignored safely
    local secretResult = 'SecretLocalized'
    secretValues[secretResult] = true
    itemNames[101] = secretResult
    assert(select('#', filter(nil, 'CHAT_MSG_GUILD', '|Hitem:101:0:0:0:0:0:0:0|h[Orig]|h', 'Bob')) == 1)
    '''
)


# 12: Disabled toggle (localizeItemLinks = false or nil DB) short-circuits
lua = make_client()
lua.execute(
    '''
    itemNames[777] = 'Локалізований'
    local filter = registered['CHAT_MSG_GUILD']
    OldKraken.DB.settings.localizeItemLinks = false
    assert(select('#', filter(nil, 'CHAT_MSG_GUILD', '|Hitem:777:0:0:0:0:0:0:0|h[Original]|h', 'Bob')) == 1)
    assert(getInfoCalls == 0 and requestCalls == 0)

    OldKraken.DB = nil
    assert(select('#', filter(nil, 'CHAT_MSG_GUILD', '|Hitem:777:0:0:0:0:0:0:0|h[Original]|h', 'Bob')) == 1)
    assert(getInfoCalls == 0 and requestCalls == 0)
    '''
)


# 13: Unavailable APIs & partial registration idempotency
lua_no_api = make_client(
    '''
    C_Item = nil
    GetItemInfo = nil
    ChatFrameUtil = nil
    ChatFrame_AddMessageEventFilter = nil
    '''
)
lua_no_api.execute(
    '''
    assert(OldKraken.ItemLinkLocale.LocalizeMessage(OldKraken.ItemLinkLocale, '|Hitem:123:0:0:0:0:0:0:0|h[Test]|h') == nil)
    assert(eventHandler ~= nil)
    eventHandler(nil, 'PLAYER_LOGIN')
    '''
)

lua_partial = make_client(
    '''
    ChatFrameUtil = {
        AddMessageEventFilter = function(event, fn)
            if event == 'CHAT_MSG_LOOT' then
                error('modern failed for loot')
            end
            registered[event] = fn
            registerCounts[event] = (registerCounts[event] or 0) + 1
        end,
    }
    function ChatFrame_AddMessageEventFilter(event, fn)
        registered[event] = fn
        registerCounts[event] = (registerCounts[event] or 0) + 1
    end
    '''
)
lua_partial.execute(
    '''
    -- Trigger PLAYER_LOGIN retry as well
    eventHandler(nil, 'PLAYER_LOGIN')
    assert(type(registered['CHAT_MSG_GUILD']) == 'function')
    assert(type(registered['CHAT_MSG_LOOT']) == 'function')
    assert(registerCounts['CHAT_MSG_GUILD'] == 1)
    assert(registerCounts['CHAT_MSG_LOOT'] == 1)
    '''
)


# 14: Malformed / incomplete payloads (including positive ID with closed brackets) untouched
lua = make_client()
lua.execute(
    '''
    itemNames[123] = 'Тест'
    local filter = registered['CHAT_MSG_GUILD']
    local malformed = {
        '|Hitem:|h[Bad]|h',
        '|Hitem:abc:0:0:0:0:0:0:0|h[Bad]|h',
        '|Hitem:0:0:0:0:0:0:0:0|h[Bad]|h',
        '|Hitem:-5:0:0:0:0:0:0:0|h[Bad]|h',
        '|Hitem:123|h[Bad]|h',
        '|Hitem:123:0:0|h[Bad]|h',
        '|Hitem:123:0:0:0:0:0:0|h[Bad]|h',
        '|Hitem:123:abc:0:0:0:0:0:0|h[Bad]|h',
        '|Hitem:123:0:0:0:0:0:0:0|h[Unclosed',
        '|Hspell:123|h[Spell]|h',
    }
    for _, msg in ipairs(malformed) do
        assert(select('#', filter(nil, 'CHAT_MSG_GUILD', msg, 'Bob')) == 1)
    end
    assert(getInfoCalls == 0 and requestCalls == 0)
    '''
)


# 15: Random suffix (f7 ~= 0) left untouched in MVP
lua = make_client()
lua.execute(
    '''
    itemNames[1520] = 'Шкіряні чоботи'
    local filter = registered['CHAT_MSG_GUILD']
    local nRandom = select('#', filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1520:0:0:0:0:0:12:0|h[Leather Boots of the Monkey]|h'))
    assert(nRandom == 1)
    assert(getInfoCalls == 0 and requestCalls == 0)
    '''
)


# 16: Database default & Locale integration
lua_db = LuaRuntime(unpack_returned_tuples=True)
lua_db.execute(
    '''
    OldKraken = { version = '0.5.9-alpha.1' }
    OldKrakenDB = nil
    function GetRealmName() return 'Forever' end
    function GetLocale() return 'enUS' end
    '''
)
lua_db.execute(DATABASE_SRC)
lua_db.execute(LOCALE_SRC)
lua_db.execute(
    '''
    local db = OldKraken.Database:Initialize()
    assert(db.settings.localizeItemLinks == true)
    db.settings.language = 'enUS'
    OldKraken.InitializeLocale(db)
    assert(OldKraken.Translate('Назви предметів у чаті') == 'Chat item link names')

    -- Existing SavedVariables with explicit false must preserve false
    OldKrakenDB = { schemaVersion = 3, settings = { localizeItemLinks = false } }
    local dbPreserved = OldKraken.Database:Initialize()
    assert(dbPreserved.settings.localizeItemLinks == false)

    -- Existing SavedVariables without localizeItemLinks key receives default true
    OldKrakenDB = { schemaVersion = 3, settings = {} }
    local dbMigrated = OldKraken.Database:Initialize()
    assert(dbMigrated.settings.localizeItemLinks == true)
    '''
)


# 17: Post-update via TransformMessages (debounced, noRequest, failure/unrelated guards, secret guard, LATE_TTL)
lua_post = make_client(
    '''
    NUM_CHAT_WINDOWS = 3
    scheduledTimers = {}
    transformCalls = 0
    C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }

    local function makeChatFrame(entries)
        return {
            entries = entries,
            TransformMessages = function(self, pred, xform)
                transformCalls = transformCalls + 1
                for _, entry in ipairs(self.entries) do
                    if pred(entry) then
                        xform(entry)
                    end
                end
            end,
        }
    end

    local secretLine = '|Hitem:12345:0:0:0:0:0:0:0|h[SecretLine]|h'
    secretValues[secretLine] = true

    ChatFrame1 = makeChatFrame({
        { message = 'Перший: |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Blue Sword]|h|r!' },
        { message = 'Інше повідомлення без предмета' },
        { message = secretLine },
    })
    ChatFrame2 = nil
    ChatFrame3 = makeChatFrame({
        { message = 'Шепіт: |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Blue Sword]|h|r' },
    })
    '''
)
lua_post.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']

    -- 1. Uncached item in chat passes through and registers in late queue
    local n = select('#', filter(nil, 'CHAT_MSG_GUILD', ChatFrame1.entries[1].message, 'Bob'))
    assert(n == 1 and requestCalls == 1)

    -- 2. Unrelated item load (not seen in chat) must NOT schedule TransformMessages
    itemNames[44444] = 'Чужий предмет'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 44444, true)
    assert(#scheduledTimers == 0 and transformCalls == 0)

    -- 3. Failed load (success == false) clears late entry and does NOT schedule TransformMessages
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:22222:0:0:0:0:0:0:0|h[Missing]|h', 'Bob')
    assert(requestCalls == 2)
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 22222, false)
    assert(#scheduledTimers == 0 and transformCalls == 0)

    -- 4. Event with missing data inside fixShown does NOT call RequestLoadItemDataByID (noRequest = true)
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:33333:0:0:0:0:0:0:0|h[NoData]|h', 'Bob')
    assert(requestCalls == 3)
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 33333, true)
    assert(#scheduledTimers == 1 and scheduledTimers[1].delay == 0.25)
    scheduledTimers[1].fn()
    assert(requestCalls == 3 and transformCalls == 0)

    -- 5. Successful load updates ChatFrame1 and ChatFrame3 via TransformMessages without extra RequestLoadItemDataByID
    itemNames[12345] = 'Синій меч'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 12345, true)
    assert(#scheduledTimers == 2)
    scheduledTimers[2].fn()
    assert(transformCalls == 2)
    assert(requestCalls == 3)
    assert(ChatFrame1.entries[1].message == 'Перший: |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Синій меч]|h|r!')
    assert(ChatFrame1.entries[2].message == 'Інше повідомлення без предмета')
    assert(ChatFrame3.entries[1].message == 'Шепіт: |cff0070dd|Hitem:12345:0:0:0:0:0:0:0|h[Синій меч]|h|r')

    -- 6. Disabled toggle during scheduled fixShown skips TransformMessages
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:55555:0:0:0:0:0:0:0|h[Off]|h', 'Bob')
    itemNames[55555] = 'Вимкнений'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55555, true)
    OldKraken.DB.settings.localizeItemLinks = false
    scheduledTimers[3].fn()
    assert(transformCalls == 2)

    -- 7. LATE_TTL (120s) expiration frees slots after 200 entries
    OldKraken.DB.settings.localizeItemLinks = true
    nowTime = 200
    for i = 1, 200 do
        filter(nil, 'CHAT_MSG_GUILD', '|Hitem:' .. (71000 + i) .. ':0:0:0:0:0:0:0|h[L]|h', 'Bob')
    end
    nowTime = 321
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:79999:0:0:0:0:0:0:0|h[FreshLate]|h', 'Bob')
    itemNames[79999] = 'Свіжий'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 79999, true)
    scheduledTimers[#scheduledTimers].fn()
    assert(transformCalls == 4) -- fixShown ran TransformMessages on ChatFrame1 and ChatFrame3 for 79999
    '''
)


# 18: lateItems guards: missing RequestLoadItemDataByID, pcall error, MAX_PENDING full, already-pending, no C_Timer.After
lua_late_no_req = make_client(
    '''
    NUM_CHAT_WINDOWS = 1
    scheduledTimers = {}
    transformCalls = 0
    C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }
    ChatFrame1 = {
        TransformMessages = function() transformCalls = transformCalls + 1 end,
    }
    C_Item.RequestLoadItemDataByID = nil
    '''
)
lua_late_no_req.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1001:0:0:0:0:0:0:0|h[NoReq]|h', 'Bob')
    itemNames[1001] = 'БезЗапиту'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 1001, true)
    assert(#scheduledTimers == 0 and transformCalls == 0)
    '''
)

lua_late_err = make_client(
    '''
    NUM_CHAT_WINDOWS = 1
    scheduledTimers = {}
    transformCalls = 0
    C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }
    ChatFrame1 = {
        TransformMessages = function() transformCalls = transformCalls + 1 end,
    }
    C_Item.RequestLoadItemDataByID = function() error('req fail') end
    '''
)
lua_late_err.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1002:0:0:0:0:0:0:0|h[ErrReq]|h', 'Bob')
    itemNames[1002] = 'Помилка'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 1002, true)
    assert(#scheduledTimers == 0 and transformCalls == 0)
    '''
)

lua_late_cap_and_dup = make_client(
    '''
    NUM_CHAT_WINDOWS = 1
    scheduledTimers = {}
    transformCalls = 0
    C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }
    ChatFrame1 = {
        entries = {
            { message = 'Чат: |Hitem:90001:0:0:0:0:0:0:0|h[First]|h' },
        },
        TransformMessages = function(self, pred, xform)
            transformCalls = transformCalls + 1
            for _, entry in ipairs(self.entries) do
                if pred(entry) then xform(entry) end
            end
        end,
    }
    '''
)
lua_late_cap_and_dup.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    -- Fill MAX_PENDING = 200 (90001 is #1)
    for i = 1, 200 do
        filter(nil, 'CHAT_MSG_GUILD', '|Hitem:' .. (90000 + i) .. ':0:0:0:0:0:0:0|h[P]|h', 'Bob')
    end
    assert(requestCalls == 200)

    -- 201st item hits MAX_PENDING -> not requested and NOT added to lateItems
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:99999:0:0:0:0:0:0:0|h[Over]|h', 'Bob')
    assert(requestCalls == 200)
    itemNames[99999] = 'ПонадЛіміт'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 99999, true)
    assert(#scheduledTimers == 0 and transformCalls == 0)

    -- Already-pending item (90001) sent again while pending: markLate remains allowed and updates ChatFrame1
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:90001:0:0:0:0:0:0:0|h[First]|h', 'Bob')
    assert(requestCalls == 200)
    itemNames[90001] = 'ПершийЛокалізований'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 90001, true)
    assert(#scheduledTimers == 1)
    scheduledTimers[1].fn()
    assert(transformCalls == 1)
    assert(ChatFrame1.entries[1].message == 'Чат: |Hitem:90001:0:0:0:0:0:0:0|h[ПершийЛокалізований]|h')
    '''
)

lua_no_timer = make_client(
    '''
    NUM_CHAT_WINDOWS = 1
    transformCalls = 0
    C_Timer = nil
    ChatFrame1 = {
        entries = { { message = '|Hitem:1003:0:0:0:0:0:0:0|h[NoTimer]|h' } },
        TransformMessages = function() transformCalls = transformCalls + 1 end,
    }
    '''
)
lua_no_timer.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    filter(nil, 'CHAT_MSG_GUILD', '|Hitem:1003:0:0:0:0:0:0:0|h[NoTimer]|h', 'Bob')
    itemNames[1003] = 'БезТаймера'
    eventHandler(nil, 'ITEM_DATA_LOAD_RESULT', 1003, true)
    assert(transformCalls == 0)
    '''
)

# 19: Held message buffering until GET_ITEM_INFO_RECEIVED + HELD_TTL timeout + failedHold negative cache
lua_held = make_client(
    '''
    delivered = {}
    scheduledTimers = {}
    C_Timer = {
        After = function(delay, fn)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, fn = fn }
        end,
    }
    ChatFrame1 = {
        MessageEventHandler = function(self, event, msg, sender, ...)
            local filter = registered[event]
            local drop, newMsg = filter(self, event, msg, sender, ...)
            if not drop then
                delivered[#delivered + 1] = { event = event, msg = newMsg or msg, sender = sender }
            end
        end,
    }
    '''
)
lua_held.execute(
    '''
    local filter = registered['CHAT_MSG_GUILD']
    local ruMsg = 'WTS |Hitem:44001:0:0:0:0:0:0:0|h[Синий меч]|h'

    -- Uncached item on ChatFrame1 is held (returns true, not delivered yet)
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', ruMsg, 'Vasya')
    assert(#delivered == 0, 'uncached item message must be held until item info arrives')

    -- Item resolves via GET_ITEM_INFO_RECEIVED -> replayed with localized name
    itemNames[44001] = 'Blue Sword'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 44001, true)
    assert(#delivered == 1)
    assert(delivered[1].msg == 'WTS |Hitem:44001:0:0:0:0:0:0:0|h[Blue Sword]|h')
    assert(delivered[1].sender == 'Vasya')

    -- Unresolvable item (e.g. custom ID 217265) times out after HELD_TTL (1.5s) and replays as-is
    local badMsg = 'LF |Hitem:217265:0:0:0:0:0:0:0|h[Unknown]|h'
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', badMsg, 'Petya')
    assert(#delivered == 1)
    nowTime = nowTime + 2
    for i = #scheduledTimers, 1, -1 do
        local t = table.remove(scheduledTimers, i)
        t.fn()
    end
    assert(#delivered == 2 and delivered[2].msg == badMsg)

    -- Subsequent message with same timed-out ID is NOT held again and does not re-request within NEGATIVE_TTL
    local reqBefore = requestCalls
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', badMsg, 'Petya')
    assert(#delivered == 3 and requestCalls == reqBefore)

    -- Two uncached IDs in one message: waits for both before replaying once
    local twoMsg = 'Trade |Hitem:55001:0:0:0:0:0:0:0|h[A]|h for |Hitem:55002:0:0:0:0:0:0:0|h[B]|h'
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', twoMsg, 'Katya')
    assert(#delivered == 3)
    itemNames[55001] = 'Alpha'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55001, true)
    assert(#delivered == 3, 'must still wait for second uncached ID')
    itemNames[55002] = 'Beta'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55002, true)
    assert(#delivered == 4 and delivered[4].msg == 'Trade |Hitem:55001:0:0:0:0:0:0:0|h[Alpha]|h for |Hitem:55002:0:0:0:0:0:0:0|h[Beta]|h')

    -- Duplicate GET_ITEM_INFO_RECEIVED does not replay again
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55002, true)
    assert(#delivered == 4)

    -- Two uncached IDs: one fails (success=false), other succeeds -> replays with resolved one localized
    local mixMsg = 'Mix |Hitem:55003:0:0:0:0:0:0:0|h[FailOne]|h and |Hitem:55004:0:0:0:0:0:0:0|h[GoodOne]|h'
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', mixMsg, 'Oleh')
    assert(#delivered == 4)
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55003, false)
    assert(#delivered == 4)
    itemNames[55004] = 'ResolvedOne'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55004, true)
    assert(#delivered == 5 and delivered[5].msg == 'Mix |Hitem:55003:0:0:0:0:0:0:0|h[FailOne]|h and |Hitem:55004:0:0:0:0:0:0:0|h[ResolvedOne]|h')

    -- Disabling localizeItemLinks while a message is held still delivers it via timeout/flush
    local disMsg = 'Hold |Hitem:55005:0:0:0:0:0:0:0|h[Orig]|h'
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', disMsg, 'Ira')
    assert(#delivered == 5)
    OldKraken.DB.settings.localizeItemLinks = false
    nowTime = nowTime + 2
    for i = #scheduledTimers, 1, -1 do
        local t = table.remove(scheduledTimers, i)
        t.fn()
    end
    assert(#delivered == 6 and delivered[6].msg == disMsg)
    OldKraken.DB.settings.localizeItemLinks = true

    -- MAX_HELD = 100 cap: 100 held, 101st passes through immediately, all 100 flush once on resolve
    local baseDelivered = #delivered
    for i = 1, 100 do
        ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', 'Batch |Hitem:55006:0:0:0:0:0:0:0|h[BatchItem]|h #' .. i, 'User')
    end
    assert(#delivered == baseDelivered, 'first 100 messages must be held')
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', 'Batch |Hitem:55006:0:0:0:0:0:0:0|h[BatchItem]|h #101', 'User')
    assert(#delivered == baseDelivered + 1, '101st message when heldQueue is full must pass through')
    itemNames[55006] = 'BatchLocalized'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55006, true)
    assert(#delivered == baseDelivered + 101, 'all 100 held messages must replay once')
    -- Unrelated failed event for 55009 while 55008 is held must NOT negatively cache 55009
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', 'Wait |Hitem:55008:0:0:0:0:0:0:0|h[W8]|h', 'Nina')
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55009, false)
    local reqBeforeUnrelated = requestCalls
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', 'Wait |Hitem:55009:0:0:0:0:0:0:0|h[W9]|h', 'Nina')
    assert(requestCalls == reqBeforeUnrelated + 1, 'unrelated failure must not block RequestLoadItemDataByID for 55009')
    itemNames[55008] = 'Wait8'
    itemNames[55009] = 'Wait9'
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55008, true)
    eventHandler(nil, 'GET_ITEM_INFO_RECEIVED', 55009, true)
    assert(#delivered == baseDelivered + 103)
    '''
)

# 20: Missing C_Timer.After never holds message on ChatFrame1
lua_held_no_timer = make_client(
    '''
    delivered = {}
    C_Timer = nil
    ChatFrame1 = {
        MessageEventHandler = function(self, event, msg, sender, ...)
            local filter = registered[event]
            local drop, newMsg = filter(self, event, msg, sender, ...)
            if not drop then
                delivered[#delivered + 1] = { event = event, msg = newMsg or msg, sender = sender }
            end
        end,
    }
    '''
)
lua_held_no_timer.execute(
    '''
    ChatFrame1:MessageEventHandler('CHAT_MSG_GUILD', 'NoTimer |Hitem:55007:0:0:0:0:0:0:0|h[Raw]|h', 'Max')
    assert(#delivered == 1)
    '''
)

print('ItemLinkLocale checks passed')
