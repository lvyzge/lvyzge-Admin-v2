# GodNDS

GodNDS is the server-authoritative god-mode package used by `godnds`. The
client may request a desired state, but only the server decides whether that
player is authorized and whether the state changes.

It uses normal Roblox Studio APIs. It is not an executor script and does not
contain anti-cheat bypasses, client injection, or hidden remote execution.

## Architecture

- `GodNDSService.lua` owns authorization, the request remote, replicated
  attributes, character protection, damage helpers, void rescue, and cleanup.
- `GodNDS.server.lua` contains the experience-specific configuration and a
  server-only `GodNDSAdminCommand` bridge for an existing admin system.
- `examples/FallDamage.server.lua` demonstrates preventing fall damage at its
  source and routing the remaining damage through `ApplyDamage`.

The public `GodNDSToggle` protocol accepts one explicit boolean:

```lua
toggleRemote:FireServer(true)  -- request enabled
toggleRemote:FireServer(false) -- request disabled
```

Requests are idempotent. Repeating `true` never turns protection off. Roblox
supplies the real sending `Player`; the server ignores invalid payloads,
enforces a cooldown, checks authorization again, and only changes that sender's
state.

## Installation

Create these exact Roblox Studio objects:

```text
ServerScriptService
├── GodNDSService       ModuleScript
└── GodNDS              Script
```

1. Paste `ServerScriptService/GodNDSService.lua` into the `GodNDSService`
   ModuleScript.
2. Paste `ServerScriptService/GodNDS.server.lua` into the `GodNDS` Script.
3. Edit `AdminUserIds` and the creator/group options near the top of
   `GodNDS.server.lua`.
4. Start a server test. The bootstrap creates `ReplicatedStorage.GodNDSToggle`
   and the server-only `ServerScriptService.GodNDSAdminCommand`.

No LocalScript is required by this package. The lvyzge Admin command bar is the
client command surface and should send the explicit boolean request shown
above.

For a private Studio test, either add your user ID or temporarily set
`AllowAllStudioPlayers = true`. Keep that option `false` in production.

## Command behavior

The lvyzge Admin command integration should expose:

```text
godnds             Request enabled
godnds on          Request enabled
godnds off         Request disabled
godnds status      Read the replicated state
ungodnds           Request disabled (compatibility alias)
god / godmode      Compatibility aliases
ungod / ungodmode  Compatibility aliases
```

The client can use these replicated attributes for status and feedback:

- `Player.GodNDSAuthorized`: server authorization result.
- `Player.GodMode`: requested state accepted by the server.
- `Character.GodMode`: the state applied to the current character.

Treat the attributes as display state, not permission proof. Client attribute
writes do not authorize anything; the remote handler always uses its own
server-side authorization record.

### Existing server admin systems

The bootstrap creates a server-only `BindableFunction`:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local bridge = ServerScriptService:WaitForChild("GodNDSAdminCommand")

local ok, reason, enabled = bridge:Invoke(player, "on")
print(ok, reason, enabled)
```

Accepted actions are `on`, `off`, `toggle`, and `status`. The bridge rejects an
unauthorized player. `toggle` exists only on this trusted server bridge; the
client remote remains explicit and idempotent.

## Centralized damage integration

Server damage systems should require the active service and call it instead of
writing `Humanoid.Health` directly:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local GodNDSService = require(ServerScriptService:WaitForChild("GodNDSService"))
local damageService = assert(GodNDSService.GetActive(), "GodNDS is not started")

-- Projectile or hazard damage
local applied, reason = damageService:ApplyDamage(targetHumanoid, 25, {
	Kind = "Projectile",
	Source = projectile,
})

-- A server kill brick
damageService:Kill(targetHumanoid, {
	Kind = "KillBrick",
	Source = killBrick,
})
```

`ApplyDamage` and `Kill` return `false, "protected"` when GodNDS blocks the
operation.

Use the centralized explosion helper instead of an ordinary damaging
`Explosion`:

```lua
damageService:CreateExplosion(hitPosition, {
	Radius = 18,
	Damage = 100,
	Pressure = 0,
	Visible = true,
})
```

The helper disables Roblox's automatic joint destruction and built-in pressure,
then applies damage once per Humanoid. Optional pressure is applied manually
and skips protected character assemblies.

## Fall damage

The best protection is to skip fall damage before it is calculated:

```lua
if player:GetAttribute("GodMode") == true then
	return
end

damageService:ApplyDamage(humanoid, calculatedDamage, {
	Kind = "Fall",
})
```

`examples/FallDamage.server.lua` is a complete server example with R6/R15
root-part support, respawn cleanup, and no frame loop. Do not install it beside
another fall-damage script without first removing or adapting the old one.

## Protection behavior

When enabled, GodNDS:

- preserves the state across respawns;
- sets `GodMode` on both the Player and current Character;
- adds an invisible ForceField;
- disables the Humanoid dead state and joint-breaking-on-death behavior;
- supports both R6 and R15 without rig-specific joints;
- restores direct Health or MaxHealth reductions using guarded property
  signals, not a per-frame healing loop;
- maintains one bounded server void-rescue loop for all protected players;
- disconnects character/player/service connections on respawn, leave, script
  destruction, and server shutdown.

## Limitations

No Humanoid health system can undo every destructive server operation after it
has happened:

- Destroying the Character or Humanoid cannot be cancelled by a HealthChanged
  connection.
- Destroying parts or breaking joints directly can leave a rig unusable even
  if its Humanoid survives.
- Calling `Player:LoadCharacter()` intentionally replaces the character.
- Moving a player into the void may destroy parts before a rescue tick if the
  movement script also destroys the character.

For owned server systems, prevent those operations at their source:

```lua
if damageService:IsProtected(player) then
	return
end

-- destructive operation here
```

If forced respawn is an intended admin action, decide explicitly whether it
should ignore god mode. Do not attempt to hook or bypass arbitrary client
scripts.

## Studio test checklist

Test with separate Server and Client views:

- An unauthorized player receives `GodNDSAuthorized = false` and cannot enable.
- An authorized player can request `true`; repeated `true` remains enabled.
- The cooldown rejects request spam without changing state.
- Requesting `false` disables and restores normal Humanoid properties.
- `TakeDamage()` through `ApplyDamage` is blocked while enabled.
- Direct server `Humanoid.Health` assignment is restored without an event loop.
- The example fall damage is skipped while enabled and applies while disabled.
- `CreateExplosion` damages an unprotected target and skips a protected target.
- A kill brick using `Kill` is blocked while enabled.
- Protection survives respawn.
- Run the checklist with both an R6 and R15 avatar.
- Move below `FallenPartsDestroyHeight + VoidMargin` and verify bounded rescue.
- Remove the player and stop the test; confirm no repeated warnings or orphaned
  `GodNDSForceField`, `GodNDSToggle`, or `GodNDSAdminCommand` objects remain.
