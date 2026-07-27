# lvyzge Admin

**lvyzge Admin** is the project, and **Lvyzge Executor** is its command interface. The application provides a responsive command bar, searchable command reference, autocomplete, keyboard navigation, command feedback, and persistent preferences.

This repository is intended only for software and experiences you own or are authorized to administer. The production registry does not expose anti-cheat bypasses, client injection, other-player attack commands, or arbitrary URL loading. Historical implementations retained for audit are registered through `cmd.addDisabled`, so they do not appear in autocomplete, generated command metadata, or command execution.

## Architecture

- `Source.lua` is the production client command runtime.
- `NA testing.lua` is the testing build and must expose the same public commands.
- `NAUI.lua` and `NAUITEST.lua` define the production and testing interfaces.
- `commands.json` is generated command metadata used by documentation and validation.
- `extract_commands.py` generates and validates `commands.json`.
- `roblox/GodNDS/ServerScriptService/GodNDSService.lua` contains the trusted GodNDS service.
- `roblox/GodNDS/ServerScriptService/GodNDS.server.lua` installs the server bridge and authorization policy.
- `roblox/GodNDS/examples/FallDamage.server.lua` demonstrates source-level fall-damage integration.

Existing settings remain under the `Nameless-Admin/` storage namespace for backward compatibility. Renaming the product does not erase or silently relocate settings, aliases, keybinds, plugins, history, or other saved data.

## GodNDS

`godnds` is a server-authoritative God-mode request. The command bar is only the client bridge: it cannot grant permission or protection by itself.

### Install

1. Copy `GodNDSService.lua` into `ServerScriptService/GodNDSService`.
2. Copy `GodNDS.server.lua` into `ServerScriptService/GodNDS`.
3. Configure the authorized user IDs in the server script.
4. Adapt damage systems to call `GodNDSService:ApplyDamage(...)` instead of changing `Humanoid.Health` directly.
5. Use `examples/FallDamage.server.lua` as the integration pattern for an existing fall-damage system.
6. Start a server test session and verify authorization before testing commands.

Do not place the server scripts in a client container. Server authorization must remain in `ServerScriptService`, and every toggle request is validated again by the server.

### Commands

| Command | Aliases | Result |
|---|---|---|
| `godnds [on\|off\|status]` | `godmode`, `god` | Requests a state or displays replicated server status |
| `ungodnds` | `ungodmode`, `ungod` | Requests disabled protection |

Examples:

```text
godnds
godnds status
godnds off
ungodnds
```

The interface reports these expected outcomes:

- GodNDS is not installed on the server.
- The player is not authorized.
- Protection is already in the requested state.
- The request failed.
- The server accepted the request and replicated the new state.

The server remains the source of truth. Client attributes and notifications are status indicators, not authorization controls.

### Studio test checklist

- An authorized player can run `godnds` and `ungodnds`.
- An unauthorized player cannot toggle protection by invoking the remote directly.
- A respawn preserves the intended state.
- R6 and R15 characters are protected.
- `Humanoid:TakeDamage()`, direct health assignment, explosions, projectiles, kill bricks, and physics hazards are covered.
- The fall-damage example skips damage at its source while protection is active.
- Repeated requests are rate-limited and do not create duplicate connections.
- Removing the Humanoid, destroying the character, breaking joints, moving the player into the void, or calling `LoadCharacter()` is treated as a separate lifecycle action, not ordinary damage.

## Command metadata

Generate metadata after changing command registrations:

```sh
python3 extract_commands.py
```

Validate freshness and reject duplicate canonical command names:

```sh
python3 extract_commands.py --check
```

Alias collisions are reported as warnings for legacy compatibility. Use strict validation when auditing or cleaning the remaining legacy collisions:

```sh
python3 extract_commands.py --check --strict-aliases
```

Run the static regression suite:

```sh
python3 -m unittest discover -s tests -v
```

## Development rules

- Keep production and testing command registrations synchronized.
- Keep quarantined legacy behavior on `cmd.addDisabled`; do not restore it to `cmd.add`.
- Keep security decisions on the server.
- Preserve the legacy storage namespace unless a tested, reversible migration is supplied.
- Vendor or commit-pin reviewed dependencies; never execute mutable remote source at startup.
- Never place access tokens in client code or forward authorization headers through a proxy.
- Update `commands.json`, tests, and documentation with every public command change.

See [SECURITY.md](SECURITY.md) for the trust model and reporting guidance.

## License

MIT. Preserve the original copyright and permission notice in [LICENSE](LICENSE) when modifying or redistributing substantial portions of the software.
