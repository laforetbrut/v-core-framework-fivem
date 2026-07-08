local Config = Config
local pairs = pairs

-- SetOptions is a private helper; all Add* functions funnel through it
local function SetOptions(tbl, distance, options)
	for _, v in pairs(options) do
		if v.required_item then
			v.item = v.required_item
			v.required_item = nil
		end
		if not v.distance or v.distance > distance then v.distance = distance end
		tbl[v.label] = v
	end
end

-- Zones

function AddCircleZone(name, center, radius, options, targetoptions)
	local centerType = type(center)
	center = (centerType == 'table' or centerType == 'vector4') and vec3(center.x, center.y, center.z) or center
	Zones[name] = CircleZone:Create(center, radius, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end

exports('AddCircleZone', AddCircleZone)

function AddBoxZone(name, center, length, width, options, targetoptions)
	local centerType = type(center)
	center = (centerType == 'table' or centerType == 'vector4') and vec3(center.x, center.y, center.z) or center
	Zones[name] = BoxZone:Create(center, length, width, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end

exports('AddBoxZone', AddBoxZone)

function AddPolyZone(name, points, options, targetoptions)
	local _points = {}
	local pointsType = type(points[1])
	if pointsType == 'table' or pointsType == 'vector3' or pointsType == 'vector4' then
		for i = 1, #points do
			_points[i] = vec2(points[i].x, points[i].y)
		end
	end
	Zones[name] = PolyZone:Create(#_points > 0 and _points or points, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end

exports('AddPolyZone', AddPolyZone)

function AddComboZone(zones, options, targetoptions)
	Zones[options.name] = ComboZone:Create(zones, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[options.name].targetoptions = targetoptions
	return Zones[options.name]
end

exports('AddComboZone', AddComboZone)

function AddEntityZone(name, entity, options, targetoptions)
	Zones[name] = EntityZone:Create(entity, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end

exports('AddEntityZone', AddEntityZone)

function RemoveZone(name)
	if not Zones[name] then return end
	if Zones[name].destroy then Zones[name]:destroy() end
	Zones[name] = nil
end

exports('RemoveZone', RemoveZone)

-- Bones

function AddTargetBone(bones, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(bones) == 'table' then
		for _, bone in pairs(bones) do
			if not Bones.Options[bone] then Bones.Options[bone] = {} end
			SetOptions(Bones.Options[bone], distance, options)
		end
	elseif type(bones) == 'string' then
		if not Bones.Options[bones] then Bones.Options[bones] = {} end
		SetOptions(Bones.Options[bones], distance, options)
	end
end

exports('AddTargetBone', AddTargetBone)

function RemoveTargetBone(bones, labels)
	if type(bones) == 'table' then
		for _, bone in pairs(bones) do
			if labels then
				if type(labels) == 'table' then
					for _, v in pairs(labels) do
						if Bones.Options[bone] then Bones.Options[bone][v] = nil end
					end
				elseif type(labels) == 'string' then
					if Bones.Options[bone] then Bones.Options[bone][labels] = nil end
				end
			else
				Bones.Options[bone] = nil
			end
		end
	else
		if labels then
			if type(labels) == 'table' then
				for _, v in pairs(labels) do
					if Bones.Options[bones] then Bones.Options[bones][v] = nil end
				end
			elseif type(labels) == 'string' then
				if Bones.Options[bones] then Bones.Options[bones][labels] = nil end
			end
		else
			Bones.Options[bones] = nil
		end
	end
end

exports('RemoveTargetBone', RemoveTargetBone)

-- Entities

function AddTargetEntity(entities, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(entities) == 'table' then
		for _, entity in pairs(entities) do
			if NetworkGetEntityIsNetworked(entity) then entity = NetworkGetNetworkIdFromEntity(entity) end
			if not Entities[entity] then Entities[entity] = {} end
			SetOptions(Entities[entity], distance, options)
		end
	elseif type(entities) == 'number' then
		if NetworkGetEntityIsNetworked(entities) then entities = NetworkGetNetworkIdFromEntity(entities) end
		if not Entities[entities] then Entities[entities] = {} end
		SetOptions(Entities[entities], distance, options)
	end
end

exports('AddTargetEntity', AddTargetEntity)

function RemoveTargetEntity(entities, labels)
	if type(entities) == 'table' then
		for _, entity in pairs(entities) do
			if NetworkGetEntityIsNetworked(entity) then entity = NetworkGetNetworkIdFromEntity(entity) end
			if labels then
				if type(labels) == 'table' then
					for _, v in pairs(labels) do
						if Entities[entity] then Entities[entity][v] = nil end
					end
				elseif type(labels) == 'string' then
					if Entities[entity] then Entities[entity][labels] = nil end
				end
			else
				Entities[entity] = nil
			end
		end
	elseif type(entities) == 'number' then
		if NetworkGetEntityIsNetworked(entities) then entities = NetworkGetNetworkIdFromEntity(entities) end
		if labels then
			if type(labels) == 'table' then
				for _, v in pairs(labels) do
					if Entities[entities] then Entities[entities][v] = nil end
				end
			elseif type(labels) == 'string' then
				if Entities[entities] then Entities[entities][labels] = nil end
			end
		else
			Entities[entities] = nil
		end
	end
end

exports('RemoveTargetEntity', RemoveTargetEntity)

-- Models

function AddTargetModel(models, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(models) == 'table' then
		for _, model in pairs(models) do
			if type(model) == 'string' then model = joaat(model) end
			if not Models[model] then Models[model] = {} end
			SetOptions(Models[model], distance, options)
		end
	else
		if type(models) == 'string' then models = joaat(models) end
		if not Models[models] then Models[models] = {} end
		SetOptions(Models[models], distance, options)
	end
end

exports('AddTargetModel', AddTargetModel)

function RemoveTargetModel(models, labels)
	if type(models) == 'table' then
		for _, model in pairs(models) do
			if type(model) == 'string' then model = joaat(model) end
			if labels then
				if type(labels) == 'table' then
					for _, v in pairs(labels) do
						if Models[model] then Models[model][v] = nil end
					end
				elseif type(labels) == 'string' then
					if Models[model] then Models[model][labels] = nil end
				end
			else
				Models[model] = nil
			end
		end
	else
		if type(models) == 'string' then models = joaat(models) end
		if labels then
			if type(labels) == 'table' then
				for _, v in pairs(labels) do
					if Models[models] then Models[models][v] = nil end
				end
			elseif type(labels) == 'string' then
				if Models[models] then Models[models][labels] = nil end
			end
		else
			Models[models] = nil
		end
	end
end

exports('RemoveTargetModel', RemoveTargetModel)

-- Global types

function AddGlobalType(type, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	SetOptions(Types[type], distance, options)
end

exports('AddGlobalType', AddGlobalType)

function AddGlobalPed(parameters) AddGlobalType(1, parameters) end

exports('AddGlobalPed', AddGlobalPed)

function AddGlobalVehicle(parameters) AddGlobalType(2, parameters) end

exports('AddGlobalVehicle', AddGlobalVehicle)

function AddGlobalObject(parameters) AddGlobalType(3, parameters) end

exports('AddGlobalObject', AddGlobalObject)

function AddGlobalPlayer(parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	SetOptions(Players, distance, options)
end

exports('AddGlobalPlayer', AddGlobalPlayer)

function RemoveGlobalType(typ, labels)
	if labels then
		if type(labels) == 'table' then
			for _, v in pairs(labels) do Types[typ][v] = nil end
		elseif type(labels) == 'string' then
			Types[typ][labels] = nil
		end
	else
		Types[typ] = {}
	end
end

exports('RemoveGlobalType', RemoveGlobalType)

function RemoveGlobalPed(labels) RemoveGlobalType(1, labels) end

exports('RemoveGlobalPed', RemoveGlobalPed)

function RemoveGlobalVehicle(labels) RemoveGlobalType(2, labels) end

exports('RemoveGlobalVehicle', RemoveGlobalVehicle)

function RemoveGlobalObject(labels) RemoveGlobalType(3, labels) end

exports('RemoveGlobalObject', RemoveGlobalObject)

function RemoveGlobalPlayer(labels)
	if labels then
		if type(labels) == 'table' then
			for _, v in pairs(labels) do Players[v] = nil end
		elseif type(labels) == 'string' then
			Players[labels] = nil
		end
	else
		Players = {}
	end
end

exports('RemoveGlobalPlayer', RemoveGlobalPlayer)

-- Getters

local function GetGlobalTypeData(type, label) return Types[type][label] end
exports('GetGlobalTypeData', GetGlobalTypeData)

local function GetZoneData(name) return Zones[name] end
exports('GetZoneData', GetZoneData)

local function GetTargetBoneData(bone, label) return Bones.Options[bone][label] end
exports('GetTargetBoneData', GetTargetBoneData)

local function GetTargetEntityData(entity, label) return Entities[entity][label] end
exports('GetTargetEntityData', GetTargetEntityData)

local function GetTargetModelData(model, label) return Models[model][label] end
exports('GetTargetModelData', GetTargetModelData)

local function GetGlobalPedData(label) return Types[1][label] end
exports('GetGlobalPedData', GetGlobalPedData)

local function GetGlobalVehicleData(label) return Types[2][label] end
exports('GetGlobalVehicleData', GetGlobalVehicleData)

local function GetGlobalObjectData(label) return Types[3][label] end
exports('GetGlobalObjectData', GetGlobalObjectData)

local function GetGlobalPlayerData(label) return Players[label] end
exports('GetGlobalPlayerData', GetGlobalPlayerData)

-- Setters

local function UpdateGlobalTypeData(type, label, data) Types[type][label] = data end
exports('UpdateGlobalTypeData', UpdateGlobalTypeData)

local function UpdateZoneData(name, data)
	data.distance = data.distance or Config.MaxDistance
	Zones[name].targetoptions = data
end
exports('UpdateZoneData', UpdateZoneData)

local function UpdateTargetBoneData(bone, label, data) Bones.Options[bone][label] = data end
exports('UpdateTargetBoneData', UpdateTargetBoneData)

local function UpdateTargetEntityData(entity, label, data) Entities[entity][label] = data end
exports('UpdateTargetEntityData', UpdateTargetEntityData)

local function UpdateTargetModelData(model, label, data) Models[model][label] = data end
exports('UpdateTargetModelData', UpdateTargetModelData)

local function UpdateGlobalPedData(label, data) Types[1][label] = data end
exports('UpdateGlobalPedData', UpdateGlobalPedData)

local function UpdateGlobalVehicleData(label, data) Types[2][label] = data end
exports('UpdateGlobalVehicleData', UpdateGlobalVehicleData)

local function UpdateGlobalObjectData(label, data) Types[3][label] = data end
exports('UpdateGlobalObjectData', UpdateGlobalObjectData)

local function UpdateGlobalPlayerData(label, data) Players[label] = data end
exports('UpdateGlobalPlayerData', UpdateGlobalPlayerData)
