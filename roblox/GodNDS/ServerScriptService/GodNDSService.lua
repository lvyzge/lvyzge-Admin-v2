--!strict

-- GodNDSService
-- Server-authoritative god mode and centralized damage helpers.
--
-- Place this ModuleScript in ServerScriptService. Only the accompanying
-- GodNDS.server.lua bootstrap should start it.

local Debris = game:GetService("Debris")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GOD_MODE_ATTRIBUTE = "GodMode"
local AUTHORIZATION_ATTRIBUTE = "GodNDSAuthorized"
local MANAGED_ATTRIBUTE = "GodNDSManaged"
local FORCE_FIELD_NAME = "GodNDSForceField"

export type Config = {
	AdminUserIds: { [number]: boolean }?,
	AllowExperienceCreator: boolean?,
	ExperienceGroupMinimumRank: number?,
	AdditionalGroupId: number?,
	AdditionalGroupMinimumRank: number?,
	AllowAllStudioPlayers: boolean?,
	RemoteName: string?,
	ToggleCooldown: number?,
	EnableVoidRescue: boolean?,
	VoidCheckInterval: number?,
	VoidMargin: number?,
	SafePositionRefreshInterval: number?,
	SafePositionLift: number?,
}

export type DamageContext = {
	Kind: string?,
	Source: Instance?,
}

export type ExplosionOptions = {
	Radius: number?,
	Damage: number?,
	Pressure: number?,
	Visible: boolean?,
	Parent: Instance?,
}

type NormalizedConfig = {
	AdminUserIds: { [number]: boolean },
	AllowExperienceCreator: boolean,
	ExperienceGroupMinimumRank: number,
	AdditionalGroupId: number,
	AdditionalGroupMinimumRank: number,
	AllowAllStudioPlayers: boolean,
	RemoteName: string,
	ToggleCooldown: number,
	EnableVoidRescue: boolean,
	VoidCheckInterval: number,
	VoidMargin: number,
	SafePositionRefreshInterval: number,
	SafePositionLift: number,
}

type ProtectionRecord = {
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
	OriginalMaxHealth: number,
	OriginalHealth: number,
	OriginalBreakJointsOnDeath: boolean,
	OriginalRequiresNeck: boolean,
	OriginalDeadStateEnabled: boolean,
	ProtectedMaxHealth: number,
	ForceField: ForceField?,
	Connections: { RBXScriptConnection },
	Active: boolean,
	Restoring: boolean,
	RemovalWarned: boolean,
}

type PlayerRecord = {
	Player: Player,
	Authorized: boolean,
	Connections: { RBXScriptConnection },
	CharacterConnections: { RBXScriptConnection },
	Protection: ProtectionRecord?,
	Generation: number,
	SafeCFrame: CFrame?,
	LastSafeRefresh: number,
	LastVoidWarning: number,
}

local DEFAULT_CONFIG: NormalizedConfig = {
	AdminUserIds = {},
	AllowExperienceCreator = true,
	ExperienceGroupMinimumRank = 255,
	AdditionalGroupId = 0,
	AdditionalGroupMinimumRank = 255,
	AllowAllStudioPlayers = false,
	RemoteName = "GodNDSToggle",
	ToggleCooldown = 0.5,
	EnableVoidRescue = true,
	VoidCheckInterval = 0.25,
	VoidMargin = 75,
	SafePositionRefreshInterval = 1,
	SafePositionLift = 4,
}

local GodNDSService = {}
GodNDSService.__index = GodNDSService

local activeService: any = nil

local function finiteNumber(value: any, fallback: number): number
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue or math.abs(numberValue) == math.huge then
		return fallback
	end
	return numberValue
end

local function normalizeConfig(config: Config?): NormalizedConfig
	local source = config or {}
	local adminUserIds: { [number]: boolean } = {}

	if type(source.AdminUserIds) == "table" then
		for userId, enabled in pairs(source.AdminUserIds) do
			local numericId = tonumber(userId)
			if numericId and numericId > 0 and enabled == true then
				adminUserIds[math.floor(numericId)] = true
			end
		end
	end

	local remoteName = tostring(source.RemoteName or DEFAULT_CONFIG.RemoteName)
	if remoteName == "" then
		remoteName = DEFAULT_CONFIG.RemoteName
	end

	return {
		AdminUserIds = adminUserIds,
		AllowExperienceCreator = source.AllowExperienceCreator ~= false,
		ExperienceGroupMinimumRank = math.clamp(
			math.floor(finiteNumber(source.ExperienceGroupMinimumRank, DEFAULT_CONFIG.ExperienceGroupMinimumRank)),
			0,
			255
		),
		AdditionalGroupId = math.max(
			0,
			math.floor(finiteNumber(source.AdditionalGroupId, DEFAULT_CONFIG.AdditionalGroupId))
		),
		AdditionalGroupMinimumRank = math.clamp(
			math.floor(finiteNumber(source.AdditionalGroupMinimumRank, DEFAULT_CONFIG.AdditionalGroupMinimumRank)),
			0,
			255
		),
		AllowAllStudioPlayers = source.AllowAllStudioPlayers == true,
		RemoteName = remoteName,
		ToggleCooldown = math.clamp(
			finiteNumber(source.ToggleCooldown, DEFAULT_CONFIG.ToggleCooldown),
			0.1,
			10
		),
		EnableVoidRescue = source.EnableVoidRescue ~= false,
		VoidCheckInterval = math.clamp(
			finiteNumber(source.VoidCheckInterval, DEFAULT_CONFIG.VoidCheckInterval),
			0.1,
			5
		),
		VoidMargin = math.clamp(finiteNumber(source.VoidMargin, DEFAULT_CONFIG.VoidMargin), 0, 1000),
		SafePositionRefreshInterval = math.clamp(
			finiteNumber(source.SafePositionRefreshInterval, DEFAULT_CONFIG.SafePositionRefreshInterval),
			0.25,
			30
		),
		SafePositionLift = math.clamp(
			finiteNumber(source.SafePositionLift, DEFAULT_CONFIG.SafePositionLift),
			0,
			50
		),
	}
end

local function disconnectAll(connections: { RBXScriptConnection })
	for index = #connections, 1, -1 do
		local connection = connections[index]
		connections[index] = nil
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

local function findHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end
	local primaryPart = character.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function resolveHumanoid(target: any): Humanoid?
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Humanoid") then
		return target
	end
	if target:IsA("Player") then
		return findHumanoid(target.Character)
	end
	if target:IsA("Model") then
		return target:FindFirstChildOfClass("Humanoid")
	end
	if target:IsA("BasePart") then
		local model = target:FindFirstAncestorOfClass("Model")
		return if model then model:FindFirstChildOfClass("Humanoid") else nil
	end
	return nil
end

local function getPlayerFromHumanoid(humanoid: Humanoid?): Player?
	if not humanoid then
		return nil
	end
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function getDeadStateEnabled(humanoid: Humanoid): boolean
	local success, enabled = pcall(function()
		return humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead)
	end)
	return success and enabled == true
end

local function setDeadStateEnabled(humanoid: Humanoid, enabled: boolean)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, enabled)
	end)
end

local function zeroVelocity(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function groupRankAtLeast(player: Player, groupId: number, minimumRank: number): boolean
	if groupId <= 0 then
		return false
	end
	local success, membership = pcall(function()
		return GroupService:GetRolesInGroupAsync(player.UserId, groupId)
	end)
	if not success or type(membership) ~= "table" or membership.IsMember ~= true then
		return false
	end
	if minimumRank <= 0 then
		return true
	end

	local roles = membership.Roles
	if type(roles) ~= "table" then
		return false
	end
	for _, role in roles do
		if type(role) == "table" then
			local rank = tonumber(role.Rank)
			if rank and rank >= minimumRank then
				return true
			end
		end
	end
	return false
end

function GodNDSService.new(config: Config?)
	assert(RunService:IsServer(), "GodNDSService can only be created on the server")

	local self = setmetatable({
		Config = normalizeConfig(config),
		_started = false,
		_remote = nil :: RemoteEvent?,
		_records = {} :: { [Player]: PlayerRecord },
		_lastToggleAt = {} :: { [Player]: number },
		_serviceConnections = {} :: { RBXScriptConnection },
	}, GodNDSService)

	return self
end

function GodNDSService.GetActive()
	return activeService
end

function GodNDSService:_isAuthorized(player: Player): boolean
	local config: NormalizedConfig = self.Config

	if config.AdminUserIds[player.UserId] == true then
		return true
	end
	if config.AllowAllStudioPlayers and RunService:IsStudio() then
		return true
	end
	if config.AllowExperienceCreator then
		if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
			return true
		end
		if
			game.CreatorType == Enum.CreatorType.Group
			and groupRankAtLeast(player, game.CreatorId, config.ExperienceGroupMinimumRank)
		then
			return true
		end
	end
	return groupRankAtLeast(player, config.AdditionalGroupId, config.AdditionalGroupMinimumRank)
end

function GodNDSService:IsAuthorized(player: Player): boolean
	local record = self._records[player]
	return record ~= nil and record.Authorized == true
end

function GodNDSService:IsEnabled(player: Player): boolean
	return player:GetAttribute(GOD_MODE_ATTRIBUTE) == true
end

function GodNDSService:IsProtected(target: any): boolean
	local humanoid = resolveHumanoid(target)
	local player = getPlayerFromHumanoid(humanoid)
	if not player or not humanoid or player:GetAttribute(GOD_MODE_ATTRIBUTE) ~= true then
		return false
	end
	local record = self._records[player]
	local protection = record and record.Protection
	return protection ~= nil
		and protection.Active
		and protection.Humanoid == humanoid
		and protection.Character == humanoid.Parent
end

function GodNDSService:_restoreProtection(protection: ProtectionRecord)
	if protection.Restoring or not protection.Active then
		return
	end

	local humanoid = protection.Humanoid
	if humanoid.Parent ~= protection.Character or protection.Character.Parent == nil then
		return
	end

	protection.Restoring = true
	local success, restoreError = pcall(function()
		if humanoid.MaxHealth > protection.ProtectedMaxHealth then
			protection.ProtectedMaxHealth = humanoid.MaxHealth
		elseif humanoid.MaxHealth < protection.ProtectedMaxHealth then
			humanoid.MaxHealth = protection.ProtectedMaxHealth
		end

		local targetHealth = math.max(protection.ProtectedMaxHealth, humanoid.MaxHealth)
		if humanoid.Health < targetHealth then
			humanoid.Health = targetHealth
		end
		if humanoid.BreakJointsOnDeath then
			humanoid.BreakJointsOnDeath = false
		end
		if humanoid.RequiresNeck then
			humanoid.RequiresNeck = false
		end
		setDeadStateEnabled(humanoid, false)
		if humanoid:GetState() == Enum.HumanoidStateType.Dead then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	protection.Restoring = false

	if not success then
		warn("[GodNDS] Could not restore protected Humanoid:", restoreError)
	end
end

function GodNDSService:_releaseProtection(record: PlayerRecord, restoreOriginal: boolean)
	local protection = record.Protection
	if not protection then
		return
	end

	record.Protection = nil
	protection.Active = false
	disconnectAll(protection.Connections)

	local forceField = protection.ForceField
	if forceField and forceField.Parent then
		forceField:Destroy()
	end
	protection.ForceField = nil

	local humanoid = protection.Humanoid
	if restoreOriginal and humanoid.Parent == protection.Character then
		protection.Restoring = true
		local success, restoreError = pcall(function()
			humanoid.BreakJointsOnDeath = protection.OriginalBreakJointsOnDeath
			humanoid.RequiresNeck = protection.OriginalRequiresNeck
			setDeadStateEnabled(humanoid, protection.OriginalDeadStateEnabled)
			humanoid.MaxHealth = protection.OriginalMaxHealth
			humanoid.Health = math.clamp(humanoid.Health, 0, protection.OriginalMaxHealth)
		end)
		protection.Restoring = false
		if not success then
			warn("[GodNDS] Could not restore original Humanoid properties:", restoreError)
		end
	end
end

function GodNDSService:_enableProtection(record: PlayerRecord, character: Model, humanoid: Humanoid)
	if record.Protection then
		if record.Protection.Character == character and record.Protection.Humanoid == humanoid then
			self:_restoreProtection(record.Protection)
			return
		end
		self:_releaseProtection(record, false)
	end

	local originalMaxHealth = math.max(1, finiteNumber(humanoid.MaxHealth, 100))
	local originalHealth = math.clamp(finiteNumber(humanoid.Health, originalMaxHealth), 0, originalMaxHealth)
	local protection: ProtectionRecord = {
		Player = record.Player,
		Character = character,
		Humanoid = humanoid,
		OriginalMaxHealth = originalMaxHealth,
		OriginalHealth = originalHealth,
		OriginalBreakJointsOnDeath = humanoid.BreakJointsOnDeath,
		OriginalRequiresNeck = humanoid.RequiresNeck,
		OriginalDeadStateEnabled = getDeadStateEnabled(humanoid),
		ProtectedMaxHealth = originalMaxHealth,
		ForceField = nil,
		Connections = {},
		Active = true,
		Restoring = false,
		RemovalWarned = false,
	}
	record.Protection = protection

	local existingForceField = character:FindFirstChild(FORCE_FIELD_NAME)
	if
		existingForceField
		and existingForceField:IsA("ForceField")
		and existingForceField:GetAttribute(MANAGED_ATTRIBUTE) == true
	then
		existingForceField:Destroy()
	end

	local forceField = Instance.new("ForceField")
	forceField.Name = FORCE_FIELD_NAME
	forceField.Visible = false
	forceField:SetAttribute(MANAGED_ATTRIBUTE, true)
	forceField.Parent = character
	protection.ForceField = forceField

	local function restore()
		self:_restoreProtection(protection)
	end

	table.insert(protection.Connections, humanoid.HealthChanged:Connect(restore))
	table.insert(protection.Connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(restore))
	table.insert(protection.Connections, humanoid:GetPropertyChangedSignal("BreakJointsOnDeath"):Connect(restore))
	table.insert(protection.Connections, humanoid:GetPropertyChangedSignal("RequiresNeck"):Connect(restore))
	table.insert(
		protection.Connections,
		humanoid.StateChanged:Connect(function(_oldState, newState)
			if newState == Enum.HumanoidStateType.Dead then
				restore()
			end
		end)
	)
	table.insert(protection.Connections, humanoid.Died:Connect(restore))
	table.insert(
		protection.Connections,
		humanoid.AncestryChanged:Connect(function(_child, parent)
			if parent ~= character and protection.Active and not protection.RemovalWarned then
				protection.RemovalWarned = true
				warn(
					"[GodNDS] A script removed the protected Humanoid for",
					record.Player.Name,
					"; health protection cannot restore a removed instance."
				)
			end
		end)
	)

	character:SetAttribute(GOD_MODE_ATTRIBUTE, true)
	self:_restoreProtection(protection)
end

function GodNDSService:_tryEnable(record: PlayerRecord)
	if not record.Authorized or record.Player:GetAttribute(GOD_MODE_ATTRIBUTE) ~= true then
		return
	end
	local character = record.Player.Character
	if not character then
		return
	end
	local humanoid = findHumanoid(character)
	if humanoid then
		self:_enableProtection(record, character, humanoid)
	end
end

function GodNDSService:_applyState(record: PlayerRecord)
	local enabled = record.Authorized and record.Player:GetAttribute(GOD_MODE_ATTRIBUTE) == true
	local character = record.Player.Character
	if character then
		character:SetAttribute(GOD_MODE_ATTRIBUTE, enabled)
	end

	if enabled then
		self:_tryEnable(record)
	else
		self:_releaseProtection(record, true)
		record.SafeCFrame = nil
	end
end

function GodNDSService:_setEnabledInternal(player: Player, enabled: boolean)
	player:SetAttribute(GOD_MODE_ATTRIBUTE, enabled)
	local character = player.Character
	if character then
		character:SetAttribute(GOD_MODE_ATTRIBUTE, enabled)
	end
	local record = self._records[player]
	if record then
		self:_applyState(record)
	end
end

function GodNDSService:SetEnabled(player: Player, enabled: boolean): (boolean, string)
	if not self._started then
		return false, "service-not-started"
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "invalid-player"
	end
	if type(enabled) ~= "boolean" then
		return false, "state-must-be-boolean"
	end
	if not self:IsAuthorized(player) then
		return false, "not-authorized"
	end
	if self:IsEnabled(player) == enabled then
		return true, if enabled then "already-enabled" else "already-disabled"
	end

	self:_setEnabledInternal(player, enabled)
	return true, if enabled then "enabled" else "disabled"
end

function GodNDSService:_onCharacterAdded(record: PlayerRecord, character: Model)
	record.Generation += 1
	local generation = record.Generation
	disconnectAll(record.CharacterConnections)
	self:_releaseProtection(record, false)
	record.SafeCFrame = nil
	record.LastSafeRefresh = 0
	record.LastVoidWarning = 0

	character:SetAttribute(
		GOD_MODE_ATTRIBUTE,
		record.Authorized and record.Player:GetAttribute(GOD_MODE_ATTRIBUTE) == true
	)

	table.insert(
		record.CharacterConnections,
		character.ChildAdded:Connect(function(child)
			if
				child:IsA("Humanoid")
				and self._records[record.Player] == record
				and record.Generation == generation
			then
				self:_tryEnable(record)
			end
		end)
	)
	table.insert(
		record.CharacterConnections,
		character.Destroying:Connect(function()
			if record.Generation == generation then
				self:_releaseProtection(record, false)
				record.SafeCFrame = nil
			end
		end)
	)

	local root = getRootPart(character)
	if root then
		record.SafeCFrame = root.CFrame
		record.LastSafeRefresh = os.clock()
	end
	self:_tryEnable(record)
end

function GodNDSService:_unregisterPlayer(player: Player)
	local record = self._records[player]
	if not record then
		return
	end

	self._records[player] = nil
	self._lastToggleAt[player] = nil
	record.Generation += 1
	disconnectAll(record.CharacterConnections)
	disconnectAll(record.Connections)
	self:_releaseProtection(record, false)
end

function GodNDSService:_registerPlayer(player: Player)
	if self._records[player] then
		return
	end

	player:SetAttribute(GOD_MODE_ATTRIBUTE, false)
	player:SetAttribute(AUTHORIZATION_ATTRIBUTE, false)

	local record: PlayerRecord = {
		Player = player,
		Authorized = false,
		Connections = {},
		CharacterConnections = {},
		Protection = nil,
		Generation = 0,
		SafeCFrame = nil,
		LastSafeRefresh = 0,
		LastVoidWarning = 0,
	}
	self._records[player] = record

	table.insert(
		record.Connections,
		player:GetAttributeChangedSignal(GOD_MODE_ATTRIBUTE):Connect(function()
			local state = player:GetAttribute(GOD_MODE_ATTRIBUTE)
			if type(state) ~= "boolean" or (state == true and not record.Authorized) then
				self:_setEnabledInternal(player, false)
				return
			end
			self:_applyState(record)
		end)
	)
	table.insert(
		record.Connections,
		player.CharacterAdded:Connect(function(character)
			self:_onCharacterAdded(record, character)
		end)
	)
	table.insert(
		record.Connections,
		player.CharacterRemoving:Connect(function(_character)
			record.Generation += 1
			disconnectAll(record.CharacterConnections)
			self:_releaseProtection(record, false)
			record.SafeCFrame = nil
		end)
	)

	if player.Character then
		self:_onCharacterAdded(record, player.Character)
	end

	task.spawn(function()
		local authorized = self:_isAuthorized(player)
		if not self._started or self._records[player] ~= record or player.Parent ~= Players then
			return
		end
		record.Authorized = authorized
		player:SetAttribute(AUTHORIZATION_ATTRIBUTE, authorized)
		if not authorized then
			self:_setEnabledInternal(player, false)
		end
	end)
end

function GodNDSService:_fallbackSafeCFrame(player: Player): CFrame?
	local respawnLocation = player.RespawnLocation
	if respawnLocation and respawnLocation:IsDescendantOf(Workspace) then
		return respawnLocation.CFrame
	end
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawnLocation and spawnLocation:IsA("SpawnLocation") then spawnLocation.CFrame else nil
end

function GodNDSService:_inspectVoid(record: PlayerRecord, now: number)
	if not record.Authorized or record.Player:GetAttribute(GOD_MODE_ATTRIBUTE) ~= true then
		return
	end

	local character = record.Player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return
	end
	local humanoid = findHumanoid(character)
	local root = getRootPart(character)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local destroyHeight = finiteNumber(Workspace.FallenPartsDestroyHeight, -500)
	local rescueHeight = destroyHeight + self.Config.VoidMargin
	if root.Position.Y <= rescueHeight then
		local safeCFrame = record.SafeCFrame or self:_fallbackSafeCFrame(record.Player)
		if safeCFrame then
			character:PivotTo(safeCFrame + Vector3.new(0, self.Config.SafePositionLift, 0))
			zeroVelocity(character)
			record.SafeCFrame = safeCFrame
			record.LastSafeRefresh = now
		elseif now - record.LastVoidWarning >= 5 then
			record.LastVoidWarning = now
			warn("[GodNDS] No safe void-rescue position for", record.Player.Name)
		end
		return
	end

	if
		record.SafeCFrame == nil
		or (
			now - record.LastSafeRefresh >= self.Config.SafePositionRefreshInterval
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and math.abs(root.AssemblyLinearVelocity.Y) < 12
		)
	then
		record.SafeCFrame = root.CFrame
		record.LastSafeRefresh = now
	end
end

function GodNDSService:ApplyDamage(target: any, amount: number, _context: DamageContext?): (boolean, string)
	local humanoid = resolveHumanoid(target)
	if not humanoid or humanoid.Parent == nil then
		return false, "humanoid-not-found"
	end

	local damage = finiteNumber(amount, -1)
	if damage <= 0 then
		return false, "damage-must-be-positive"
	end
	if self:IsProtected(humanoid) then
		return false, "protected"
	end

	humanoid:TakeDamage(damage)
	return true, "applied"
end

function GodNDSService:Kill(target: any, _context: DamageContext?): (boolean, string)
	local humanoid = resolveHumanoid(target)
	if not humanoid or humanoid.Parent == nil then
		return false, "humanoid-not-found"
	end
	if self:IsProtected(humanoid) then
		return false, "protected"
	end

	humanoid.Health = 0
	return true, "killed"
end

function GodNDSService:CreateExplosion(position: Vector3, options: ExplosionOptions?): Explosion
	assert(typeof(position) == "Vector3", "CreateExplosion position must be a Vector3")

	local resolvedOptions = options or {}
	local radius = math.clamp(finiteNumber(resolvedOptions.Radius, 12), 0.1, 500)
	local maximumDamage = math.clamp(finiteNumber(resolvedOptions.Damage, 100), 0, 1_000_000)
	local pressure = math.clamp(finiteNumber(resolvedOptions.Pressure, 0), 0, 1_000_000)
	local parent = resolvedOptions.Parent
	if typeof(parent) ~= "Instance" then
		parent = Workspace
	end

	-- Roblox's built-in joint breaking and pressure are disabled. Damage and
	-- optional impulse are applied below so protected characters can be skipped.
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Visible = resolvedOptions.Visible ~= false
	explosion.Parent = parent
	Debris:AddItem(explosion, 2)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local parts = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	local seenHumanoids: { [Humanoid]: boolean } = {}
	local seenAssemblies: { [BasePart]: boolean } = {}

	for _, part in ipairs(parts) do
		local humanoid = resolveHumanoid(part)
		if humanoid and not seenHumanoids[humanoid] then
			seenHumanoids[humanoid] = true
			local root = getRootPart(humanoid.Parent :: Model)
			local samplePosition = if root then root.Position else part.Position
			local alpha = 1 - math.clamp((samplePosition - position).Magnitude / radius, 0, 1)
			if maximumDamage > 0 and alpha > 0 then
				self:ApplyDamage(humanoid, maximumDamage * alpha, {
					Kind = "Explosion",
					Source = explosion,
				})
			end
		end

		if pressure > 0 then
			local assembly = part.AssemblyRootPart or part
			if not assembly.Anchored and not seenAssemblies[assembly] then
				seenAssemblies[assembly] = true
				local assemblyHumanoid = resolveHumanoid(assembly)
				if not self:IsProtected(assemblyHumanoid) then
					local offset = assembly.Position - position
					local distance = offset.Magnitude
					if distance > 0 and distance < radius then
						local alpha = 1 - math.clamp(distance / radius, 0, 1)
						assembly:ApplyImpulse(offset.Unit * pressure * alpha * assembly.AssemblyMass)
					end
				end
			end
		end
	end

	return explosion
end

function GodNDSService:Start()
	if self._started then
		return self
	end
	assert(activeService == nil or activeService == self, "Another GodNDSService is already active")

	local remoteName: string = self.Config.RemoteName
	local existing = ReplicatedStorage:FindFirstChild(remoteName)
	assert(existing == nil, ReplicatedStorage:GetFullName() .. " already contains " .. remoteName)

	self._started = true
	activeService = self

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote:SetAttribute(MANAGED_ATTRIBUTE, true)
	remote:SetAttribute("ProtocolVersion", 2)
	remote:SetAttribute("Purpose", "AuthorizedAdminExplicitSelfState")
	remote.Parent = ReplicatedStorage
	self._remote = remote

	table.insert(
		self._serviceConnections,
		remote.OnServerEvent:Connect(function(player, requestedState)
			-- The sender is supplied by Roblox and cannot be spoofed. The only
			-- accepted payload is the desired boolean state for that same player.
			if type(requestedState) ~= "boolean" then
				return
			end

			local now = os.clock()
			if now - (self._lastToggleAt[player] or 0) < self.Config.ToggleCooldown then
				return
			end
			self._lastToggleAt[player] = now

			if not self:IsAuthorized(player) then
				return
			end
			self:SetEnabled(player, requestedState)
		end)
	)
	table.insert(
		self._serviceConnections,
		Players.PlayerAdded:Connect(function(player)
			self:_registerPlayer(player)
		end)
	)
	table.insert(
		self._serviceConnections,
		Players.PlayerRemoving:Connect(function(player)
			self:_unregisterPlayer(player)
		end)
	)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_registerPlayer(player)
	end

	if self.Config.EnableVoidRescue then
		task.spawn(function()
			while self._started do
				task.wait(self.Config.VoidCheckInterval)
				if not self._started then
					break
				end
				local now = os.clock()
				for _, record in pairs(self._records) do
					local success, inspectError = pcall(function()
						self:_inspectVoid(record, now)
					end)
					if not success then
						warn("[GodNDS] Void rescue check failed:", inspectError)
					end
				end
			end
		end)
	end

	return self
end

function GodNDSService:Stop()
	if not self._started then
		return
	end

	self._started = false
	disconnectAll(self._serviceConnections)

	local playersToRemove = {}
	for player in pairs(self._records) do
		table.insert(playersToRemove, player)
	end
	for _, player in ipairs(playersToRemove) do
		self:_setEnabledInternal(player, false)
		player:SetAttribute(AUTHORIZATION_ATTRIBUTE, false)
		self:_unregisterPlayer(player)
	end

	table.clear(self._lastToggleAt)
	local remote = self._remote
	self._remote = nil
	if remote and remote.Parent and remote:GetAttribute(MANAGED_ATTRIBUTE) == true then
		remote:Destroy()
	end

	if activeService == self then
		activeService = nil
	end
end

return GodNDSService
