-- KazWQUpgrades: Gear upgrade indicators for WorldQuestsList
-- Hooks WQL's update cycle and shows a green arrow next to gear rewards that are upgrades

local KazUtil = LibStub("KazUtil-1.0")
local Print = KazUtil.CreatePrinter("KazWQUpgrades")

-- Slot mapping: INVTYPE string -> equipment slot ID(s)
local INVTYPE_SLOTS = {
    INVTYPE_HEAD = {1},
    INVTYPE_NECK = {2},
    INVTYPE_SHOULDER = {3},
    INVTYPE_BODY = {4},
    INVTYPE_CHEST = {5},
    INVTYPE_ROBE = {5},
    INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7},
    INVTYPE_FEET = {8},
    INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10},
    INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17},
    INVTYPE_SHIELD = {17},
    INVTYPE_2HWEAPON = {16},
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_HOLDABLE = {17},
    INVTYPE_RANGED = {16},
    INVTYPE_RANGEDRIGHT = {16},
}

-- Cache: questID -> true/false (nil = not checked yet or data not ready)
local upgradeCache = {}
local enabled = true

-- Check if a quest reward is a gear upgrade
local function IsUpgrade(questID)
    local cached = upgradeCache[questID]
    if cached == true or cached == false then
        return cached
    end

    local numRewards = GetNumQuestLogRewards(questID)
    if numRewards == 0 then
        return false
    end

    local _, _, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
    if not itemID then
        return false
    end

    local _, _, _, equipSlot = C_Item.GetItemInfoInstant(itemID)
    if not equipSlot or equipSlot == "" then
        upgradeCache[questID] = false
        return false
    end

    local slots = INVTYPE_SLOTS[equipSlot]
    if not slots then
        upgradeCache[questID] = false
        return false
    end

    local itemLink = GetQuestLogItemLink("reward", 1, questID)
    if not itemLink then
        return false
    end

    local rewardIlvl = C_Item.GetDetailedItemLevelInfo(itemLink)
    if not rewardIlvl then
        return false
    end

    -- Compare against equipped items in relevant slots
    -- For dual slots (rings, trinkets, 1H weapons): upgrade if beats the LOWER of the two
    local lowestEquipped = math.huge
    for _, slotID in ipairs(slots) do
        local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
        if C_Item.DoesItemExist(itemLoc) then
            local equippedIlvl = C_Item.GetCurrentItemLevel(itemLoc)
            if equippedIlvl and equippedIlvl < lowestEquipped then
                lowestEquipped = equippedIlvl
            end
        else
            lowestEquipped = 0
            break
        end
    end

    local isUpgrade = rewardIlvl > lowestEquipped
    upgradeCache[questID] = isUpgrade
    return isUpgrade
end

-- Lazy-create the green arrow indicator on a WQL line
local function EnsureIndicator(line)
    if line.kazUpgradeIcon then
        return line.kazUpgradeIcon
    end

    local icon = line:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", line.reward, "RIGHT", 2, 0)
    icon:SetAtlas("bags-greenarrow")
    icon:Hide()

    line.kazUpgradeIcon = icon
    return icon
end

-- Scan visible WQL lines and show/hide upgrade arrows
local function ScanLines()
    if not enabled then return end

    local lines = WorldQuestList and WorldQuestList.l
    if not lines then return end

    for i, line in ipairs(lines) do
        if line:IsShown() and line.questID and line.reward then
            local icon = EnsureIndicator(line)
            local ok, result = pcall(IsUpgrade, line.questID)
            if ok and result then
                icon:Show()
            else
                icon:Hide()
            end
        elseif line.kazUpgradeIcon then
            line.kazUpgradeIcon:Hide()
        end
    end
end

-- Replace WorldQuestList.UpdateList with a wrapper so ALL calls go through our hook.
-- WQL internally calls the local WorldQuestList_Update() directly, which bypasses
-- hooksecurefunc on the table slot. Wrapping the function itself catches everything.
local originalUpdateList = WorldQuestList.UpdateList
WorldQuestList.UpdateList = function(...)
    originalUpdateList(...)
    ScanLines()
end

-- Also hook the .8s ticker and other paths that call the local directly.
-- WQL's OnShow and event handlers call WorldQuestList_Update() (the local),
-- which does NOT go through WorldQuestList.UpdateList. Hook OnShow to catch those.
if WorldQuestList.C then
    WorldQuestList:HookScript("OnShow", function()
        C_Timer.After(0.1, ScanLines)
    end)
end

-- Wipe cache when gear changes
local _, handlers, register = KazUtil.CreateEventHandler()
function handlers.PLAYER_EQUIPMENT_CHANGED() wipe(upgradeCache) end
register("PLAYER_EQUIPMENT_CHANGED")

-- Periodic rescan — WQL's internal local calls bypass our wrapper.
-- Light 1s ticker only runs while WQL is visible.
C_Timer.NewTicker(1, function()
    if WorldQuestList and WorldQuestList:IsVisible() then
        ScanLines()
    end
end)

-- Slash commands
local function HandleSlashCommand(msg)
    local cmd = KazUtil.ParseCommand(msg)
    if cmd == "" then
        enabled = not enabled
        Print(enabled and "Enabled" or "Disabled")
        ScanLines()
    end
end

SLASH_KAZWQUPGRADES1 = "/kwq"
SlashCmdList["KAZWQUPGRADES"] = HandleSlashCommand

if KAZ_COMMANDS then
    KAZ_COMMANDS["wq"] = { handler = HandleSlashCommand, alias = "/kwq", desc = "WQ gear upgrade indicators" }
end
