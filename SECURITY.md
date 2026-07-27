# Security policy

## Scope

lvyzge Admin is designed for experiences and systems the operator owns or is explicitly authorized to administer. Security-sensitive behavior must use supported platform APIs and a trusted server boundary.

The project does not accept features whose purpose is client injection, anti-cheat evasion, remote-event abuse, unauthorized access, destructive interference with other users, hidden telemetry, or execution of unreviewed mutable remote code.

Legacy implementations with those characteristics are quarantined with
`cmd.addDisabled`. That code is retained only to make review and removal
traceable; it is not registered as a runnable command.

## Trust model

- The server is authoritative for permissions, damage, health, inventory, cooldowns, and command effects.
- Clients may request an action and display replicated status, but client attributes are not proof of authorization.
- `GodNDSToggle` requests must be authenticated, authorized, validated, and rate-limited by `GodNDS.server.lua`.
- GodNDS state is replicated for presentation; the server-owned state and `GodNDSService` decide whether damage is accepted.
- Plugins and downloaded source are untrusted until reviewed. A Lua environment wrapper is not a strong sandbox when privileged APIs remain reachable.
- Saved settings are local user data. The legacy `Nameless-Admin/` namespace is retained to avoid destructive migration.

## Dependency and network policy

- Prefer code committed in this repository.
- If a remote dependency is unavoidable, pin an immutable revision and verify its expected digest before execution.
- Require TLS certificate verification.
- Restrict requests to an explicit host allowlist.
- Never place GitHub tokens, cookies, webhook secrets, or other credentials in client-accessible code.
- Never forward authorization headers to mirrors, scraping services, or user-configurable proxies.
- Treat arbitrary URL execution and automatic plugin installation as unsafe.

## GodNDS safety requirements

The server installation must:

1. authorize by immutable server-side identity;
2. accept an explicit desired Boolean state;
3. reject malformed and excessive requests;
4. centralize supported damage through `GodNDSService`;
5. clean character and player connections on death, respawn, and removal; and
6. avoid busy loops and per-frame healing.

GodNDS protects against damage. Character destruction, Humanoid removal, joint destruction, void movement, and forced respawn are lifecycle operations and require separate, narrowly scoped server policy.

## Reporting a vulnerability

Open a private GitHub security advisory for the repository when available. Include:

- the affected revision and file;
- a concise impact description;
- minimal reproduction steps using an authorized test environment; and
- a suggested mitigation, if known.

Do not include live credentials, private player data, or instructions that enable abuse in a public issue. Allow maintainers reasonable time to investigate before public disclosure.
