--!strict

-- Example server-side fall damage integration.
--
-- Place this Script in ServerScriptService only if your experience needs this
-- sample. Prefer adapting your existing fall-damage system to call
-- GodNDSService:ApplyDamage instead of maintaining two fall-damage scripts.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GodNDSService = require(
	ServerScriptService:WaitForChild("GodNDSService")
)

local service = GodNDSService.GetActive()
local serviceDeadline = os.clock() + 10
while service == nil and os.clock() < serviceDeadline do
	task.wait(0.05)
	service = GodNDSService.GetActive()
end
assert(service ~= nil, "GodNDS.server.lua must start before FallDamage.server.lua")

local SAFE_FALL_DISTANCE = 22
local DAMAGE_PER_STUD = 4

local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function disconnectAll(connections: { RBXScriptConnection }?)
	if not connections then
		return
	end
	for index = #connections, 1, -1 do
		local connection = connections[index]
		connections[index] = nil
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

local function getRootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function bindCharacter(player: Player, character: Model)
	disconnectAll(characterConnections[player])
	characterConnections[player] = {}

	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local fallStartY: number? = nil
	table.insert(
		characterConnections[player],
		humanoid.StateChanged:Connect(function(_oldState, newState)
			local root = getRootPart(character)
			if not root then
				fallStartY = nil
				return
			end

			if newState == Enum.HumanoidStateType.Freefall then
				fallStartY = root.Position.Y
				return
			end

			if
				newState ~= Enum.HumanoidStateType.Landed
				and newState ~= Enum.HumanoidStateType.Running
				and newState ~= Enum.HumanoidStateType.RunningNoPhysics
			then
				return
			end

			local startY = fallStartY
			fallStartY = nil
			if startY == nil then
				return
			end

			local fallDistance = startY - root.Position.Y
			if fallDistance <= SAFE_FALL_DISTANCE then
				return
			end

			-- Prevent damage at its source. ApplyDamage repeats the protection
			-- check so this remains safe if the state changes during this event.
			if player:GetAttribute("GodMode") == true then
				return
			end

			local damage = (fallDistance - SAFE_FALL_DISTANCE) * DAMAGE_PER_STUD
			service:ApplyDamage(humanoid, damage, {
				Kind = "Fall",
			})
		end)
	)
end

local function unregisterPlayer(player: Player)
	disconnectAll(characterConnections[player])
	disconnectAll(playerConnections[player])
	characterConnections[player] = nil
	playerConnections[player] = nil
end

local function registerPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	playerConnections[player] = {}

	table.insert(
		playerConnections[player],
		player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
	)
	table.insert(
		playerConnections[player],
		player.CharacterRemoving:Connect(function()
			disconnectAll(characterConnections[player])
			characterConnections[player] = nil
		end)
	)

	if player.Character then
		bindCharacter(player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	registerPlayer(player)
end

local playerAddedConnection = Players.PlayerAdded:Connect(registerPlayer)
local playerRemovingConnection = Players.PlayerRemoving:Connect(unregisterPlayer)

script.Destroying:Connect(function()
	if playerAddedConnection.Connected then
		playerAddedConnection:Disconnect()
	end
	if playerRemovingConnection.Connected then
		playerRemovingConnection:Disconnect()
	end
	for player in pairs(playerConnections) do
		unregisterPlayer(player)
	end
end)
