local Wait = Wait
local Config = Config
local pairs = pairs

local pedsReady = false

local function applyPedConfig(spawnedped, v)
	if v.freeze then FreezeEntityPosition(spawnedped, true) end
	if v.invincible then SetEntityInvincible(spawnedped, true) end
	if v.blockevents then SetBlockingOfNonTemporaryEvents(spawnedped, true) end

	if v.animDict and v.anim then
		RequestAnimDict(v.animDict)
		while not HasAnimDictLoaded(v.animDict) do Wait(0) end
		TaskPlayAnim(spawnedped, v.animDict, v.anim, 8.0, 0, -1, v.flag or 1, 0, false, false, false)
	end

	if v.scenario then
		SetPedCanPlayAmbientAnims(spawnedped, true)
		TaskStartScenarioInPlace(spawnedped, v.scenario, 0, true)
	end

	if v.pedrelations then
		if type(v.pedrelations.groupname) ~= 'string' then error(v.pedrelations.groupname .. ' is not a string') end
		local pedgrouphash = joaat(v.pedrelations.groupname)
		if not DoesRelationshipGroupExist(pedgrouphash) then AddRelationshipGroup(v.pedrelations.groupname) end
		SetPedRelationshipGroupHash(spawnedped, pedgrouphash)
		if v.pedrelations.toplayer then
			SetRelationshipBetweenGroups(v.pedrelations.toplayer, pedgrouphash, joaat('PLAYER'))
		end
		if v.pedrelations.toowngroup then
			SetRelationshipBetweenGroups(v.pedrelations.toowngroup, pedgrouphash, pedgrouphash)
		end
	end

	if v.weapon then
		if type(v.weapon.name) == 'string' then v.weapon.name = joaat(v.weapon.name) end
		if IsWeaponValid(v.weapon.name) then
			SetCanPedEquipWeapon(spawnedped, v.weapon.name, true)
			GiveWeaponToPed(spawnedped, v.weapon.name, v.weapon.ammo, v.weapon.hidden or false, true)
			SetPedCurrentWeaponVisible(spawnedped, not v.weapon.hidden or false, true)
		end
	end

	if v.target then
		if v.target.useModel then
			AddTargetModel(v.model, { options = v.target.options, distance = v.target.distance })
		else
			AddTargetEntity(spawnedped, { options = v.target.options, distance = v.target.distance })
		end
	end

	if v.action then v.action(v) end
end

local function spawnOnePed(v, missionPed)
	RequestModel(v.model)
	while not HasModelLoaded(v.model) do Wait(0) end
	if type(v.model) == 'string' then v.model = joaat(v.model) end
	local z = v.minusOne and (v.coords.z - 1.0) or v.coords.z
	local ped = CreatePed(0, v.model, v.coords.x, v.coords.y, z, v.coords.w or 0.0, v.networked or false, missionPed)
	applyPedConfig(ped, v)
	return ped
end

function SpawnPeds()
	if pedsReady or not next(Config.Peds) then return end
	for k, v in pairs(Config.Peds) do
		if not v.currentpednumber or v.currentpednumber == 0 then
			Config.Peds[k].currentpednumber = spawnOnePed(v, false)
		end
	end
	pedsReady = true
end

function DeletePeds()
	if not pedsReady or not next(Config.Peds) then return end
	for k, v in pairs(Config.Peds) do
		DeletePed(v.currentpednumber)
		Config.Peds[k].currentpednumber = 0
	end
	pedsReady = false
end

exports('DeletePeds', DeletePeds)

function SpawnPed(data)
	local key, value = next(data)
	if type(value) == 'table' and type(key) ~= 'string' then
		for _, v in pairs(data) do
			if v.spawnNow then v.currentpednumber = spawnOnePed(v, true) end
			local nextnumber = #Config.Peds + 1
			if nextnumber <= 0 then nextnumber = 1 end
			Config.Peds[nextnumber] = v
		end
	else
		if data.spawnNow then data.currentpednumber = spawnOnePed(data, true) end
		local nextnumber = #Config.Peds + 1
		if nextnumber <= 0 then nextnumber = 1 end
		Config.Peds[nextnumber] = data
	end
end

exports('SpawnPed', SpawnPed)

local function RemovePed(peds)
	if type(peds) == 'table' then
		for k, v in pairs(peds) do
			DeletePed(v)
			if Config.Peds[k] then Config.Peds[k].currentpednumber = 0 end
		end
	elseif type(peds) == 'number' then
		DeletePed(peds)
	end
end

exports('RemoveSpawnedPed', RemovePed)

local function GetPeds() return Config.Peds end
exports('GetPeds', GetPeds)

local function UpdatePedsData(index, data) Config.Peds[index] = data end
exports('UpdatePedsData', UpdatePedsData)
