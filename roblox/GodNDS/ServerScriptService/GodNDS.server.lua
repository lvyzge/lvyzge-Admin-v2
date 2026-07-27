--!strict

-- GodNDS bootstrap and trusted server command bridge.
-- Place this Script beside GodNDSService in ServerScriptService.

local ServerScriptService = game:GetService("ServerScriptService")

local GodNDSService = require(script.Parent:WaitForChild("GodNDSService"))

-- Configure authorization before publishing.
local service = GodNDSService.new({
	AdminUserIds = {
		-- [123456789] = true,
	},

	-- The owner of a user-owned experience is authorized automatically.
	-- For group-owned experiences, only members at or above this rank qualify.
	AllowExperienceCreator = true,
	ExperienceGroupMinimumRank = 255,

	-- Optional second group. Leave the ID at 0 to disable it.
	AdditionalGroupId = 0,
	AdditionalGroupMinimumRank = 255,

	-- Keep false in published experiences. This is useful for local Studio tests.
	AllowAllStudioPlayers = false,

	RemoteName = "GodNDSToggle",
	ToggleCooldown = 0.5,

	EnableVoidRescue = true,
	VoidCheckInterval = 0.25,
	VoidMargin = 75,
	SafePositionRefreshInterval = 1,
	SafePositionLift = 4,
})

service:Start()

-- Trusted server admin systems may invoke this BindableFunction with:
--     bridge:Invoke(player, "on" | "off" | "toggle" | "status")
-- It is deliberately parented to ServerScriptService and never replicated.
local existingBridge = ServerScriptService:FindFirstChild("GodNDSAdminCommand")
assert(existingBridge == nil, "ServerScriptService already contains GodNDSAdminCommand")

local commandBridge = Instance.new("BindableFunction")
commandBridge.Name = "GodNDSAdminCommand"
commandBridge:SetAttribute("GodNDSManaged", true)
commandBridge.Parent = ServerScriptService

commandBridge.OnInvoke = function(player: any, rawAction: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid-player", false
	end
	if not service:IsAuthorized(player) then
		return false, "not-authorized", service:IsEnabled(player)
	end

	local action = tostring(rawAction or "status"):lower()
	action = action:match("^%s*(.-)%s*$") or action

	if action == "status" or action == "state" or action == "check" then
		local enabled = service:IsEnabled(player)
		return true, if enabled then "enabled" else "disabled", enabled
	end

	local requestedState: boolean
	if action == "on" or action == "enable" or action == "enabled" or action == "true" or action == "1" then
		requestedState = true
	elseif
		action == "off"
		or action == "disable"
		or action == "disabled"
		or action == "false"
		or action == "0"
	then
		requestedState = false
	elseif action == "toggle" then
		requestedState = not service:IsEnabled(player)
	else
		return false, "expected-on-off-toggle-or-status", service:IsEnabled(player)
	end

	local success, reason = service:SetEnabled(player, requestedState)
	return success, reason, service:IsEnabled(player)
end

local stopped = false
local function stop()
	if stopped then
		return
	end
	stopped = true

	if commandBridge.Parent and commandBridge:GetAttribute("GodNDSManaged") == true then
		commandBridge.OnInvoke = nil
		commandBridge:Destroy()
	end
	service:Stop()
end

script.Destroying:Connect(stop)
game:BindToClose(stop)
