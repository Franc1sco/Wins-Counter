
/*  SM Wins Counter
 *
 *  Copyright (C) 2018 Francisco 'Franc1sco' García and Headline
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sourcemod>
#include <autoexecconfig>
#include <cstrike>

#pragma semicolon 1

new Handle:g_hDatabaseName = INVALID_HANDLE;
new String:g_sDatabaseName[60];

new    Handle:g_hPluginEnabled = INVALID_HANDLE;
new bool:g_bPluginEnabled;

new    Handle:g_hDebug = INVALID_HANDLE;
new bool:g_bDebug;

new Handle:g_hDatabase = INVALID_HANDLE;
new bool:g_bLateLoad;

new bool:ga_bLoaded[MAXPLAYERS + 1] = {false, ...};
new String:ga_sSteamID[MAXPLAYERS + 1][30];
new ga_iClientMVP[MAXPLAYERS +1] = {0, ...};


#define DATA "1.0.1"

public Plugin myinfo =
{
	name = "SM Wins Counter",
	author = "Franc1sco franug & Headline",
	description = "",
	version = DATA,
	url = "http://steamcommunity.com/id/franug"
};

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sError[], err_max)
{
    g_bLateLoad = bLate;
    
    return APLRes_Success;
}

public OnPluginStart()
{
    LoadTranslations("core.phrases");
    LoadTranslations("common.phrases");
    
    AutoExecConfig_SetFile("wins_counter");
    
    g_hDatabaseName = AutoExecConfig_CreateConVar("wincounter_database_name", "storage-local", "Name of the database for the plugin.");
    HookConVarChange(g_hDatabaseName, OnCVarChange);
    GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
    
    g_hPluginEnabled = AutoExecConfig_CreateConVar("wincounter_enabled", "1", "Enable the plugin? (1 = Yes, 0 = No)", FCVAR_NONE, true, 0.0, true, 1.0);
    HookConVarChange(g_hPluginEnabled, OnCVarChange);
    g_bPluginEnabled = GetConVarBool(g_hPluginEnabled);
    
    g_hDebug = AutoExecConfig_CreateConVar("wincounter_debug", "0", "Enable debug logging? (1 = Yes, 0 = No)", FCVAR_NONE, true, 0.0, true, 1.0);
    HookConVarChange(g_hDebug, OnCVarChange);
    g_bDebug = GetConVarBool(g_hDebug);
    
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_team", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    //HookEvent("round_end", Event_RoundEnd);
    
}

public OnCVarChange(Handle:hCVar, const String:sOldValue[], const String:sNewValue[])
{
    if (hCVar == g_hDatabaseName)
    {
        GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
    }
    else if (hCVar == g_hPluginEnabled)
    {
        g_bPluginEnabled = GetConVarBool(g_hPluginEnabled);
    }
    else if (hCVar == g_hDebug)
    {
        g_bDebug = GetConVarBool(g_hDebug);
    }
}

public OnMapStart()
{
    if (g_bPluginEnabled)
    {
        if (g_hDatabase == INVALID_HANDLE)
        {
            SetDBHandle();
        }
        if (g_bLateLoad)
        {
            for (new i = 1; i <= MaxClients; i++)
            {
                if (IsValidClient(i))
                {
                    #if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
                        GetClientAuthId(i, AuthId_Steam2, ga_sSteamID[i], sizeof(ga_sSteamID[]));
                    #else
                        GetClientAuthString(i, ga_sSteamID[i], sizeof(ga_sSteamID[]));
                    #endif
                    if (StrContains(ga_sSteamID[i], "STEAM_", true) != -1)
                    {
                        if (g_bDebug)
                        {
                            Log("table.log","Loading #s for %L", i);
                        }
                        LoadMvpCount(i);
                    }
                    else
                    {
                        if (g_bDebug)
                        {
                            Log("table.log","Refreshing steam ID for client %L", i);
                        }
                        CreateTimer(10.0, RefreshSteamID, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
                    }
                }
            }
        }
    }
}

public Action:RefreshSteamID(Handle:hTimer, any:iUserID)
{
    new client = GetClientOfUserId(iUserID);
    if (!IsValidClient(client))
    {
        return;
    }

    #if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
        GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
    #else
        GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
    #endif
    
    if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //still invalid - retry again
    {
        if (g_bDebug)
        {
            Log("table.log","Re-refreshing steam ID for client %L", client);
        }
        CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        if (g_bDebug)
        {
            Log("table.log","Loading mvpcount for client %L", client);
        }
        LoadMvpCount(client);
    }
}

public OnClientConnected(client)
{
    if (g_bPluginEnabled)
    {
        ga_iClientMVP[client] = 0;
        ga_sSteamID[client] = "";
        ga_bLoaded[client] = false;
    }
}

public OnClientDisconnect(client)
{
    if (g_bPluginEnabled)
    {
        UpdateMvpStar(client);
        ga_iClientMVP[client] = 0;
        ga_sSteamID[client] = "";
        ga_bLoaded[client] = false;
    }
}

UpdateMvpStar(client)
{
    if (ga_bLoaded[client] && !StrEqual(ga_sSteamID[client], "", false))
    {
        decl String:sQuery[300];
        Format(sQuery, sizeof(sQuery), "UPDATE winscounter SET deaths=%i WHERE steamid=\"%s\"", ga_iClientMVP[client], ga_sSteamID[client]);
        SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery, 2);
    }
}

public Action:Event_PlayerSpawn(Handle:hEvent, const String:sName[], bool:bDontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    CreateTimer(0.5, Timer_UpdateClanTag, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_UpdateClanTag(Handle:hTimer, any:client)
{
    SetClanTag(client);
}

SetClanTag(client)
{
    if (IsValidClient(client, false))
    {
        if (ga_iClientMVP[client] == 1)
        {
            decl String:sString[64];
            Format(sString, sizeof(sString), "[%i Win]", ga_iClientMVP[client]);
            CS_SetClientClanTag(client, sString);
        }
        else
        {
            decl String:sString[64];
            Format(sString, sizeof(sString), "[%i Wins]", ga_iClientMVP[client]);
            CS_SetClientClanTag(client, sString);
        }
    }
}

/*
public Action:Event_RoundEnd(Handle:hEvent, const String:sName[], bool:bDontBroadcast)
{
	int count = 0;
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i, false, false) && GetPlayerCount() >= 4)
        {
        	
            ga_iClientMVP[i]++;
            SetClanTag(i);
        }
    }
}*/

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int count = 0;
	int client;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && IsPlayerAlive(i))
		{
			client = i;
			count++;
		}
	}
	
	if (count == 1 && GetPlayerCount() >= 3)
	{
		ga_iClientMVP[client]++;
		SetClanTag(client);
	}
}


public OnClientPostAdminCheck(client)
{
    if (g_bPluginEnabled)
    {    
        #if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
            GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
        #else
            GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
        #endif
        LoadMvpCount(client);
    }
}

LoadMvpCount(client)
{
    if (g_bPluginEnabled)
    {
        if (!IsValidClient(client))
        {
            return;
        }
        #if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
            GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
        #else
            GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
        #endif
        if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //if ID is invalid
        {
            CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
            if (g_bDebug)
            {
                Log("table.log","Refreshing Steam ID for client %L!", client);
            }
        }
        
        if (g_hDatabase == INVALID_HANDLE) //connect not loaded - retry to give it time
        {
            CreateTimer(1.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
            if (g_bDebug)
            {
                Log("table.log","Database connection not established yet! Delaying loading of client %L", client);
            }
        }
        else
        {
            if (g_bDebug)
            {
                Log("table.log","Sending database query to load client %L", client);
            }
            
            decl String:sQuery[300];
            Format(sQuery, sizeof(sQuery), "SELECT `deaths` FROM winscounter WHERE steamid=\"%s\"", ga_sSteamID[client]);
            SQL_TQuery(g_hDatabase, SQLCallback_CheckSQL, sQuery, GetClientUserId(client));
        }
    }
}

public SQLCallback_CheckSQL(Handle:hOwner, Handle:hHndl, const String:sError[], any:iUserID)
{
    if (hHndl == INVALID_HANDLE)
    {
        SetFailState("Error: %s", sError);
    }
    
    new client = GetClientOfUserId(iUserID);
    if (!IsValidClient(client))
    {
        return;
    }
    else 
    {
        if (SQL_GetRowCount(hHndl) == 1)
        {
            SQL_FetchRow(hHndl);
            
            ga_iClientMVP[client] = SQL_FetchInt(hHndl, 0);
            
            ga_bLoaded[client] = true;
            SetClanTag(client);
            LogToGame("Player %L has been loaded from the database!", client);
            LogMessage("Player %L has been loaded from the database!", client);
            
            if (g_bDebug)
            {
                Log("table.log","Player %L has been loaded from the database !", client);
            }
        }
        else
        {
            if (SQL_GetRowCount(hHndl) > 1)
            {
                //LogError("Player %L has multiple entries under their ID. Running script to clean up duplicates and keep original entry (oldest)", client);
                //DeleteDuplicates();
                CreateTimer(20.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
            }
            else if (g_hDatabase == INVALID_HANDLE)
            {
                CreateTimer(2.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
            }
            else    //new player
            {
                decl String:sQuery[300];
                Format(sQuery, sizeof(sQuery), "INSERT INTO winscounter (steamid, deaths) VALUES(\"%s\", 0)", ga_sSteamID[client]);
                SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery, 3);
                SetClanTag(client);
                ga_bLoaded[client] = true;
                LogToGame("New player %L has been added to the database!", client);
                LogMessage("New player %L has been added to the database!", client);
                if (g_bDebug)
                {
                    Log("table.log","New player %L has been added to the database!", client);
                }
            }
        }
    }
}

/*
DeleteDuplicates()
{
    if (g_hDatabase != INVALID_HANDLE)
    {
        if (g_bDebug)
        {
            Log("table.log","Duplicates detected in database. Deleting duplicate Steam IDs!");
        }
        SQL_TQuery(g_hDatabase, SQLCallback_Void, "delete table from table inner join (select min(id) minid, steamid from table group by steamid having count(1) > 1) as duplicates on (duplicates.steamid = table.steamid and duplicates.minid <> table.id)", 4);
    }
}*/

public Action:RepeatCheckRank(Handle:hTimer, any:iUserID)
{
    new client = GetClientOfUserId(iUserID);
    LoadMvpCount(client);
}

SetDBHandle()
{
    if (g_hDatabase == INVALID_HANDLE)
    {
        SQL_TConnect(SQLCallback_Connect, g_sDatabaseName);
    }
}

public SQLCallback_Connect(Handle:hOwner, Handle:hHndl, const String:sError[], any:data)
{
    if (hHndl == INVALID_HANDLE)
    {
        SetFailState("Error connecting to database. %s", sError);
    }
    else
    {
        g_hDatabase = hHndl;
        decl String:sDriver[64];
        
        SQL_ReadDriver(g_hDatabase, sDriver, 64);
        
        if (StrEqual(sDriver, "sqlite"))
        {
            SQL_TQuery(g_hDatabase, SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `winscounter` (`id` int(20) PRIMARY KEY, `steamid` varchar(32) NOT NULL, `deaths` int(32) NOT NULL)", 0);
        }
        else
        {
            SQL_TQuery(g_hDatabase, SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `winscounter` ( `id` int(20) NOT NULL AUTO_INCREMENT, `steamid` varchar(32) NOT NULL, `deaths` int(32) NOT NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=latin1 AUTO_INCREMENT=1", 1);
        }
        
        if (g_bDebug)
        {
            Log("table.log","Successfully connected to database!");
        }
    }
}

public SQLCallback_Void(Handle:hOwner, Handle:hHndl, const String:sError[], any:iData)
{
    if (hHndl == INVALID_HANDLE)
    {
        SetFailState("Error (%i): %s", iData, sError);
    }
}

stock Log(String:sPath[], const String:sMsg[], any:...)
{
    new String:sLogFilePath[PLATFORM_MAX_PATH], String:sFormattedMsg[256];
    BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
    VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
    LogToFileEx(sLogFilePath, "%s", sFormattedMsg);
}

stock bool:IsValidClient(client, bool:bAllowBots = true, bool:bAllowDead = true)
{
    if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
    {
        return false;
    }
    return true;
}

stock GetPlayerCount()
{
    new players;
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) > 1)
        {
            players++;
        }
    }
    return players;
}