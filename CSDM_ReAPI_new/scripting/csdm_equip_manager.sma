// Copyright © 2016 Vaqtincha

#include <amxmodx>
#include <csdm>
#include <fakemeta>


#define IsPlayerNotUsed(%1)			(g_iPreviousSecondary[%1] == INVALID_INDEX && g_iPreviousPrimary[%1] == INVALID_INDEX)

const CSDM_BUYZONE_KEY	= 71952486

enum equip_data_s
{
	szWeaponName[20],
	szDisplayName[32],
	iAmount,
	TeamName:iTeam,
	WeaponIdType:iWeaponID
}

enum arraylist_e
{
	Array:Autoitems,
	Array:Primary,
	Array:Secondary,
	Array:BotSecondary,
	Array:BotPrimary
}

enum 
{
	BUYZONE_REMOVE,
	BUYZONE_TRIGGER_ON,
	BUYZONE_TRIGGER_OFF
}

new const g_szValidItemNames[][] = 
{
	"","weapon_p228","","weapon_scout","weapon_hegrenade","weapon_xm1014","weapon_c4",
	"weapon_mac10","weapon_aug","weapon_smokegrenade","weapon_elite","weapon_fiveseven","weapon_ump45",
	"weapon_sg550","weapon_galil","weapon_famas","weapon_usp","weapon_glock18","weapon_awp",
	"weapon_mp5navy","weapon_m249","weapon_m3","weapon_m4a1","weapon_tmp","weapon_g3sg1",
	"weapon_flashbang","weapon_deagle","weapon_sg552","weapon_ak47","weapon_knife","weapon_p90",
	"weapon_shield","item_kevlar","item_assaultsuit","item_thighpack","item_longjump"
}

new HookChain:g_hGiveDefaultItems, HookChain:g_hGiveNamedItem
new Array:g_aArrays[arraylist_e], Trie:g_tCheckItemName
new g_iPreviousSecondary[MAX_CLIENTS + 1], g_iPreviousPrimary[MAX_CLIENTS + 1], bool:g_bOpenMenu[MAX_CLIENTS + 1]

new g_iSecondarySection, g_iPrimarySection, g_iBotSecondarySection, g_iBotPrimarySection
new g_iNumPrimary, g_iNumSecondary, g_iNumBotPrimary, g_iNumBotSecondary, g_iNumAutoItems

new g_iEquipMenuID, g_iEquipMenuCB, g_iSecondaryMenuID, g_iPrimaryMenuID
new EquipTypes:g_iEquipMode = EQUIP_MENU, bool:g_bBlockDefaultItems = true
new bool:g_bHasMapParameters, mp_maxmoney

public plugin_init()
{
	register_plugin("CSDM Equip Manager", CSDM_VERSION_STRING, "Vaqtincha")

	register_clcmd("say /guns", "ClCmd_EnableMenu")
	register_clcmd("say guns", "ClCmd_EnableMenu")
	register_clcmd("say_team /guns", "ClCmd_EnableMenu")
	register_clcmd("say_team guns", "ClCmd_EnableMenu")

	DisableHookChain(g_hGiveDefaultItems = RegisterHookChain(RG_CBasePlayer_GiveDefaultItems, "CBasePlayer_GiveDefaultItems", .post = false))
	DisableHookChain(g_hGiveNamedItem = RegisterHookChain(RG_CBasePlayer_GiveNamedItem, "CBasePlayer_GiveNamedItem", .post = true))

	g_bHasMapParameters = bool:rg_find_ent_by_class(NULLENT, "info_map_parameters")
	mp_maxmoney = get_cvar_pointer("mp_maxmoney")
}

public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public plugin_cfg()
{
	BuildMenus()
	CheckForwards()
}

public plugin_end()
{
	if(g_tCheckItemName)
		TrieDestroy(g_tCheckItemName)
}

// API
public EquipTypes:get_equip_mode()
{
	return g_iEquipMode
}

public set_equip_mode(const iNewEquipmode)
{
	g_iEquipMode = EquipTypes:clamp(iNewEquipmode, _:AUTO_EQUIP, _:FREE_BUY)
	CheckForwards()
}


public CSDM_ConfigurationLoad(const ReadTypes:iReadAction)
{
	if(!g_tCheckItemName)
	{
		g_tCheckItemName = TrieCreate()
		for(new iId = 0; iId < sizeof(g_szValidItemNames); iId++)
		{
			TrieSetCell(g_tCheckItemName, g_szValidItemNames[iId], g_szValidItemNames[iId][0] ? iId : 0) // WEAPON_NONE
		}
	}

	g_aArrays[Autoitems] = ArrayCreate(equip_data_s)
	g_aArrays[Secondary] = ArrayCreate(equip_data_s)
	g_aArrays[Primary] = ArrayCreate(equip_data_s)
	g_aArrays[BotSecondary] = ArrayCreate(equip_data_s)
	g_aArrays[BotPrimary] = ArrayCreate(equip_data_s)

	CSDM_RegisterConfig("equip", "ReadCfg_Settings")
	CSDM_RegisterConfig("autoitems", "ReadCfg_AutoItems")
	g_iSecondarySection = CSDM_RegisterConfig("secondary", "ReadCfg_MenuItems")
	g_iPrimarySection = CSDM_RegisterConfig("primary", "ReadCfg_MenuItems")
	g_iBotSecondarySection = CSDM_RegisterConfig("botsecondary", "ReadCfg_BotWeapons")
	g_iBotPrimarySection = CSDM_RegisterConfig("botprimary", "ReadCfg_BotWeapons")
}

public CSDM_ExecuteCVarValues()
{
	if(g_iEquipMode == FREE_BUY)
	{
		set_cvar_num("mp_buytime", -1)
	}
}

public CSDM_RestartRound(const bool:bNewGame)
{
	if(!bNewGame || !g_bBlockDefaultItems)
		return

	new iPlayers[32], iCount, pPlayer
	get_players(iPlayers, iCount, "ah")
	for(--iCount; iCount >= 0; iCount--)
	{
		pPlayer = iPlayers[iCount]
		if(get_member(pPlayer, m_bNotKilled))
		{
			rg_remove_all_items(pPlayer)
		}
	}
}

public client_putinserver(pPlayer)
{
	g_iPreviousSecondary[pPlayer] = g_iPreviousPrimary[pPlayer] = INVALID_INDEX
	g_bOpenMenu[pPlayer] = true
}

public ClCmd_EnableMenu(const pPlayer)
{
	if(g_iEquipMode != EQUIP_MENU)
		return PLUGIN_HANDLED

	if(IsPlayerNotUsed(pPlayer) && is_user_alive(pPlayer))
	{
		menu_display(pPlayer, g_iEquipMenuID)
		return PLUGIN_HANDLED
	}
	if(g_bOpenMenu[pPlayer])
	{
		CSDM_PrintChat(pPlayer, RED, "^4[CSDM] ^3Your equip menu is already enabled!")
		return PLUGIN_HANDLED
	}
	CSDM_PrintChat(pPlayer, BLUE, "^4[CSDM] ^3Gun menu will be re-enabled next spawn.")
	g_bOpenMenu[pPlayer] = true

	return PLUGIN_HANDLED
}

public CSDM_PlayerSpawned(const pPlayer, const bool:bIsBot, const iNumSpawns)
{
	if(g_iEquipMode == FREE_BUY)
	{
		rg_add_account(pPlayer, get_pcvar_num(mp_maxmoney), AS_SET)
		if(g_bBlockDefaultItems) // already gived by default ?
		{
			rg_give_item(pPlayer, "weapon_knife")
		}
		return
	}

	GiveAutoItems(pPlayer)

	if(g_iEquipMode == AUTO_EQUIP)  // only autoitems ?
		return

	if(bIsBot)
	{
		RandomWeapons(pPlayer, g_aArrays[BotSecondary], g_iNumBotSecondary)
		RandomWeapons(pPlayer, g_aArrays[BotPrimary], g_iNumBotPrimary)
		return
	}

	if(g_iEquipMode == EQUIP_MENU)
	{
		if(g_bOpenMenu[pPlayer])
		{
			menu_display(pPlayer, g_iEquipMenuID)
		}
		else
		{
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])
		}
	}
	else if(g_iEquipMode == RANDOM_WEAPONS)
	{
		RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
		RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)
	}
}

// CBasePlayer
public CBasePlayer_GiveDefaultItems(const pPlayer)
{
	return HC_SUPERCEDE
}

public CBasePlayer_GiveNamedItem(const pPlayer, const pszName[])
{
	if(!pszName[0] || !(pszName[0] == 'w' && pszName[6] == '_')) // weapon_
		return HC_CONTINUE

	new WeaponIdType:iId = any:get_weaponid(pszName)
	if(IsValidWeaponID(iId))
	{
		rg_set_user_bpammo(pPlayer, iId, g_iMaxBPAmmo[iId])
	}

	return HC_CONTINUE
}

// Menus
public EquipMenuHandler(const pPlayer, const iMenu, const iItem)
{
	if(iItem == MENU_EXIT || iItem < 0)
		return PLUGIN_HANDLED

	new szNum[3], iAccess, hCallback
	menu_item_getinfo(iMenu, iItem, iAccess, szNum, charsmax(szNum), _, _, hCallback)

	switch(str_to_num(szNum))
	{
		case 1: menu_display(pPlayer, g_iNumSecondary ? g_iSecondaryMenuID : g_iPrimaryMenuID)
		case 2: 
		{
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])
		}
		case 3:
		{
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])

			CSDM_PrintChat(pPlayer, GREY, "^4[CSDM] ^3say ^1guns ^3to re-enable the gun menu.")
			g_bOpenMenu[pPlayer] = false
		}
		case 4:
		{
			g_iPreviousSecondary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
			g_iPreviousPrimary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)
		}
	}

	return PLUGIN_HANDLED
}

public EquipMenuCallback(const pPlayer, const iMenu, const iItem)
{
	if(iItem < 0)
		return PLUGIN_HANDLED

	new szNum[3], iAccess, hCallback
	menu_item_getinfo(iMenu, iItem, iAccess, szNum, charsmax(szNum), _, _, hCallback)
	
	if(!g_iNumSecondary && !g_iNumPrimary)
		return ITEM_DISABLED

	if((szNum[0] == '2' || szNum[0] == '3') && IsPlayerNotUsed(pPlayer))
		return ITEM_DISABLED
	
	return ITEM_IGNORE
}

public SecondaryMenuHandler(const pPlayer, const iMenu, const iItem)
{
	if(iItem == MENU_EXIT || iItem < 0)
		return PLUGIN_HANDLED

	new szNum[3], iAccess, hCallback
	menu_item_getinfo(iMenu, iItem, iAccess, szNum, charsmax(szNum), _, _, hCallback)

	new eWeaponData[equip_data_s], iItemIndex = str_to_num(szNum)
	ArrayGetArray(g_aArrays[Secondary], iItemIndex, eWeaponData)

	GiveWeapon(pPlayer, eWeaponData)
	g_iPreviousSecondary[pPlayer] = iItemIndex

	menu_display(pPlayer, g_iPrimaryMenuID)
	return PLUGIN_HANDLED
}

public PrimaryMenuHandler(const pPlayer, const iMenu, const iItem)
{
	if(iItem == MENU_EXIT || iItem < 0)
		return PLUGIN_HANDLED
	
	new szNum[3], iAccess, hCallback
	menu_item_getinfo(iMenu, iItem, iAccess, szNum, charsmax(szNum), _, _, hCallback)

	new eWeaponData[equip_data_s], iItemIndex = str_to_num(szNum)
	ArrayGetArray(g_aArrays[Primary], iItemIndex, eWeaponData)

	GiveWeapon(pPlayer, eWeaponData)
	g_iPreviousPrimary[pPlayer] = iItemIndex

	return PLUGIN_HANDLED
}

// Config callbacks
public ReadCfg_Settings(const szLineData[], const iSectionID)
{
	new szKey[MAX_KEY_LEN], szValue[MAX_VALUE_LEN], szSign[2]
	if(ParseConfigKey(szLineData, szKey, szSign, szValue))
	{
		if(equali(szKey, "equip_mode"))
		{
			g_iEquipMode = EquipTypes:clamp(str_to_num(szValue), _:AUTO_EQUIP, _:FREE_BUY)
		}
		else if(equali(szKey, "block_default_items"))
		{
			g_bBlockDefaultItems = bool:(str_to_num(szValue))
		}
	}
}

public ReadCfg_AutoItems(const szLineData[], const iSectionID)
{
	new szClassName[20], szTeam[4], szAmount[4], eWeaponData[equip_data_s]
	if(parse(szLineData, szClassName, charsmax(szClassName), szTeam, charsmax(szTeam), szAmount, charsmax(szAmount)) != 3)
		return

	strtolower(szClassName)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szClassName)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szClassName)
	eWeaponData[iTeam] = _:(szTeam[0] == 't' ? TEAM_TERRORIST : szTeam[0] == 'c' ? TEAM_CT : TEAM_UNASSIGNED)
	eWeaponData[iAmount] = str_to_num(szAmount)

	ArrayPushArray(g_aArrays[Autoitems], eWeaponData)
	g_iNumAutoItems++
}

public ReadCfg_BotWeapons(szLineData[], const iSectionID)
{
	new eWeaponData[equip_data_s]

	strtolower(szLineData)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szLineData)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szLineData)

	if(iSectionID == g_iBotSecondarySection)
	{
		ArrayPushArray(g_aArrays[BotSecondary], eWeaponData)
		g_iNumBotSecondary++
	}
	else if(iSectionID == g_iBotPrimarySection)
	{
		ArrayPushArray(g_aArrays[BotPrimary], eWeaponData)
		g_iNumBotPrimary++
	}
}

public ReadCfg_MenuItems(const szLineData[], const iSectionID)
{
	new szClassName[20], szMenuText[32], eWeaponData[equip_data_s]
	if(parse(szLineData, szClassName, charsmax(szClassName), szMenuText, charsmax(szMenuText)) != 2)
		return

	strtolower(szClassName)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szClassName)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szClassName)
	copy(eWeaponData[szDisplayName], charsmax(eWeaponData[szDisplayName]), szMenuText)

	if(iSectionID == g_iSecondarySection)
	{
		ArrayPushArray(g_aArrays[Secondary], eWeaponData)
		g_iNumSecondary++
	}
	else if(iSectionID == g_iPrimarySection)
	{
		ArrayPushArray(g_aArrays[Primary], eWeaponData)
		g_iNumPrimary++
	}
}

// Functions
PreviousWeapons(const pPlayer, const Array:aArrayName, const iItemIndex)
{
	if(iItemIndex != INVALID_INDEX)
	{
		new eWeaponData[equip_data_s]
		ArrayGetArray(aArrayName, iItemIndex, eWeaponData)
		GiveWeapon(pPlayer, eWeaponData)
	}
}

RandomWeapons(const pPlayer, const Array:aArrayName, const iArraySize)
{
	if(!iArraySize)
		return INVALID_INDEX
	
	new eWeaponData[equip_data_s], iRand = random(iArraySize)
	ArrayGetArray(aArrayName, iRand, eWeaponData)
	GiveWeapon(pPlayer, eWeaponData)
	return iRand
}

GiveAutoItems(const pPlayer)
{
	if(!g_iNumAutoItems)
		return

	new eWeaponData[equip_data_s], i, TeamName:iPlayerTeam = get_member(pPlayer, m_iTeam)
	for(i = 0; i < g_iNumAutoItems; i++)
	{
		ArrayGetArray(g_aArrays[Autoitems], i, eWeaponData)
		if(iPlayerTeam == eWeaponData[iTeam] || eWeaponData[iTeam] == TEAM_UNASSIGNED)
		{
			GiveWeapon(pPlayer, eWeaponData)
		}
	}
}

GiveWeapon(const pPlayer, eData[equip_data_s])
{
	new WeaponIdType:iId = eData[iWeaponID]
	rg_give_item_ex(pPlayer, eData[szWeaponName], iId, (GRENADE_BS & 1<<any:iId) ? GT_APPEND : GT_REPLACE)

	if(eData[iAmount] && eData[szWeaponName][0] == 'i' && (eData[szWeaponName][5] == 'a' || eData[szWeaponName][5] == 'k'))
	{
		set_entvar(pPlayer, var_armorvalue, float(eData[iAmount]))
	}
	else if(IsValidWeaponID(iId))
	{
		rg_set_user_bpammo(pPlayer, iId, eData[iAmount] ? eData[iAmount] : g_iMaxBPAmmo[iId])
	}
}

WeaponIdType:GetWeaponIndex(const szClassName[])
{
	new WeaponIdType:iId = WEAPON_NONE
	if(!szClassName[0] || !TrieGetCell(g_tCheckItemName, szClassName, iId))
	{
		server_print("[CSDM] WARNING: Invalid item name ^"%s^" will be skipped!", szClassName)
		return WEAPON_NONE
	}
	return iId
}

BuildMenus()
{
	g_iEquipMenuID = MenuCrate("Equip Menu", "EquipMenuHandler", bool:(!g_iNumSecondary && !g_iNumPrimary))
	g_iEquipMenuCB = menu_makecallback("EquipMenuCallback")

	menu_additem(g_iEquipMenuID, "New weapons", "1", .callback = g_iEquipMenuCB)
	menu_additem(g_iEquipMenuID, "Previous setup", "2", .callback = g_iEquipMenuCB)
	menu_additem(g_iEquipMenuID, "2+Don't show menu again^n", "3", .callback = g_iEquipMenuCB)
	menu_additem(g_iEquipMenuID, "Random selection", "4", .callback = g_iEquipMenuCB)

	g_iSecondaryMenuID = MenuCrate("Secondary Weapons", "SecondaryMenuHandler")
	AddItemsToMenu(g_iSecondaryMenuID, g_aArrays[Secondary], g_iNumSecondary)

	g_iPrimaryMenuID = MenuCrate("Primary Weapons", "PrimaryMenuHandler")
	AddItemsToMenu(g_iPrimaryMenuID, g_aArrays[Primary], g_iNumPrimary)
}

MenuCrate(const szTitle[], const szHandler[], const bAddExitKey = false)
{
	new iMenu = menu_create(szTitle, szHandler)
	if(!bAddExitKey)
	{
		menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
	}
	menu_setprop(iMenu, MPROP_NUMBER_COLOR, "\y")
	return iMenu
}

AddItemsToMenu(const iMenu, const Array:aArrayName, const iArraySize)
{
	if(!iArraySize)
		return

	new eWeaponData[equip_data_s], szNum[3], i
	for(i = 0; i < iArraySize; i++) 
	{
		ArrayGetArray(aArrayName, i, eWeaponData)
		num_to_str(i, szNum, charsmax(szNum))
		menu_additem(iMenu, eWeaponData[szDisplayName], szNum)
	}
}

CheckForwards()
{
	if(g_bBlockDefaultItems)
	{
		EnableHookChain(g_hGiveDefaultItems)
	}
	else
	{
		DisableHookChain(g_hGiveDefaultItems)
	}

	if(g_iEquipMode == FREE_BUY)
	{
		EnableHookChain(g_hGiveNamedItem)
		if(!SetStateBuyZone(BUYZONE_TRIGGER_ON))
		{
			CreateBuyZone()
		}
		if(g_bHasMapParameters)
		{
			set_member_game(m_bCTCantBuy, false)
			set_member_game(m_bTCantBuy, false)
		}
	}
	else
	{
		DisableHookChain(g_hGiveNamedItem)
		SetStateBuyZone(BUYZONE_TRIGGER_OFF)
		if(g_bHasMapParameters)
		{
			set_member_game(m_bCTCantBuy, true)
			set_member_game(m_bTCantBuy, true)
		}
	}
}

CreateBuyZone()
{
	new pEntity = rg_create_entity("func_buyzone")
	SPAWN_ENTITY(pEntity)

	if(!is_nullent(pEntity))
	{
		SET_SIZE(pEntity, Vector(-8191, -8191, -8191), Vector(8191, 8191, 8191))
		SET_ORIGIN(pEntity, VECTOR_ZERO)
		SetEntityKeyID(pEntity, CSDM_BUYZONE_KEY)
		return pEntity
	}
	return NULLENT
}

bool:SetStateBuyZone(const iAction)
{
	new pEntity = NULLENT
	while((pEntity = rg_find_ent_by_class(pEntity, "func_buyzone")))
	{
		if(GetEntityKeyID(pEntity) != CSDM_BUYZONE_KEY)
			continue

		switch(iAction)
		{
			case BUYZONE_REMOVE: REMOVE_ENTITY(pEntity)
			case BUYZONE_TRIGGER_ON: set_entvar(pEntity, var_solid, SOLID_TRIGGER)
			case BUYZONE_TRIGGER_OFF: set_entvar(pEntity, var_solid, SOLID_NOT)
		}
		return true
	}
	return false
}


