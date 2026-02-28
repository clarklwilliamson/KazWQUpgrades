-- KazWQUpgrades: Gear upgrade indicators for WorldQuestsList
-- Hooks WQL's update cycle and shows a green arrow next to gear rewards that are upgrades

local ADDON_NAME = "KazWQUpgrades"

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

-- Cache: questID -> true/false/nil (nil = not checked yet)
local upgradeCache = {}
local enabled = true

-- Check if a quest reward is a gear upgrade
local function IsUpgrade(questID)
    if upgradeCache[questID] ~= nil then
        return upgradeCache[questID]
    end

    local numRewards = GetNumQuestLogRewards(questID)
    if numRewards == 0 then
        upgradeCache[questID] = false
        return false
    end

    -- Get the first reward item
    local _, _, _, _, _, itemID = GetQuestLogRewardInfo(1, questID)
    if not itemID then
        upgradeCache[questID] = false
        return false
    end

    -- Check if it's equippable
    local _, _, _, equipSlot = C_Item.GetItemInfoInstant(itemID)
    if not equipSlot then
        upgradeCache[questID] = false
        return false
    end

    local slots = INVTYPE_SLOTS[equipSlot]
    if not slots then
        upgradeCache[questID] = false
        return false
    end

    -- Get reward item level from quest log link
    local itemLink = GetQuestLogItemLink("reward", 1, questID)
    if not itemLink then
        upgradeCache[questID] = false
        return false
    end

    local rewardIlvl = C_Item.GetDetailedItemLevelInfo(itemLink)
    if not rewardIlvl then
        upgradeCache[questID] = false
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
            -- Empty slot = definite upgrade
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

-- Hook WorldQuestList_Update to tag lines with upgrade indicators
hooksecurefunc("WorldQuestList_Update", function()
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
end)

-- Wipe cache when gear changes
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:SetScript("OnEvent", function()
    wipe(upgradeCache)
end)

-- Slash commands
local function HandleSlashCommand(msg)
    msg = (msg or ""):trim():lower()
    if msg == "" then
        enabled = not enabled
        print("|cff00ccffKazWQUpgrades|r: " .. (enabled and "Enabled" or "Disabled"))
        if WorldQuestList and WorldQuestList:IsVisible() and WorldQuestList_Update then
            WorldQuestList_Update()
        end
    end
end

SLASH_KAZWQUPGRADES1 = "/kwq"
SlashCmdList["KAZWQUPGRADES"] = HandleSlashCommand

if KAZ_COMMANDS then
    KAZ_COMMANDS["wq"] = { handler = HandleSlashCommand, alias = "/kwq", desc = "WQ gear upgrade indicators" }
end
