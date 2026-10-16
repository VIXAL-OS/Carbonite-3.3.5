-- Quest Share: a Share button on Carbonite's quest window (Carbonite only had it in its lists' right-click menus,
-- among a dozen others), and under the window, for the selected quest, each party member: already on it, or why the
-- server will refuse it (their level below the quest's minimum, over its max level, a class it isn't for). After a
-- share, from anywhere (the window, the watch list's menu, Blizzard's log), what the server answered for each of them
-- replaces that; refusals also show in red in the middle of the screen ("it's difficult to find the share quest
-- button, and it's not immediately obvious when someone isn't eligible for a shared quest", the user, 2026-10-15).
--
-- The minimum level comes from Carbonite's quest database; the max level and classes from the server's rules that
-- Carbonite carries (Nx.NotYetRules, AzerothCore's quest_template_addon). A previous quest in the chain can't be
-- checked for someone else (their finished quests aren't known here), so it's only named.

local RED, ORANGE, GREEN, GREY, YELLOW = "|cffff4040", "|cffffb040", "|cff40ff40", "|cff9d9d9d", "|cffffd200"

-- The server's answers to a share (ERR_QUEST_PUSH_<suffix>), each: what to show, its colour, and how loud
-- (2: refused, red in the middle of the screen with a sound; 1: in the middle of the screen; 0: only in the list).
local RESULTS = {
    ACCEPTED_S = { "accepted", GREEN, 1 },
    SUCCESS_S = { "sent, waiting for them", GREY, 0 },
    INVALID_S = { "NOT ELIGIBLE", RED, 2 },
    ONQUEST_S = { "already has it", ORANGE, 1 },
    ALREADY_DONE_S = { "already completed it", ORANGE, 1 },
    LOG_FULL_S = { "quest log is full", RED, 2 },
    BUSY_S = { "busy, share again", ORANGE, 1 },
    DECLINED_S = { "declined", ORANGE, 1 },
    DEAD_S = { "dead", ORANGE, 1 },
    NOT_DAILY_S = { "can't take this daily", RED, 2 },
    TIMER_EXPIRED_S = { "too late: the quest's timer ran out", RED, 2 },
    NOT_IN_PARTY_S = { "not in your party", RED, 2 },
    DIFFERENT_SERVER_DAILY_S = { "already did this daily today", RED, 2 },
    TOO_FAR_S = { "too far away", RED, 2 },
}

local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32, SHAMAN = 64,
                    MAGE = 128, WARLOCK = 256, DRUID = 1024 }

local patterns = {}           -- { Lua pattern capturing the name, its RESULTS entry }
local shared = { title = nil, at = -1000, answers = {} } -- the last share: its quest, when, each member's answer
local button, strip, driver
local lines = {}
local lastMessage, lastMessageAt = nil, 0

-- A global string ("%s is not eligible for that quest") as a pattern capturing the name.
local function Pattern(fmt)
    local p = fmt:gsub("%%%d?%$?s", "\001")
    p = p:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\001", "(.+)")
    return "^" .. p .. "$"
end

local function BuildPatterns()
    for suffix, result in pairs(RESULTS) do
        local fmt = _G["ERR_QUEST_PUSH_" .. suffix]
        if type(fmt) == "string" then patterns[#patterns + 1] = { Pattern(fmt), result } end
    end
    -- Any other share answer this client knows, shown as the game words it.
    for key, fmt in pairs(_G) do
        if type(key) == "string" and type(fmt) == "string" and key:sub(1, 15) == "ERR_QUEST_PUSH_" and
           not RESULTS[key:sub(16)] and fmt:find("%%%d?%$?s") then
            patterns[#patterns + 1] = { Pattern(fmt), { nil, ORANGE, 1 } }
        end
    end
end

-- The quest at a log index: its title, level and id (nil for a header or nothing).
local function QuestAt(index)
    if not index or index < 1 then return nil end
    local title, level, _, _, isHeader = GetQuestLogTitle(index)
    if not title or isHeader then return nil end
    local link = GetQuestLink(index)
    local id = link and tonumber(link:match("quest:(%d+)"))
    return title, level, id
end

local function CarboniteQuest(id)
    local que = Nx and Nx.Que
    local q = id and que and que.ITQ and que.ITQ[id]
    if not q or not que.Unp then return nil end
    return que, q
end

local function MinLevel(id)
    local que, q = CarboniteQuest(id)
    if not que then return nil end
    local ok, _, _, _, min = pcall(que.Unp, que, q[1])
    min = ok and tonumber(min) or nil
    return (min and min > 0) and min or nil
end

local function QuestName(id)
    local que, q = CarboniteQuest(id)
    if que then
        local ok, name = pcall(que.Unp, que, q[1])
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "quest " .. id
end

-- From the server's rules: max level, class mask, and the first previous quest (negative: only needs to be taken).
local function Rules(id)
    local s = id and Nx and Nx.NotYetRules and Nx.NotYetRules[id]
    if type(s) ~= "string" then return nil end
    local prev = s:match("p([%-%d,]+)")
    return tonumber(s:match("m(%d+)")), tonumber(s:match("c(%d+)")), prev and tonumber(prev:match("(%-?%d+)"))
end

-- Before a share: what's known about whether a party member can take the quest.
local function Forecast(index, id, unit)
    if not UnitIsConnected(unit) then return "offline", GREY end
    if IsUnitOnQuest(index, unit) then return "already has it", GREY end
    local level = UnitLevel(unit) or 0
    local min = MinLevel(id)
    if min and level > 0 and level < min then return "can't take it: needs level " .. min, RED end
    local max, classes, prev = Rules(id)
    if max and level > max then return "can't take it: max level " .. max, RED end
    if classes then
        local _, class = UnitClass(unit)
        local mask = class and CLASS_BIT[class]
        if mask and bit.band(classes, mask) == 0 then return "can't take it: not for their class", RED end
    end
    if prev then
        return "can take it" .. GREY .. (prev > 0 and " if they've done " or " if they've started ") .. QuestName(math.abs(prev)), GREEN
    end
    return "can take it", GREEN
end

local function Place(height)
    local win = strip:GetParent()
    local below = (win:GetBottom() or 1000) > height + 4
    if strip.below ~= below then
        strip:ClearAllPoints()
        if below then
            strip:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, -1)
            strip:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", 0, -1)
        else
            strip:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 0, 1)
            strip:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, 1)
        end
        strip.below = below
    end
    strip:SetHeight(height)
end

local function Refresh()
    if not button then return end
    local index = GetQuestLogSelection()
    local title, _, id = QuestAt(index)
    local members = GetNumPartyMembers()
    local pushable = title and GetQuestLogPushable()
    if title and members > 0 and pushable then button:Enable() else button:Disable() end
    if not title or members == 0 then strip:Hide() return end

    local n = 0
    local function Line(text)
        n = n + 1
        local fs = lines[n]
        if not fs then
            fs = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetHeight(14)
            fs:SetPoint("TOPLEFT", strip, "TOPLEFT", 8, -6 - (n - 1) * 14)
            fs:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -8, -6 - (n - 1) * 14)
            lines[n] = fs
        end
        fs:SetText(text)
        fs:Show()
    end
    local answered = shared.title == title and GetTime() - shared.at < 300
    if not pushable then
        Line(RED .. "This quest can't be shared.|r")
    else
        Line(YELLOW .. (answered and "Shared: " or "Before you share: ") .. "|r" .. title)
    end
    for i = 1, members do
        local unit = "party" .. i
        local name = UnitName(unit) or unit
        local answer = answered and shared.answers[name]
        local text, colour
        if answer then
            text, colour = answer[1], answer[2]
        else
            text, colour = Forecast(index, id, unit)
        end
        Line(name .. " (" .. (UnitLevel(unit) or "?") .. "): " .. colour .. text .. "|r")
    end
    for i = n + 1, #lines do lines[i]:Hide() end
    Place(12 + n * 14)
    strip:Show()
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local title = QuestAt(GetQuestLogSelection())
    if not title then
        GameTooltip:SetText("Share quest")
        GameTooltip:AddLine("Pick a quest in the list first.", 1, 0.4, 0.4)
    elseif GetNumPartyMembers() == 0 then
        GameTooltip:SetText("Share quest")
        GameTooltip:AddLine("You need to be in a party.", 1, 0.4, 0.4)
    elseif not GetQuestLogPushable() then
        GameTooltip:SetText("Share quest")
        GameTooltip:AddLine("This quest can't be shared.", 1, 0.4, 0.4)
    else
        GameTooltip:SetText("Share: " .. title)
        GameTooltip:AddLine("Under the quest window: who can take it, then what each of them answered.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function Attach()
    if button then return true end
    local list = Nx and Nx.Que and Nx.Que.Lis
    local bar = list and list.Bar and list.Bar.Frm
    local win = list and list.Win1 and list.Win1.Frm
    if not bar or not win then return false end

    button = CreateFrame("Button", "QuestShareButton", bar, "UIPanelButtonTemplate")
    button:SetWidth(92)
    button:SetHeight(math.max(16, (bar:GetHeight() or 20) - 2))
    button:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    button:SetFrameLevel(bar:GetFrameLevel() + 10)
    button:SetText("Share quest")
    button:SetScript("OnClick", function()
        if GetQuestLogSelection() > 0 then QuestLogPushQuest() end
    end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    strip = CreateFrame("Frame", nil, win)
    strip:SetBackdrop({ bgFile = "Interface\\Buttons\\White8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    strip:SetBackdropColor(0, 0, 0, 0.85)
    strip:SetBackdropBorderColor(0.6, 0.6, 0.8, 1)
    strip:Hide()

    -- Kept fresh while the window is open (the strip itself hides when there's nothing to show).
    driver = CreateFrame("Frame", nil, win)
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.25 then elapsed = 0 Refresh() end
    end)
    Refresh()
    return true
end

-- Every share, from anywhere: the quest it was, and the answers start over.
hooksecurefunc("QuestLogPushQuest", function(index)
    shared.title = QuestAt(index or GetQuestLogSelection())
    shared.at = GetTime()
    shared.answers = {}
end)

local function OnMessage(msg)
    if msg == lastMessage and GetTime() - lastMessageAt < 0.5 then return end -- (as chat and as a screen message)
    for i = 1, #patterns do
        local who = msg:match(patterns[i][1])
        if who then
            lastMessage, lastMessageAt = msg, GetTime()
            local result = patterns[i][2]
            local text = result[1] or msg
            shared.answers[who] = { text, result[2] }
            shared.at = GetTime()
            if result[3] >= 1 then
                local r, g, b = 1, 0.7, 0.25
                if result[3] >= 2 then r, g, b = 1, 0.25, 0.25 elseif result[2] == GREEN then r, g, b = 0.25, 1, 0.25 end
                UIErrorsFrame:AddMessage(who .. ": " .. text .. (shared.title and (" (" .. shared.title .. ")") or ""), r, g, b)
                if result[3] >= 2 then PlaySound("igQuestFailed") end
            end
            if button then Refresh() end
            return
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_LOGIN" then
        BuildPatterns()
        if Nx and Nx.Que and Nx.Que.Lis and not Attach() then hooksecurefunc(Nx.Que.Lis, "Ope", Attach) end
        return
    end
    if type(msg) == "string" and #patterns > 0 then OnMessage(msg) end
end)
