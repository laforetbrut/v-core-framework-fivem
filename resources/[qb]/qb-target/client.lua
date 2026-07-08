local GetEntityCoords = GetEntityCoords
local Wait = Wait
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetWorldPositionOfEntityBone = GetWorldPositionOfEntityBone
local SetPauseMenuActive = SetPauseMenuActive
local DisableAllControlActions = DisableAllControlActions
local EnableControlAction = EnableControlAction
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local GetEntityModel = GetEntityModel
local IsPedAPlayer = IsPedAPlayer
local GetEntityType = GetEntityType
local PlayerPedId = PlayerPedId
local GetShapeTestResult = GetShapeTestResult
local StartShapeTestLosProbe = StartShapeTestLosProbe
local SetDrawOrigin = SetDrawOrigin
local DrawSprite = DrawSprite
local ClearDrawOrigin = ClearDrawOrigin
local HasStreamedTextureDictLoaded = HasStreamedTextureDictLoaded
local RequestStreamedTextureDict = RequestStreamedTextureDict
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local currentResourceName = GetCurrentResourceName()
local Config = Config

local function Load(name)
	local chunk = LoadResourceFile(currentResourceName, ('data/%s.lua'):format(name))
	if chunk then
		local err
		chunk, err = load(chunk, ('@@%s/data/%s.lua'):format(currentResourceName, name), 't')
		if err then
			error(('\n^1 %s'):format(err), 0)
		end
		return chunk()
	end
end
local pairs        = pairs
local pcall        = pcall
local table_wipe   = table.wipe

-- QBCore state — populated by the init thread below, captured as upvalues by CheckOptions
local QBCore, PlayerData
local ItemCheck    = function(_) return true end
local JobCheck     = function(_) return true end
local GangCheck    = function(_) return true end
local JobTypeCheck = function(_) return true end
local CitizenCheck = function(_) return true end

local function CheckOptions(data, entity, distance)
	if distance and data.distance and distance > data.distance then return false end
	if data.job and not JobCheck(data.job) then return false end
	if data.excludejob and JobCheck(data.excludejob) then return false end
	if data.jobType and not JobTypeCheck(data.jobType) then return false end
	if data.excludejobType and JobTypeCheck(data.excludejobType) then return false end
	if data.gang and not GangCheck(data.gang) then return false end
	if data.excludegang and GangCheck(data.excludegang) then return false end
	if data.item and not ItemCheck(data.item) then return false end
	if data.citizenid and not CitizenCheck(data.citizenid) then return false end
	if data.canInteract and not data.canInteract(entity, distance, data) then return false end
	return true
end

-- Shared state — global so registration.lua and peds.lua can access them
Types, Players, Entities, Models, Zones = { {}, {}, {} }, {}, {}, {}, {}
Bones = Load('bones')

local nuiData, sendData, sendDistance = {}, {}, {}
local playerPed, targetActive, hasFocus, success, allowTarget = PlayerPedId(), false, false, false, true
local screen = {}
local listSprite = {}

---------------------------------------
--- Source: https://github.com/citizenfx/lua/blob/luaglm-dev/cfx/libs/scripts/examples/scripting_gta.lua
--- Credits to gottfriedleibniz
local glm = require 'glm'

local glm_rad = glm.rad
local glm_quatEuler = glm.quatEulerAngleZYX
local glm_rayPicking = glm.rayPicking
local glm_up = glm.up()
local glm_forward = glm.forward()

local function ScreenPositionToCameraRay()
	local pos = GetFinalRenderedCamCoord()
	local rot = glm_rad(GetFinalRenderedCamRot(2))
	local q = glm_quatEuler(rot.z, rot.y, rot.x)
	return pos, glm_rayPicking(
		q * glm_forward,
		q * glm_up,
		glm_rad(screen.fov),
		screen.ratio,
		0.10000,
		10000.0,
		0, 0
	)
end
---------------------------------------

local function DrawTarget()
	CreateThread(function()
		while not HasStreamedTextureDictLoaded('shared') do
			Wait(10)
			RequestStreamedTextureDict('shared', true)
		end
		local sleep
		local r, g, b, a
		while targetActive do
			sleep = 500
			for _, zone in pairs(listSprite) do
				sleep = 0
				r = zone.targetoptions.drawColor?[1] or Config.DrawColor[1]
				g = zone.targetoptions.drawColor?[2] or Config.DrawColor[2]
				b = zone.targetoptions.drawColor?[3] or Config.DrawColor[3]
				a = zone.targetoptions.drawColor?[4] or Config.DrawColor[4]
				if zone.success then
					r = zone.targetoptions.successDrawColor?[1] or Config.SuccessDrawColor[1]
					g = zone.targetoptions.successDrawColor?[2] or Config.SuccessDrawColor[2]
					b = zone.targetoptions.successDrawColor?[3] or Config.SuccessDrawColor[3]
					a = zone.targetoptions.successDrawColor?[4] or Config.SuccessDrawColor[4]
				end
				SetDrawOrigin(zone.center.x, zone.center.y, zone.center.z, 0)
				DrawSprite('shared', 'emptydot_32', 0, 0, 0.01, 0.02, 0, r, g, b, a)
				ClearDrawOrigin()
			end
			Wait(sleep)
		end
		listSprite = {}
	end)
end

local function RaycastCamera(flag, playerCoords)
	if not playerPed then playerPed = PlayerPedId() end
	if not playerCoords then playerCoords = GetEntityCoords(playerPed) end

	local rayPos, rayDir = ScreenPositionToCameraRay()
	local destination = rayPos + 16 * rayDir
	local rayHandle = StartShapeTestLosProbe(rayPos.x, rayPos.y, rayPos.z, destination.x, destination.y, destination.z,
		flag or -1, playerPed, 4)

	while true do
		local result, _, endCoords, _, entityHit = GetShapeTestResult(rayHandle)
		if result ~= 1 then
			local distance = playerCoords and #(playerCoords - endCoords)
			if flag == 30 and entityHit then
				entityHit = HasEntityClearLosToEntity(entityHit, playerPed, 7) and entityHit
			end
			local entityType = entityHit and GetEntityType(entityHit)
			if entityType == 0 and pcall(GetEntityModel, entityHit) then
				entityType = 3
			end
			return endCoords, distance, entityHit, entityType or 0
		end
		Wait(0)
	end
end

exports('RaycastCamera', RaycastCamera)

local function DisableNUI()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	hasFocus = false
end

exports('DisableNUI', DisableNUI)

local function EnableNUI(options)
	if not targetActive or hasFocus then return end
	SetCursorLocation(0.5, 0.5)
	SetNuiFocus(true, true)
	SetNuiFocusKeepInput(true)
	hasFocus = true
	SendNUIMessage({ response = 'validTarget', data = options })
end

exports('EnableNUI', EnableNUI)

local function LeftTarget()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	success, hasFocus = false, false
	table_wipe(sendData)
	SendNUIMessage({ response = 'leftTarget' })
end

exports('LeftTarget', LeftTarget)

local function DisableTarget(forcedisable)
	if not forcedisable then return end
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
	SendNUIMessage({ response = 'closeTarget' })
end

exports('DisableTarget', DisableTarget)

local function DrawOutlineEntity(entity, bool)
	if not Config.EnableOutline or IsEntityAPed(entity) then return end
	SetEntityDrawOutline(entity, bool)
	SetEntityDrawOutlineColor(Config.OutlineColor[1], Config.OutlineColor[2], Config.OutlineColor[3], Config.OutlineColor[4])
end

exports('DrawOutlineEntity', DrawOutlineEntity)

local function SetupOptions(datatable, entity, distance, isZone)
	if not isZone then table_wipe(sendDistance) end
	table_wipe(nuiData)
	local slot = 0
	for _, data in pairs(datatable) do
		if CheckOptions(data, entity, distance) then
			slot = data.num or slot + 1
			if sendData[slot] then slot = #sendData + 1 end
			sendData[slot] = data
			sendData[slot].entity = entity
			nuiData[slot] = {
				icon = data.icon,
				targeticon = data.targeticon,
				label = data.label
			}
			if not isZone then
				sendDistance[data.distance] = true
			end
		else
			if not isZone then
				sendDistance[data.distance] = false
			end
		end
	end
	return slot
end

local function CheckEntity(flag, datatable, entity, distance)
	if not next(datatable) then return end
	local slot = SetupOptions(datatable, entity, distance)
	if not next(nuiData) then
		LeftTarget()
		DrawOutlineEntity(entity, false)
		return
	end
	success = true
	SendNUIMessage({ response = 'foundTarget', data = nuiData[slot].targeticon, options = nuiData })
	DrawOutlineEntity(entity, true)
	while targetActive and success do
		if not hasFocus then
			local _, dist, entity2 = RaycastCamera(flag)
			if entity ~= entity2 then
				LeftTarget()
				DrawOutlineEntity(entity, false)
				break
			else
				for k, v in pairs(sendDistance) do
					if v and dist > k then
						LeftTarget()
						DrawOutlineEntity(entity, false)
						break
					end
				end
			end
		end
		Wait(0)
	end
	LeftTarget()
	DrawOutlineEntity(entity, false)
end

exports('CheckEntity', CheckEntity)

local function CheckBones(coords, entity, bonelist)
	local closestBone = -1
	local closestDistance = 20
	local closestPos, closestBoneName
	for _, v in pairs(bonelist) do
		if Bones.Options[v] then
			local boneId = GetEntityBoneIndexByName(entity, v)
			local bonePos = GetWorldPositionOfEntityBone(entity, boneId)
			local distance = #(coords - bonePos)
			if closestBone == -1 or distance < closestDistance then
				closestBone, closestDistance, closestPos, closestBoneName = boneId, distance, bonePos, v
			end
		end
	end
	if closestBone ~= -1 then
		return closestBone, closestPos, closestBoneName
	else
		return false
	end
end

exports('CheckBones', CheckBones)

local function EnableTarget()
	if not allowTarget or success or not LocalPlayer.state['isLoggedIn'] or IsNuiFocused() or (Config.DisableInVehicle and IsPedInAnyVehicle(playerPed or PlayerPedId(), false)) then return end
	if targetActive then return end

	targetActive = true
	playerPed = PlayerPedId()
	screen.ratio = GetAspectRatio(true)
	screen.fov = GetFinalRenderedCamFov()
	if Config.DrawSprite then DrawTarget() end

	SendNUIMessage({ response = 'openTarget' })
	CreateThread(function()
		repeat
			SetPauseMenuActive(false)
			if Config.DisableControls then
				DisableAllControlActions(0)
			else
				DisableControlAction(0, 1, true) -- look left/right
				DisableControlAction(0, 2, true) -- look up/down
				DisableControlAction(0, 4, true) -- look down only
				DisableControlAction(0, 5, true) -- look left only
				DisableControlAction(0, 6, true) -- look right only
				DisableControlAction(0, 25, true) -- input aim
				DisableControlAction(0, 24, true) -- attack
			end
			EnableControlAction(0, 30, true) -- move left/right
			EnableControlAction(0, 31, true) -- move forward/back

			if not hasFocus then
				EnableControlAction(0, 1, true) -- look left/right
				EnableControlAction(0, 2, true) -- look up/down
			end

			Wait(0)
		until not targetActive
	end)

	local flag = 30

	while targetActive do
		local sleep = 0
		if flag == 30 then flag = -1 else flag = 30 end

		local coords, distance, entity, entityType = RaycastCamera(flag)
		if distance <= Config.MaxDistance then
			if entityType > 0 then
				-- Local (non-net) entity targets
				if Entities[entity] then
					CheckEntity(flag, Entities[entity], entity, distance)
				end

				-- Owned entity targets
				if NetworkGetEntityIsNetworked(entity) then
					local data = Entities[NetworkGetNetworkIdFromEntity(entity)]
					if data then CheckEntity(flag, data, entity, distance) end
				end

				-- Player and Ped targets
				if entityType == 1 then
					local data = Models[GetEntityModel(entity)]
					if IsPedAPlayer(entity) then data = Players end
					if data and next(data) then CheckEntity(flag, data, entity, distance) end

					-- Vehicle bones and models
				elseif entityType == 2 then
					local closestBone, _, closestBoneName = CheckBones(coords, entity, Bones.Vehicle)
					local datatable = Bones.Options[closestBoneName]

					if datatable and next(datatable) and closestBone then
						local slot = SetupOptions(datatable, entity, distance)
						if next(nuiData) then
							success = true
							SendNUIMessage({ response = 'foundTarget', data = nuiData[slot].targeticon, options = nuiData })
							DrawOutlineEntity(entity, true)
							while targetActive and success do
								if not hasFocus then
									local coords2, dist, entity2 = RaycastCamera(flag)
									if entity == entity2 then
										local closestBone2 = CheckBones(coords2, entity, Bones.Vehicle)
										if closestBone ~= closestBone2 then
											LeftTarget()
											DrawOutlineEntity(entity, false)
											break
										else
											for k, v in pairs(sendDistance) do
												if v and dist > k then
													LeftTarget()
													DrawOutlineEntity(entity, false)
													break
												end
											end
										end
									else
										LeftTarget()
										DrawOutlineEntity(entity, false)
										break
									end
								end
								Wait(0)
							end
							LeftTarget()
							DrawOutlineEntity(entity, false)
						end
					end

					-- Vehicle model targets
					local data = Models[GetEntityModel(entity)]
					if data then CheckEntity(flag, data, entity, distance) end

					-- Entity targets
				elseif entityType > 2 then
					local data = Models[GetEntityModel(entity)]
					if data then CheckEntity(flag, data, entity, distance) end
				end

				-- Generic targets
				if not success then
					local data = Types[entityType]
					if data and next(data) then CheckEntity(flag, data, entity, distance) end
				end
			else
				sleep = sleep + 20
			end

			if not success then
				-- Zone targets
				local closestDis, closestZone
				for k, zone in pairs(Zones) do
					if distance < (closestDis or Config.MaxDistance) and distance <= zone.targetoptions.distance and zone:isPointInside(coords) then
						closestDis = distance
						closestZone = zone
					end
					if Config.DrawSprite then
						local testCentre = type(zone.center) == 'vector2' and vector3(zone.center.x, zone.center.y, zone.maxZ) or zone.center
						if #(coords - testCentre) < (zone.targetoptions.drawDistance or Config.DrawDistance) then
							listSprite[k] = zone
						else
							listSprite[k] = nil
						end
					end
				end
				if closestZone then
					local slot = SetupOptions(closestZone.targetoptions.options, entity, distance, true)
					if next(nuiData) then
						success = true
						SendNUIMessage({ response = 'foundTarget', data = nuiData[slot].targeticon, options = nuiData })
						if Config.DrawSprite then
							listSprite[closestZone.name].success = true
						end
						DrawOutlineEntity(entity, true)
						while targetActive and success do
							if not hasFocus then
								local newCoords, dist = RaycastCamera(flag)
								if not closestZone:isPointInside(newCoords) or dist > closestZone.targetoptions.distance then
									LeftTarget()
									DrawOutlineEntity(entity, false)
									break
								end
							end
							Wait(0)
						end
						if Config.DrawSprite and listSprite[closestZone.name] then
							listSprite[closestZone.name].success = false
						end
						LeftTarget()
						DrawOutlineEntity(entity, false)
					end
				else
					sleep = sleep + 20
				end
			else
				LeftTarget()
				DrawOutlineEntity(entity, false)
			end
		else
			sleep = sleep + 20
		end
		Wait(sleep)
	end
	DisableTarget(false)
end

local function AllowTargeting(bool)
	allowTarget = bool
	if allowTarget then return end
	DisableTarget(true)
end

exports('AllowTargeting', AllowTargeting)

local function IsTargetActive() return targetActive end
exports('IsTargetActive', IsTargetActive)

local function IsTargetSuccess() return success end
exports('IsTargetSuccess', IsTargetSuccess)

-- NUI Callbacks

RegisterNUICallback('selectTarget', function(option, cb)
	option = tonumber(option) or option
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
	if not next(sendData) then return end
	local data = sendData[option]
	if not data then return end
	table_wipe(sendData)
	CreateThread(function()
		Wait(0)
		if data.entity ~= nil then
			data.coords = GetEntityCoords(data.entity)
		end
		if data.action then
			data.action(data.entity)
		elseif data.event then
			if data.type == 'client' then
				TriggerEvent(data.event, data)
			elseif data.type == 'server' then
				TriggerServerEvent(data.event, data)
			elseif data.type == 'command' then
				ExecuteCommand(data.event)
			elseif data.type == 'qbcommand' then
				TriggerServerEvent('QBCore:CallCommand', data.event, data)
			else
				TriggerEvent(data.event, data)
			end
		else
			error('No trigger setup')
		end
	end)
	cb('ok')
end)

RegisterNUICallback('closeTarget', function(_, cb)
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
	cb('ok')
end)

RegisterNUICallback('leftTarget', function(_, cb)
	DisableTarget(true)
	cb('ok')
end)

-- Startup thread

CreateThread(function()
	RegisterCommand('+playerTarget', function()
		CreateThread(EnableTarget)
	end, false)
	RegisterCommand('-playerTarget', function()
		if success then
			EnableNUI(nuiData)
		else
			DisableTarget(true)
		end
	end, false)
	RegisterKeyMapping('+playerTarget', 'Enable targeting', 'keyboard', Config.OpenKey)
	TriggerEvent('chat:removeSuggestion', '/+playerTarget')
	TriggerEvent('chat:removeSuggestion', '/-playerTarget')

	if table.type(Config.CircleZones) ~= 'empty' then
		for _, v in pairs(Config.CircleZones) do
			AddCircleZone(v.name, v.coords, v.radius, {
				name = v.name,
				debugPoly = v.debugPoly,
				useZ = v.useZ,
			}, {
				options = v.options,
				distance = v.distance
			})
		end
	end

	if table.type(Config.BoxZones) ~= 'empty' then
		for _, v in pairs(Config.BoxZones) do
			AddBoxZone(v.name, v.coords, v.length, v.width, {
				name = v.name,
				heading = v.heading,
				debugPoly = v.debugPoly,
				minZ = v.minZ,
				maxZ = v.maxZ
			}, {
				options = v.options,
				distance = v.distance
			})
		end
	end

	if table.type(Config.PolyZones) ~= 'empty' then
		for _, v in pairs(Config.PolyZones) do
			AddPolyZone(v.name, v.points, {
				name = v.name,
				debugPoly = v.debugPoly,
				minZ = v.minZ,
				maxZ = v.maxZ
			}, {
				options = v.options,
				distance = v.distance
			})
		end
	end

	if table.type(Config.TargetBones) ~= 'empty' then
		for _, v in pairs(Config.TargetBones) do
			AddTargetBone(v.bones, {
				options = v.options,
				distance = v.distance
			})
		end
	end

	if table.type(Config.TargetModels) ~= 'empty' then
		for _, v in pairs(Config.TargetModels) do
			AddTargetModel(v.models, {
				options = v.options,
				distance = v.distance
			})
		end
	end

	if table.type(Config.GlobalPedOptions) ~= 'empty' then
		AddGlobalPed(Config.GlobalPedOptions)
	end

	if table.type(Config.GlobalVehicleOptions) ~= 'empty' then
		AddGlobalVehicle(Config.GlobalVehicleOptions)
	end

	if table.type(Config.GlobalObjectOptions) ~= 'empty' then
		AddGlobalObject(Config.GlobalObjectOptions)
	end

	if table.type(Config.GlobalPlayerOptions) ~= 'empty' then
		AddGlobalPlayer(Config.GlobalPlayerOptions)
	end
end)

-- QBCore init

CreateThread(function()
	QBCore = exports['qb-core']:GetCoreObject({ 'Functions' })
	PlayerData = QBCore.Functions.GetPlayerData()
	ItemCheck = QBCore.Functions.HasItem

	JobCheck = function(job)
		if type(job) == 'table' then
			job = job[PlayerData.job.name]
			if job and PlayerData.job.grade.level >= job then return true end
		elseif job == 'all' or job == PlayerData.job.name then
			return true
		end
		return false
	end

	JobTypeCheck = function(jobType)
		if type(jobType) == 'table' then
			jobType = jobType[PlayerData.job.type]
			if jobType then return true end
		elseif jobType == 'all' or jobType == PlayerData.job.type then
			return true
		end
		return false
	end

	GangCheck = function(gang)
		if type(gang) == 'table' then
			gang = gang[PlayerData.gang.name]
			if gang and PlayerData.gang.grade.level >= gang then return true end
		elseif gang == 'all' or gang == PlayerData.gang.name then
			return true
		end
		return false
	end

	CitizenCheck = function(citizenid)
		return citizenid == PlayerData.citizenid or citizenid[PlayerData.citizenid]
	end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
	PlayerData = QBCore.Functions.GetPlayerData()
	SpawnPeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
	PlayerData = {}
	DeletePeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
	if key == 'job' then
		local JobInfo = val
		PlayerData.job = JobInfo
	elseif key == 'gang' then
		local GangInfo = val
		PlayerData.gang = GangInfo
	elseif key == 'all' then
		PlayerData = val
	end
end)

-- Events

AddEventHandler('onResourceStart', function(resource)
	if resource ~= currentResourceName then return end
	SpawnPeds()
end)

AddEventHandler('onResourceStop', function(resource)
	if resource ~= currentResourceName then return end
	DeletePeds()
end)

if Config.Debug then Load('debug') end
