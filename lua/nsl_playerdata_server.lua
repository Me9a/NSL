-- Natural Selection League Plugin
-- Source located at - https://github.com/xToken/NSL
-- lua\nsl_playerdata_server.lua
-- - Dragon

local NSL_ClientData = { }
local NSL_NS2IDLookup = { }
local G_IDTable = { }
local RefBadges = { }
local NSL_FunctionData = { }
local NSL_PlayerDataRetries = { }
local NSL_PlayerDataMaxRetries = 3
local NSL_PlayerDataTimeout = 30

--These are the only mandatory fields
--S_ID 		- Steam ID
--NICK 		- Nickname on Site
--NSL_Team	- Current Team

--These are optional, and should be checked as such by the mod
--NSL_IP 	- IP Info from site
--NSL_ID	- Users ID on Site
--NSL_TID	- Teams ID on Site
--NSL_Level - Access Level
--NSL_Rank	- Rank
--NSL_Icon 	- Assigned Icon
--Would like to USE these icons :S

function GetNSLUserData(ns2id)
	if NSL_ClientData[ns2id] == nil then
		--Check manually specified player data table from configs
		local cPlayerData = GetNSLConfigValue("PLAYERDATA")
		local sns2id = tostring(ns2id)
		if cPlayerData and sns2id then
			for id, data in pairs(cPlayerData) do
				if id == sns2id then
					return data
				end
			end
		end
	else
		return NSL_ClientData[ns2id]
	end
	return nil
end

local function GetGameIDMatchingNS2ID(ns2id)
	ns2id = tonumber(ns2id)
	for p = 1, #G_IDTable do
		if G_IDTable[p] == ns2id then
			return p
		end
	end
end

local function GetPlayerMatchingNS2Id(ns2id)
	ns2id = tonumber(ns2id)
	local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
    for p = 1, #playerList do
        local playerClient = Server.GetOwner(playerList[p])
        if playerClient and playerClient:GetUserId() == tonumber(ns2id) then
            return playerList[p]
		end
	end
end

local function GetPlayerMatchingGameID(gID)
	local targetNS2ID = G_IDTable[gID]
	if targetNS2ID ~= nil then
		return GetPlayerMatchingNS2Id(targetNS2ID)
	end
end

local function GetPlayerMatchingName(name)
	local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
    for p = 1, #playerList do
        if playerList[p]:GetName() == name then
			return playerList[p]
		end
	end
end

function GetPlayerMatching(id)
    return GetPlayerMatchingGameID(gID) or GetPlayerMatchingNS2Id(id) or GetPlayerMatchingName(id)
end

local function GetRefBadgeforID(ns2id)
	local NSLBadges = GetNSLConfigValue("Badges")
	if NSLBadges and type(NSLBadges) == "table" then
		local level = 0
		local pData = GetNSLUserData(ns2id)
		if pData and pData.NSL_Level then
			if pData.NSL_Level <= level then
				return
			end
			level = pData.NSL_Level
			return NSLBadges[tostring(level)]
		end
	end
end

function GetNSLBadgeNameFromTeamName(teamName)
	if teamName and teamName ~= "" then
		teamName = string.lower(teamName)
		if GetNSLConfigValue("TeamNames") then
			for badge, names in pairs(GetNSLConfigValue("TeamNames")) do
				if table.contains(names, teamName) then
					return badge
				end
			end
		end
	end
end

local function UpdateClientBadge(ns2id)
	local refBadge = GetRefBadgeforID(ns2id)
	local teamBadge = GetNSLBadgeNameFromTeamName(NSL_ClientData[ns2id].NSL_Team)
	if GiveBadge then
		--Yay for badges+ mod.
		--Give badge if ref and ref badge configured.
		local succes, row
		row = 1
		if refBadge then
			success = GiveBadge(ns2id, refBadge, row)
			row = row + 1
		end
		if teamBadge then
			success = success and GiveBadge(ns2id, teamBadge, row)
		end
	else
		--Assume legacy badge process :S
		local player = GetPlayerMatchingNS2Id(ns2id)
		if player and refBadge then
			local client = Server.GetOwner(player)
			if client then
				local newmsg = { clientId = client:GetId() }
				
				--Set all badges to false first.
				for _, badge in ipairs(gRefBadges) do
					newmsg[ "has_" .. badge.name .. "_badge" ] = false
				end
				--Set current NSL badge to true.
				newmsg["has_" .. refBadge .. "_badge"] = true
				
				--Sends new badge info to all connected users.
				Server.SendNetworkMessage("RefBadges", newmsg, true)
				
				--Store it ourselves as well for future clients
				table.insert(RefBadges, {msg = newmsg, ns2id = client:GetUserId()})
			end
		end
	end
end

local function RemovePlayerFromRetryTable(player)
	local client = Server.GetOwner(player)
	if client and client:GetUserId() then
		for i = #NSL_PlayerDataRetries, 1, -1 do
			if NSL_PlayerDataRetries[i] and NSL_PlayerDataRetries[i].id == client:GetUserId() then
				NSL_PlayerDataRetries[i] = nil
			end
		end
	end
end

local function UpdateCallbacksWithNSLData(player, nslData)
	if player then
		for i = 1, #gPlayerDataUpdatedFunctions do
			gPlayerDataUpdatedFunctions[i](player, nslData)
		end
		ServerAdminPrint(Server.GetOwner(player), string.format("%s Username verified as %s", GetActiveLeague(), nslData.NICK))
	end
end

local function OnClientConnectENSLResponse(response)
	if response then
		local responsetable = json.decode(response)
		if responsetable == nil or responsetable.steam == nil or responsetable.steam.id == nil then
			--Message to user to register on ENSL site?
			--Possible DB issue?
		else
			local ns2id = NSL_NS2IDLookup[responsetable.steam.id]
			if ns2id ~= nil then
				local player = GetPlayerMatchingNS2Id(ns2id)
				local clientData = {
					S_ID = responsetable.steam.id or "",
					NICK = responsetable.username or "Invalid",
					NSL_Team = responsetable.team and responsetable.team.name or "No Team",
					NSL_ID = responsetable.id or "",
					NSL_TID = responsetable.team and responsetable.team.id or "",
				}
				if responsetable.admin then
					clientData.NSL_Level = 4
					clientData.NSL_Rank = "Admin"
				elseif responsetable.referee then
					clientData.NSL_Level = 3
					clientData.NSL_Rank = "Ref"
				elseif responsetable.caster then
					clientData.NSL_Level = 2
					clientData.NSL_Rank = "Caster"
				elseif responsetable.moderator then
					clientData.NSL_Level = 3
					clientData.NSL_Rank = "Mod"
				else
					clientData.NSL_Level = 0
					clientData.NSL_Rank = nil
				end

				--Check config refs here
				local cRefs = GetNSLConfigValue("REFS")
				if cRefs and table.contains(cRefs, ns2id) then
					--A manually configured 'Ref' - give them ref level
					clientData.NSL_Level = 3
					clientData.NSL_Rank = "Ref"
				end
				
				NSL_ClientData[ns2id] = clientData
				UpdateCallbacksWithNSLData(player, clientData)
				RemovePlayerFromRetryTable(player)
				UpdateClientBadge(ns2id)
			end
		end
	end
end

local function OnClientConnectAUSNS2Response(response)
	if response then
		local responsetable = json.decode(response)
		if responsetable == nil or responsetable.UserID == nil then
			--Message to user to register on AUSNS2 site?
			--Possible DB issue?
		else
			local steamId = string.gsub(responsetable.SteamID, "STEAM_", "")
			if steamId ~= nil then
				local ns2id = NSL_NS2IDLookup[steamId]
				if ns2id ~= nil then
					local player = GetPlayerMatchingNS2Id(ns2id)
					NSL_ClientData[ns2id] = {
					S_ID = responsetable.SteamID or "",
					NICK = responsetable.UserName or "Invalid",
					NSL_Team = responsetable.TeamName or "No Team",
					NSL_ID = responsetable.UserID or "",
					NSL_TID = responsetable.TeamID or "",
					NSL_Level = responsetable.IsAdmin and 1 or 0,
					NSL_Rank = nil,
					NSL_Icon = nil}
					
					UpdateCallbacksWithNSLData(player, NSL_ClientData[ns2id])
					RemovePlayerFromRetryTable(player)
					UpdateClientBadge(ns2id)
				end				
			end
		end
	end
end

function UpdateNSLPlayerData(RefTable)
	if not GetNSLUserData(RefTable.id) then
		--Check for retry
		if RefTable.attemps < NSL_PlayerDataMaxRetries then
			--Doesnt have data, query
			local QueryURL = GetNSLConfigValue("PlayerDataURL")
			if QueryURL then
				--PlayerDataFormat
				local steamId = "0:" .. (RefTable.id % 2) .. ":" .. math.floor(RefTable.id / 2)
				NSL_NS2IDLookup[steamId] = RefTable.id
				RefTable.attemps = RefTable.attemps + 1
				RefTable.time = NSL_PlayerDataTimeout
				if GetNSLConfigValue("PlayerDataFormat") == "ENSL" then
					Shared.SendHTTPRequest(string.format("%s%s.steamid", QueryURL, RefTable.id), "GET", OnClientConnectENSLResponse)
				end
				if GetNSLConfigValue("PlayerDataFormat") == "AUSNS" then
					Shared.SendHTTPRequest(string.format("%s%s", QueryURL, steamId), "GET", OnClientConnectAUSNS2Response)
				end
			else
				--Configs might not be loaded yet - push out time
				RefTable.time = NSL_PlayerDataTimeout
			end
		else
			Shared.Message(string.format("NSL - Failed to get valid response from %s site for ns2id %s.", 
														GetActiveLeague(), tostring(RefTable.id)))
			RefTable = nil
		end
	else
		--Already have data.
		local player = GetPlayerMatchingNS2Id(RefTable.id)
		if player then
			UpdateCallbacksWithNSLData(player, GetNSLUserData(RefTable.id))
		end
		RefTable = nil
	end
end

local function OnNSLClientConnected(client)
	local NS2ID = client:GetUserId()
	if GetNSLModEnabled() and NS2ID > 0 then
		table.insert(NSL_PlayerDataRetries, {id = NS2ID, attemps = 0, time = 1})
		--Dont think badges+ needs this..
		if not GiveBadge and #RefBadges > 0 then
			--Sync user all badge data
			for _, badge in ipairs(RefBadges) do
				--Check for updates first
				if NS2ID == badge.ns2id then
					--Update and send to everyone
					badge.msg.clientId = client:GetId()
					Server.SendNetworkMessage( "RefBadges", badge.msg, true )
				else
					Server.SendNetworkMessage( client, "RefBadges", badge.msg, true )
				end
			end
		end
	end
	if not table.contains(G_IDTable, NS2ID) then
		table.insert(G_IDTable, NS2ID)
	end
end

table.insert(gConnectFunctions, OnNSLClientConnected)

local function OnServerUpdated(deltaTime)
	if GetNSLModEnabled() then
		for i = #NSL_PlayerDataRetries, 1, -1 do
			if NSL_PlayerDataRetries[i] and NSL_PlayerDataRetries[i].time > 0 then
				NSL_PlayerDataRetries[i].time = math.max(0, NSL_PlayerDataRetries[i].time - deltaTime)
				if NSL_PlayerDataRetries[i].time == 0 then
					UpdateNSLPlayerData(NSL_PlayerDataRetries[i])
				end
			end
		end
	end
end

Event.Hook("UpdateServer", OnServerUpdated)

local function UpdatePlayerDataOnActivation(newState)
	if newState == "PCW" or newState == "OFFICIAL" or newState == "GATHER" then
		local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
		for p = 1, #playerList do
			local playerClient = Server.GetOwner(playerList[p])
			if playerClient then
				OnNSLClientConnected(playerClient)
			end
		end
	end
end

table.insert(gPluginStateChange, UpdatePlayerDataOnActivation)

local function GetPlayerList(query)
	if query == nil then
		return EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
	elseif query:lower() == "marines" then
		return GetEntitiesForTeam("Player", kTeam1Index)
	elseif query:lower() == "aliens" then
		return GetEntitiesForTeam("Player", kTeam2Index)
	elseif query:lower() == "specs" or query:lower() == "spectators" then
		return GetEntitiesForTeam("Player", kSpectatorIndex)
	elseif query:lower() == "other" or query:lower() == "others" then
		return GetEntitiesForTeam("Player", kTeamReadyRoom)
	else
		return EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
	end
end

local function GetPlayerString(player)
	local playerClient = Server.GetOwner(player)
	if playerClient then
		local pNS2ID = playerClient:GetUserId()
		local NSLData = GetNSLUserData(pNS2ID)
		local gID = GetGameIDMatchingNS2ID(pNS2ID)
		if NSLData == nil then
			local sID = "0:" .. (pNS2ID % 2) .. ":" .. math.floor(pNS2ID / 2)
			return string.format("IGN : %s, sID : %s, NS2ID : %s, gID : %s, HCap : %.0f%%, League Information Unavailable or Unregistered User.", player:GetName(), sID, pNS2ID, gID, (1 - player:GetHandicap() ) * 100)
		else
			return string.format("IGN : %s, sID : %s, NS2ID : %s, gID : %s, HCap : %.0f%%, LNick : %s, LTeam : %s, LID : %s", player:GetName(), NSLData.S_ID, pNS2ID, gID, (1 - player:GetHandicap() ) * 100, NSLData.NICK, NSLData.NSL_Team, NSLData.NSL_ID or 0)
		end				
	end
	return ""
end

local function OnClientCommandViewNSLInfo(client, team)
	if client then
		local NS2ID = client:GetUserId()
		local playerList = GetPlayerList(team)				
		if playerList then
			ServerAdminPrint(client, "IGN = In-Game Name, sID = SteamID, gID = GameID, HCap = Handicap, LNick = League Nickname, LTeam = League Team, LID = League ID")
			for p = 1, #playerList do
				ServerAdminPrint(client, GetPlayerString(playerList[p]))
			end
		end
	end
end

Event.Hook("Console_sv_nslinfo",               OnClientCommandViewNSLInfo)

local function MakeNSLMessage(message, header)
	local m = { }
	m.message = string.sub(message, 1, 250)
	m.header = header
	m.color = GetNSLConfigValue("MessageColor")
	return m
end

local function OnCommandChat(client, target, message, header)
	if target == nil then
		Server.SendNetworkMessage("NSLSystemMessage", MakeNSLMessage(message, header), true)
	else
		if type(target) == "number" then
			local playerRecords = GetEntitiesForTeam("Player", target)
			for _, player in ipairs(playerRecords) do
				local pclient = Server.GetOwner(player)
				if pclient ~= nil then
					Server.SendNetworkMessage(pclient, "NSLSystemMessage", MakeNSLMessage(message, header), true)
				end
			end
		elseif type(target) == "userdata" and target:isa("Player") then
			Server.SendNetworkMessage(target, "NSLSystemMessage", MakeNSLMessage(message, header), true)
		end
	end
end

local function OnClientCommandChat(client, ...)
	if not client then return end
	local NS2ID = client:GetUserId()
	if GetIsNSLRef(NS2ID) then
		local ns2data = GetNSLUserData(NS2ID)
		local message = ""
		local header = string.format("(All)(%s) %s:", ns2data.NSL_Rank or "Ref", ns2data.NICK or NS2ID)
        for i, p in ipairs({...}) do
            message = message .. " " .. p
        end
		OnCommandChat(client, nil, message, header)
	end
end

Event.Hook("Console_sv_nslsay",               OnClientCommandChat)

local function OnClientCommandTeamChat(client, team, ...)
	if not client then return end
	local NS2ID = client:GetUserId()
	team = tonumber(team)
	if GetIsNSLRef(NS2ID) and team then
		local ns2data = GetNSLUserData(NS2ID)
		local message = ""
		local header = string.format("(%s)(%s) %s:", GetActualTeamName(team), ns2data.NSL_Rank or "Ref", ns2data.NICK or NS2ID)
        for i, p in ipairs({...}) do
            message = message .. " " .. p
        end
		OnCommandChat(client, team, message, header)
	end
end

Event.Hook("Console_sv_nsltsay",               OnClientCommandTeamChat)

local function OnClientCommandPlayerChat(client, target, ...)
	if not client then return end
	local NS2ID = client:GetUserId()
	local player = GetPlayerMatching(target)
	if GetIsNSLRef(NS2ID) and player then
		local ns2data = GetNSLUserData(NS2ID)
		local message = ""
		local header = string.format("(%s)(%s) %s:", player:GetName(), ns2data.NSL_Rank or "Ref", ns2data.NICK or NS2ID)
        for i, p in ipairs({...}) do
            message = message .. " " .. p
        end
		OnCommandChat(client, player, message, header)
	end
end

Event.Hook("Console_sv_nslpsay", OnClientCommandPlayerChat)

local function OnRecievedFunction(client, message)

	if client and message then
		local NS2ID = client:GetUserId()
		if not NSL_FunctionData[NS2ID] then
			NSL_FunctionData[NS2ID] = { }
		end
		if not table.contains(NSL_FunctionData[NS2ID], message.detectionType) then
			--Reconnects or monitored fields could re-add duplicate stuff, only add if new.	
			table.insert(NSL_FunctionData[NS2ID], message.detectionType)
		end
		--Set value
		NSL_FunctionData[NS2ID][message.detectionType] = message.detectionValue
	end
	
end

Server.HookNetworkMessage("ClientFunctionReport", OnRecievedFunction)

local function GetFunctionString(player)
	local playerClient = Server.GetOwner(player)
	if playerClient then
		local pNS2ID = playerClient:GetUserId()
		local NSLData = GetNSLUserData(pNS2ID)
		local gID = GetGameIDMatchingNS2ID(pNS2ID)
		if NSLData == nil then
			local sID = "0:" .. (pNS2ID % 2) .. ":" .. math.floor(pNS2ID / 2)
			return string.format("IGN : %s, sID : %s, NS2ID : %s, gID : %s, League Information Unavailable or Unregistered User.", player:GetName(), sID, pNS2ID, gID)
		else
			return string.format("IGN : %s, sID : %s, NS2ID : %s, gID : %s, LNick : %s", player:GetName(), NSLData.S_ID, pNS2ID, gID, NSLData.NICK)
		end				
	end
	return ""
end

local function OnClientCommandShowFunctionData(client, target)
	if not client then return end
	local NS2ID = client:GetUserId()
	local heading = false
	if GetIsNSLAdmin(NS2ID) then
		local targetPlayer = GetPlayerMatching(target)
		local targetClient
		if targetPlayer then
			targetClient = Server.GetOwner(targetPlayer)
		end
		local playerList = GetPlayerList()
		if playerList then
			for p = 1, #playerList do
				local playerClient = Server.GetOwner(playerList[p])
				if playerClient then
					local pNS2ID = playerClient:GetUserId()
					if NSL_FunctionData[pNS2ID] and (not targetPlayer or (targetClient and pNS2ID == targetClient:GetUserId())) then
						if not heading then
							ServerAdminPrint(client, "IGN = In-Game Name, sID = SteamID, gID = GameID, LNick = League Nickname")
							heading = true
						end
						ServerAdminPrint(client, "Function Data For " .. GetFunctionString(playerList[p]))
						for k, v in ipairs(NSL_FunctionData[pNS2ID]) do
							--Check for value updates if this is a detection type that updates.. itself?
							if NSL_FunctionData[pNS2ID][v] then
								ServerAdminPrint(client, v .. ":" .. NSL_FunctionData[pNS2ID][v])
							else
								ServerAdminPrint(client, v)
							end
						end
						ServerAdminPrint(client, "End Function Data")
					end
				end
			end
		end
		if not heading then
			ServerAdminPrint(client, "No function data currently logged")
		end
	end
end

Event.Hook("Console_sv_nslfunctiondata", OnClientCommandShowFunctionData)