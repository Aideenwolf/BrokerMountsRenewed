local LDB_NAME = "BrokerMountsRenewed"
local ADDON_LABEL = "BrokerMountsRenewed"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark.blp"
local IGNORED_SPELL_ID = 55164 -- Swift Spectral Gryphon

local parent = CreateFrame("Frame")
local dropdown = CreateFrame("Frame", "BrokerMountsRenewedDropDown", UIParent, "UIDropDownMenuTemplate")

local broker = nil

local CATEGORY_LABELS = {
	favorites = "Favorites",
	utility = "Utility Mounts",
	flying = "Flying Mounts",
	ground = "Ground Mounts",
	water = "Water Mounts",
	all = "All",
}

local CATEGORY_ORDER = {
	"favorites",
	"utility",
	"flying",
	"ground",
	"water",
	"all",
}

local MOUNT_TYPE_BY_CATEGORY = {
	ground = {
		[230] = true,
		[241] = true,
		[284] = true,
	},
	water = {
		[231] = true,
		[232] = true,
		[254] = true,
		[269] = true,
	},
}

local UTILITY_MOUNT_NAMES = {
	["grand expedition yak"] = true,
	["grand black war mammoth"] = true,
	["chauffeured mekgineer's chopper"] = true,
	["trader's gilded brutosaur"] = true,
	["mighty caravan brutosaur"] = true,
}

local function IsMountAllowedForPlayer(faction)
	local playerFaction = UnitFactionGroup("player")
	if playerFaction == "Horde" then
		return faction ~= 1
	end
	if playerFaction == "Alliance" then
		return faction ~= 2
	end
	return true
end

local function IsUsableSpell(spellID)
	return spellID and C_Spell.IsSpellUsable(spellID) or false
end

local function IsUtilityMount(name)
	local normalized = name and string.lower(name)
	return normalized and UTILITY_MOUNT_NAMES[normalized] == true or false
end

local function GetMountCategory(mountType)
	if MOUNT_TYPE_BY_CATEGORY.ground[mountType] then
		return "ground"
	end
	if MOUNT_TYPE_BY_CATEGORY.water[mountType] then
		return "water"
	end
	return "flying"
end

local function SetBrokerDisplay(text, icon, isUsable)
	if not broker then
		return
	end

	broker.icon = icon or DEFAULT_ICON
	if text and text ~= "" then
		broker.text = isUsable and text or string.format("|cff848484%s|r", text)
	else
		broker.text = ADDON_LABEL
	end
end

local function TrackLastMount(mount)
	if not mount then
		return
	end

	lastmountIndex = mount.mountID
	lastmountText = mount.name
	lastmountIcon = mount.icon
	lastmountSpell = mount.spellID
end

local function BuildMountRecord(index)
	local name, spellID, icon, active, isUsable, _, isFavorite, _, faction, _, isCollected, mountID = C_MountJournal.GetDisplayedMountInfo(index)
	if not mountID or not isCollected or spellID == IGNORED_SPELL_ID then
		return nil
	end
	if not IsMountAllowedForPlayer(faction) then
		return nil
	end

	local _, _, _, _, mountType = C_MountJournal.GetMountInfoExtraByID(mountID)

	return {
		mountID = mountID,
		name = name,
		spellID = spellID,
		icon = icon,
		active = active,
		isUsable = isUsable and IsUsableSpell(spellID),
		isFavorite = isFavorite,
		isUtility = IsUtilityMount(name),
		category = GetMountCategory(mountType),
	}
end

local function SortMounts(a, b)
	if a.active ~= b.active then
		return a.active
	end
	return a.name < b.name
end

local function CollectMounts()
	local mounts = {
		favorites = {},
		utility = {},
		flying = {},
		ground = {},
		water = {},
		all = {},
	}

	for index = 1, C_MountJournal.GetNumDisplayedMounts() do
		local mount = BuildMountRecord(index)
		if mount then
			table.insert(mounts.all, mount)
			table.insert(mounts[mount.category], mount)
			if mount.isFavorite then
				table.insert(mounts.favorites, mount)
			end
			if mount.isUtility then
				table.insert(mounts.utility, mount)
			end
		end
	end

	for _, key in ipairs(CATEGORY_ORDER) do
		table.sort(mounts[key], SortMounts)
	end

	return mounts
end

local function GetOwnedMountCounts()
	local owned, usable = 0, 0
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local _, spellID, _, _, isUsable, _, _, _, faction, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
		if isCollected and IsMountAllowedForPlayer(faction) and spellID ~= IGNORED_SPELL_ID then
			owned = owned + 1
			if isUsable and IsUsableSpell(spellID) then
				usable = usable + 1
			end
		end
	end
	return owned, usable
end

local function RestoreLastMountDisplay()
	if not lastmountIndex or not lastmountText then
		SetBrokerDisplay(ADDON_LABEL, DEFAULT_ICON, true)
		return
	end

	local _, spellID = C_MountJournal.GetMountInfoByID(lastmountIndex)
	if spellID == IGNORED_SPELL_ID then
		SetBrokerDisplay(ADDON_LABEL, DEFAULT_ICON, true)
		return
	end

	SetBrokerDisplay(lastmountText, lastmountIcon, IsUsableSpell(lastmountSpell or spellID))
end

local function UpdateDisplay()
	local mounts = CollectMounts()
	for _, mount in ipairs(mounts.all) do
		if mount.active then
			TrackLastMount(mount)
			SetBrokerDisplay(mount.name, mount.icon, true)
			return
		end
	end

	RestoreLastMountDisplay()
end

local function SummonMount(mount)
	if not mount then
		return
	end

	C_MountJournal.SummonByID(mount.mountID)
	TrackLastMount(mount)
	SetBrokerDisplay(mount.name, mount.icon, mount.isUsable)
end

local function SummonRandomFromCategory(category)
	local mounts = CollectMounts()[category]
	local usableMounts = {}

	if mounts then
		for _, mount in ipairs(mounts) do
			if mount.isUsable then
				table.insert(usableMounts, mount)
			end
		end
	end

	if #usableMounts == 0 then
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffff00%s:|r No usable mounts in %s.", ADDON_LABEL, CATEGORY_LABELS[category] or category))
		end
		return
	end

	SummonMount(usableMounts[random(#usableMounts)])
end

local function SummonRandomFavoriteByCategory(category)
	local mountsByCategory = CollectMounts()
	local favoritesByMountID = {}
	local eligibleMounts = {}

	for _, mount in ipairs(mountsByCategory.favorites) do
		favoritesByMountID[mount.mountID] = true
	end

	for _, mount in ipairs(mountsByCategory[category] or {}) do
		if favoritesByMountID[mount.mountID] and mount.isUsable then
			table.insert(eligibleMounts, mount)
		end
	end

	if #eligibleMounts == 0 then
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffff00%s:|r No usable favorite mounts in %s.", ADDON_LABEL, CATEGORY_LABELS[category] or category))
		end
		return
	end

	SummonMount(eligibleMounts[random(#eligibleMounts)])
end
local function AddMenuItems(target, mounts)
	if #mounts == 0 then
		table.insert(target, {
			text = "No mounts available",
			notCheckable = true,
			isTitle = true,
		})
		return
	end

	for _, mount in ipairs(mounts) do
		local prefix = mount.active and "|cff00ff00" or (mount.isUsable and "" or "|cff848484")
		local suffix = mount.active and "|r" or (mount.isUsable and "" or "|r")
		table.insert(target, {
			text = string.format("|T%s:16|t %s%s", mount.icon or DEFAULT_ICON, prefix, mount.name) .. suffix,
			notCheckable = true,
			func = function()
				SummonMount(mount)
			end,
		})
	end
end

local function BuildCategoryMenu(category, mounts)
	local items = {
		{
			text = string.format("Random %s", CATEGORY_LABELS[category]),
			notCheckable = true,
			func = function()
				SummonRandomFromCategory(category)
			end,
		},
		{
			text = " ",
			isTitle = true,
			notCheckable = true,
		},
	}
	AddMenuItems(items, mounts)
	return items
end

local function BuildMenu()
	local mountsByCategory = CollectMounts()
	local menu = {
		{
			text = ADDON_LABEL,
			isTitle = true,
			notCheckable = true,
		},
	}

	for _, category in ipairs(CATEGORY_ORDER) do
		table.insert(menu, {
			text = string.format("%s (%d)", CATEGORY_LABELS[category], #mountsByCategory[category]),
			notCheckable = true,
			hasArrow = true,
			menuList = BuildCategoryMenu(category, mountsByCategory[category]),
		})
	end

	table.insert(menu, {
		text = "Cancel",
		notCheckable = true,
		func = CloseDropDownMenus,
	})

	return menu
end

local function InitializeDropdown(_, level, menuList)
    local entries = menuList or BuildMenu()
    for _, entry in ipairs(entries) do
        UIDropDownMenu_AddButton(entry, level)
    end
end

local function ShowMenu()
    GameTooltip:Hide()
    UIDropDownMenu_Initialize(dropdown, InitializeDropdown, "MENU")
    ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
end

local function ShowHelpTooltip(anchor)
    GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(ADDON_LABEL, 0, 1, 1)
    GameTooltip:AddLine("Right Click: Mount Menu", 1, 0.82, 0)
    GameTooltip:AddLine("Left Click: Mount or Dismiss", 1, 0.82, 0)
    GameTooltip:AddLine("Shift + Left Click: Favorite - Random Mount", 1, 0.82, 0)
    GameTooltip:AddLine("Alt + Left Click: Favorite - Random Flying Mount", 1, 0.82, 0)
    GameTooltip:AddLine("Ctrl + Left Click: Favorite - Random Ground Mount", 1, 0.82, 0)
    GameTooltip:AddLine("Alt + Right Click: Random Flying Mount", 1, 0.82, 0)
    GameTooltip:AddLine("Ctrl + Right Click: Random Ground Mount", 1, 0.82, 0)
    local owned, usable = GetOwnedMountCounts()
    GameTooltip:AddLine(string.format("Owned: %d  Usable: %d", owned, usable), 0.2, 1, 0.2)
    GameTooltip:Show()
end

local function OnEnter(frame)
    ShowHelpTooltip(frame)
end

local function OnLeave()
    GameTooltip:Hide()
end

local function HandleDefaultClick()
    if IsMounted() then
        C_MountJournal.Dismiss()
    elseif lastmountIndex then
        C_MountJournal.SummonByID(lastmountIndex)
    end
end

local function OnClick(_, button)
	if button == "LeftButton" and IsShiftKeyDown() then
		SummonRandomFromCategory("favorites")
		return
	end

	if button == "LeftButton" and IsAltKeyDown() and not IsControlKeyDown() then
        SummonRandomFavoriteByCategory("flying")
		return
	end

	if button == "LeftButton" and IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown() then
        SummonRandomFavoriteByCategory("ground")
		return
	end

	if button == "LeftButton" and not IsShiftKeyDown() and not IsAltKeyDown() and not IsControlKeyDown() then
		HandleDefaultClick()
		return
	end

	if button == "RightButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
		SummonRandomFromCategory("flying")
		return
	end

	if button == "RightButton" and IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown() then
		SummonRandomFromCategory("ground")
		return
	end

	if button == "RightButton" and not IsShiftKeyDown() and not IsAltKeyDown() and not IsControlKeyDown() then
		ShowMenu()
	end
end

function parent:PLAYER_LOGIN()
	broker = LibStub("LibDataBroker-1.1"):NewDataObject(LDB_NAME, {
		icon = DEFAULT_ICON,
		text = ADDON_LABEL,
		type = "data source",
		OnEnter = OnEnter,
		OnLeave = OnLeave,
		OnClick = OnClick,
	})

	self:RegisterEvent("SPELL_UPDATE_USABLE")
	self:RegisterEvent("COMPANION_UPDATE")
	self:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
	self:RegisterEvent("NEW_MOUNT_ADDED")
	self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	UpdateDisplay()
end

parent.SPELL_UPDATE_USABLE = UpdateDisplay
parent.COMPANION_UPDATE = UpdateDisplay
parent.MOUNT_JOURNAL_USABILITY_CHANGED = UpdateDisplay
parent.NEW_MOUNT_ADDED = UpdateDisplay
parent.PLAYER_MOUNT_DISPLAY_CHANGED = UpdateDisplay
parent.PLAYER_ENTERING_WORLD = UpdateDisplay

parent:SetScript("OnEvent", function(self, event, ...)
	if self[event] then
		self[event](self, ...)
	end
end)
parent:RegisterEvent("PLAYER_LOGIN")





