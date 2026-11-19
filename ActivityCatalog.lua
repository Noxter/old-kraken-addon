-- Shared activity names for guild events and Group Finder.
local dungeons = {
    {value='', label='Усі / не вибрано'},
    {value='rfc', label='Вогненна прірва (RFC)', min=13, max=18},
    {value='thanes', label='Зала танів (HoT)', min=13, max=18},
    {value='lordaeron', label='Руїни Лордерона (RoL)', min=15, max=20},
    {value='wc', label='Печери Стогонів (WC)', min=17, max=24},
    {value='deadmines', label='Мертві копальні (VC)', min=17, max=26},
    {value='sfk', label='Фортеця Темного Ікла (SFK)', min=22, max=30},
    {value='excavation', label='Розкопки: Болотини (ESW)', min=24, max=29},
    {value='bfd', label='Чорні Глибини (BFD)', min=24, max=32},
    {value='stockade', label='В’язниця Штормграда (Stocks)', min=24, max=32},
    {value='dalaran', label='Місто Даларан (CoD)', min=28, max=33},
    {value='gnomeregan', label='Гномреган (Gnome)', min=29, max=38},
    {value='rfk', label='Лабіринти Голкошерстих (RFK)', min=29, max=38},
    {value='sm', label='Червоний монастир (SM)', min=30, max=46},
    {value='drowned', label='Затоплене місто (TDC)', min=35, max=40},
    {value='rfd', label='Кургани Голкошерстих (RFD)', min=37, max=46},
    {value='kroldok', label='Фортеця Крол’док (KS)', min=40, max=45},
    {value='uldaman', label='Ульдаман (Ulda)', min=41, max=51},
    {value='zf', label='Зул’Фаррак (ZF)', min=44, max=54},
    {value='maraudon', label='Мародон (Mara)', min=46, max=55},
    {value='alcaz', label='В’язниця острова Алказ (AIP)', min=48, max=53},
    {value='st', label='Храм Атал’Гаккара (ST)', min=50, max=56},
    {value='brd', label='Глибини Чорної гори (BRD)', min=52, max=60},
    {value='dm', label='Забуте Місто (DM)', min=55, max=60},
    {value='blackmaw', label='Фортеця Чорнощелепих (BMH)', min=55, max=60},
    {value='lbrs', label='Пік Чорної гори (BRS)', min=57, max=60},
    {value='scholo', label='Шоломанса (Scholo)', min=58, max=60},
    {value='strat', label='Стратхольм (Strat)', min=58, max=60},
    {value='shapers', label='Тераса Творця (STr)', min=58, max=60},
}
local raids = {
    {value='', label='Усі / не вибрано'},
    {value='barrowdeeps', label='Курганні глибини (BD)', min=60, max=60},
    {value='hyjalsummit', label='Вершина Гіджала (HS)', min=60, max=60},
    {value='onyxia', label='Лігво Оніксії (Ony)', min=60, max=60},
}
OldKraken.ActivityCatalog = {dungeon=dungeons, raid=raids, roleIcons={
    tank='|TInterface\\AddOns\\OldKraken\\Media\\RoleIcons.tga:16:16:0:0:64:16:0:16:0:16|t',
    healer='|TInterface\\AddOns\\OldKraken\\Media\\RoleIcons.tga:16:16:0:0:64:16:16:32:0:16|t',
    dps='|TInterface\\AddOns\\OldKraken\\Media\\RoleIcons.tga:16:16:0:0:64:16:32:48:0:16|t',
    flex='|TInterface\\AddOns\\OldKraken\\Media\\RoleIcons.tga:16:16:0:0:64:16:48:64:0:16|t',
}}

-- Loading-screen artwork already used by Group Finder; unknown activities use the same fallback.
local activityArt = {
    thanes=7963781, lordaeron=7963782, wc=131882, deadmines=131833, sfk=131869,
    excavation=7963777, bfd=131823, stockade=131870, dalaran=7963775,
    gnomeregan=131841, rfk=131865, sm=131852, drowned=7963741, rfd=131864,
    kroldok=7963780, uldaman=131876, zf=131885, maraudon=131850, alcaz=7963734,
    st=131872, brd=131824, dm=131835, blackmaw=7963784, lbrs=131825,
    scholo=131868, strat=131871, shapers=7963783,
}
local raidArt = {barrowdeeps='BarrowDeeps', hyjalsummit='HyjalSummit', onyxia='Onyxia'}
function OldKraken.ActivityCatalog.SetArtwork(texture, activity)
    local raid=raidArt[activity]
    if raid then
        texture:SetTexture('Interface\\AddOns\\'..OldKraken.name..'\\Media\\Raids\\'..raid..'.tga')
        texture:SetTexCoord(0,1,0,1)
        return
    end
    local art=activityArt[activity] or 7963779
    texture:SetTexture(art)
    if art>=7000000 then texture:SetTexCoord(0.22,0.78,0.22,0.78)
    else texture:SetTexCoord(0.225,0.775,0.25,0.80) end
end

local canonicalTitles = {}
for _, list in ipairs({dungeons, raids}) do
    for _, entry in ipairs(list) do
        if type(entry.value) == 'string' and entry.value ~= '' and type(entry.label) == 'string' then
            local uk = entry.label
            local en = OldKraken.TranslateEn and OldKraken.TranslateEn(uk) or uk
            canonicalTitles[entry.value] = {[uk] = true, [en] = true}
        end
    end
end
OldKraken.ActivityCatalog.canonicalTitles = canonicalTitles
function OldKraken.ActivityCatalog.IsCanonicalTitle(activity, title)
    local set = type(activity) == 'string' and canonicalTitles[activity]
    return type(set) == 'table' and type(title) == 'string' and set[title] == true
end

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(dungeons, 'label')
    OldKraken.LocalizeTable(raids, 'label')
end
