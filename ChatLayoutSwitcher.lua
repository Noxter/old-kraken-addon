-- Keyboard layout switcher (QWERTY <-> Ukrainian ЙЦУКЕН) for chat EditBoxes.
local Switcher = {}
OldKraken.ChatLayoutSwitcher = Switcher

local EN_TO_UK = {
    ['q']='й', ['w']='ц', ['e']='у', ['r']='к', ['t']='е', ['y']='н', ['u']='г', ['i']='ш', ['o']='щ', ['p']='з',
    ['[']='х', [']']='ї', ['a']='ф', ['s']='і', ['d']='в', ['f']='а', ['g']='п', ['h']='р', ['j']='о', ['k']='л',
    ['l']='д', [';']='ж', ["'"]='є', ['\\']='ґ', ['z']='я', ['x']='ч', ['c']='с', ['v']='м', ['b']='и', ['n']='т',
    ['m']='ь', [',']='б', ['.']='ю', ['/']='.',
    ['Q']='Й', ['W']='Ц', ['E']='У', ['R']='К', ['T']='Е', ['Y']='Н', ['U']='Г', ['I']='Ш', ['O']='Щ', ['P']='З',
    ['{']='Х', ['}']='Ї', ['A']='Ф', ['S']='І', ['D']='В', ['F']='А', ['G']='П', ['H']='Р', ['J']='О', ['K']='Л',
    ['L']='Д', [':']='Ж', ['"']='Є', ['|']='Ґ', ['Z']='Я', ['X']='Ч', ['C']='С', ['V']='М', ['B']='И', ['N']='Т',
    ['M']='Ь', ['<']='Б', ['>']='Ю', ['?']=',',
    ['@']='"', ['#']='№', ['$']=';', ['^']=':', ['&']='?',
}

local UK_TO_EN = {
    ['й']='q', ['ц']='w', ['у']='e', ['к']='r', ['е']='t', ['н']='y', ['г']='u', ['ш']='i', ['щ']='o', ['з']='p',
    ['х']='[', ['ї']=']', ['ф']='a', ['і']='s', ['в']='d', ['а']='f', ['п']='g', ['р']='h', ['о']='j', ['л']='k',
    ['д']='l', ['ж']=';', ['є']="'", ['ґ']='\\', ['я']='z', ['ч']='x', ['с']='c', ['м']='v', ['и']='b', ['т']='n',
    ['ь']='m', ['б']=',', ['ю']='.', ['.']='/',
    ['Й']='Q', ['Ц']='W', ['У']='E', ['К']='R', ['Е']='T', ['Н']='Y', ['Г']='U', ['Ш']='I', ['Щ']='O', ['З']='P',
    ['Х']='{', ['Ї']='}', ['Ф']='A', ['І']='S', ['В']='D', ['А']='F', ['П']='G', ['Р']='H', ['О']='J', ['Л']='K',
    ['Д']='L', ['Ж']=':', ['Є']='"', ['Ґ']='|', ['Я']='Z', ['Ч']='X', ['С']='C', ['М']='V', ['И']='B', ['Т']='N',
    ['Ь']='M', ['Б']='<', ['Ю']='>', [',']='?',
    ['"']='@', ['№']='#', [';']='$', [':']='^', ['?']='&',
}

local function nextUtf8(s, i)
    local b = s:byte(i)
    if not b then return nil, i end
    local len = 1
    if b >= 240 and b <= 247 then len = 4
    elseif b >= 224 and b <= 239 then len = 3
    elseif b >= 192 and b <= 223 then len = 2 end
    local j = math.min(#s, i + len - 1)
    return s:sub(i, j), j + 1
end

local function isLatin(ch)
    return #ch == 1 and ch:match('^[A-Za-z]$') ~= nil
end

local function isCyrillic(ch)
    if #ch ~= 2 then return false end
    local b1, b2 = ch:byte(1, 2)
    return (b1 == 208 and b2 >= 128 and b2 <= 191)
        or (b1 == 209 and b2 >= 128 and b2 <= 191)
        or (b1 == 210 and (b2 == 144 or b2 == 145))
end

-- Split text into alternating plain/protected segments so WoW links, textures, and raid icons are never corrupted.
local function splitProtected(text)
    local parts, i, n = {}, 1, #text
    local function push(kind, value)
        if value ~= '' then parts[#parts + 1] = { kind = kind, text = value } end
    end
    local bufStart = 1
    while i <= n do
        local matchedEnd
        if text:sub(i, i) == '|' then
            local c1, c2 = text:sub(i, i + 1), text:sub(i, i + 9)
            if c2:match('^|c%x%x%x%x%x%x%x%x$') then
                matchedEnd = i + 9
            elseif c1 == '|r' then
                matchedEnd = i + 1
            elseif c1 == '|H' then
                local _, linkEnd = text:find('^|H.-|h.-|h', i)
                if linkEnd then matchedEnd = linkEnd end
            elseif c1 == '|T' then
                local _, texEnd = text:find('^|T.-|t', i)
                if texEnd then matchedEnd = texEnd end
            end
        elseif text:sub(i, i) == '{' then
            local _, iconEnd = text:find('^{[A-Za-z0-9_]+}', i)
            if iconEnd then matchedEnd = iconEnd end
        end
        if matchedEnd then
            if i > bufStart then push('plain', text:sub(bufStart, i - 1)) end
            push('raw', text:sub(i, matchedEnd))
            i = matchedEnd + 1
            bufStart = i
        else
            i = i + 1
        end
    end
    if bufStart <= n then push('plain', text:sub(bufStart, n)) end
    return parts
end

function Switcher:Convert(text)
    if type(text) ~= 'string' or text == '' then return text end
    local prefix = ''
    local body = text
    local slashCmd = text:match('^(/[A-Za-z0-9]+%s+)')
    if slashCmd then
        prefix = slashCmd
        body = text:sub(#slashCmd + 1)
    end
    if body == '' then return text end

    local parts = splitProtected(body)
    local latin, cyrillic = 0, 0
    for _, part in ipairs(parts) do
        if part.kind == 'plain' then
            local i = 1
            while i <= #part.text do
                local ch, nxt = nextUtf8(part.text, i)
                if isLatin(ch) then latin = latin + 1
                elseif isCyrillic(ch) then cyrillic = cyrillic + 1 end
                i = nxt
            end
        end
    end

    local map = cyrillic > latin and UK_TO_EN or EN_TO_UK
    local out = { prefix }
    for _, part in ipairs(parts) do
        if part.kind == 'raw' then
            out[#out + 1] = part.text
        else
            local i = 1
            while i <= #part.text do
                local ch, nxt = nextUtf8(part.text, i)
                out[#out + 1] = map[ch] or ch
                i = nxt
            end
        end
    end
    return table.concat(out)
end

local function isEnabled()
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) ~= 'table' or settings.chatLayoutSwitcher ~= false
end

local hooked = {}
local function hookEditBox(box)
    if type(box) ~= 'table' or hooked[box] or type(box.HookScript) ~= 'function' then return end
    hooked[box] = true
    box:HookScript('OnKeyDown', function(self, key)
        if not isEnabled() then return end
        local ctrl = type(IsControlKeyDown) == 'function' and IsControlKeyDown()
        local alt = type(IsAltKeyDown) == 'function' and IsAltKeyDown()
        local shift = type(IsShiftKeyDown) == 'function' and IsShiftKeyDown()
        if not ctrl or alt or shift then return end
        if key ~= 'L' and key ~= 'l' then return end
        if type(self.GetText) ~= 'function' or type(self.SetText) ~= 'function' then return end
        local current = self:GetText()
        if type(current) ~= 'string' or current == '' then return end
        local converted = Switcher:Convert(current)
        if converted ~= current then
            self:SetText(converted)
            if type(self.SetCursorPosition) == 'function' then
                self:SetCursorPosition(#converted)
            end
        end
    end)
end

function Switcher:HookEditBoxes()
    local count = type(NUM_CHAT_WINDOWS) == 'number' and NUM_CHAT_WINDOWS or 10
    for i = 1, count do
        hookEditBox(_G['ChatFrame' .. i .. 'EditBox'])
    end
    if type(ChatEdit_GetActiveWindow) == 'function' then
        hookEditBox(ChatEdit_GetActiveWindow())
    end
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', function()
    Switcher:HookEditBoxes()
end)
Switcher:HookEditBoxes()
