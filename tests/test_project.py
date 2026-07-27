import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import extract_commands  # noqa: E402


SOURCE_PATHS = (ROOT / "Source.lua", ROOT / "NA testing.lua")
GOD_ALIASES = {"godnds", "godmode", "god"}
UNGOD_ALIASES = {"ungodnds", "ungodmode", "ungod"}


def read(path: Path):
	return path.read_text(encoding="utf-8")


def result_for(path: Path):
	return extract_commands.build_result(read(path))


def commands_with_alias(result, alias: str):
	return [
		command
		for section in ("commands", "patched_commands")
		for command in result[section]
		if alias in command["aliases"]
	]


class GodNDSProjectTests(unittest.TestCase):
	def test_server_package_enforces_the_request_boundary(self):
		service_path = ROOT / "roblox/GodNDS/ServerScriptService/GodNDSService.lua"
		bootstrap_path = ROOT / "roblox/GodNDS/ServerScriptService/GodNDS.server.lua"
		self.assertTrue(service_path.is_file())
		self.assertTrue(bootstrap_path.is_file())

		service = read(service_path)
		bootstrap = read(bootstrap_path)
		for marker in (
			"remote.OnServerEvent:Connect",
			'type(requestedState) ~= "boolean"',
			"self.Config.ToggleCooldown",
			"self:IsAuthorized(player)",
			"self:SetEnabled(player, requestedState)",
			"function GodNDSService:ApplyDamage",
		):
			self.assertIn(marker, service)

		self.assertIn("AllowAllStudioPlayers = false", bootstrap)
		self.assertIn("AdminUserIds", bootstrap)

	def test_server_package_avoids_deprecated_group_rank_api(self):
		service_path = ROOT / "roblox/GodNDS/ServerScriptService/GodNDSService.lua"
		service = read(service_path)
		self.assertIn("GroupService:GetRolesInGroupAsync", service)
		self.assertNotIn("GetRankInGroup", service)

	def test_godnds_is_registered_once_in_both_builds(self):
		for path in SOURCE_PATHS:
			with self.subTest(path=path.name):
				result = result_for(path)
				god_owners = commands_with_alias(result, "godnds")
				ungod_owners = commands_with_alias(result, "ungodnds")

				self.assertEqual(len(god_owners), 1)
				self.assertEqual(len(ungod_owners), 1)
				self.assertTrue(GOD_ALIASES.issubset(set(god_owners[0]["aliases"])))
				self.assertTrue(UNGOD_ALIASES.issubset(set(ungod_owners[0]["aliases"])))

				for alias in GOD_ALIASES:
					self.assertEqual(commands_with_alias(result, alias), god_owners)
				for alias in UNGOD_ALIASES:
					self.assertEqual(commands_with_alias(result, alias), ungod_owners)

	def test_godnds_uses_an_explicit_server_request(self):
		for path in SOURCE_PATHS:
			with self.subTest(path=path.name):
				source = read(path)
				self.assertIn('"GodNDSToggle"', source)
				self.assertIn('"GodNDSAuthorized"', source)
				self.assertIn('"GodMode"', source)
				self.assertRegex(
					source,
					r"FireServer\s*\(\s*requestedState\s*\)",
					"GodNDS must send the explicit desired Boolean state",
				)

	def test_legacy_client_hook_god_mode_is_removed(self):
		legacy_markers = (
			"NAmanage.God_HookMeta",
			"NAmanage.God_Enable",
			"NAmanage.God_AltRepSignal",
			"NAStuff._godTarget",
			"Godmode Methods",
		)
		for path in SOURCE_PATHS:
			with self.subTest(path=path.name):
				source = read(path)
				for marker in legacy_markers:
					self.assertNotIn(marker, source)

	def test_production_and_testing_godnds_metadata_match(self):
		production = result_for(SOURCE_PATHS[0])
		testing = result_for(SOURCE_PATHS[1])

		for alias in ("godnds", "ungodnds"):
			with self.subTest(alias=alias):
				self.assertEqual(
					commands_with_alias(production, alias),
					commands_with_alias(testing, alias),
				)


class GeneratedMetadataTests(unittest.TestCase):
	def test_commands_json_is_fresh(self):
		generated = result_for(ROOT / "Source.lua")
		checked_in = json.loads(read(ROOT / "commands.json"))
		self.assertEqual(checked_in, generated)

	def test_canonical_names_are_unique_and_god_aliases_have_one_owner(self):
		result = result_for(ROOT / "Source.lua")
		self.assertEqual(extract_commands.duplicate_canonical_names(result), {})

		collisions = extract_commands.duplicate_aliases(result)
		for alias in GOD_ALIASES | UNGOD_ALIASES:
			with self.subTest(alias=alias):
				self.assertNotIn(alias, collisions)


class BrandingAndCompatibilityTests(unittest.TestCase):
	def test_documentation_uses_product_brand_without_executor_loaders(self):
		readme = read(ROOT / "README.md")
		security = read(ROOT / "SECURITY.md")

		self.assertIn("# lvyzge Admin", readme)
		self.assertIn("Lvyzge Executor", readme)
		for document in (readme, security):
			self.assertNotIn("loadstring(", document)
			self.assertNotIn("game:HttpGet", document)

	def test_application_contains_lvyzge_executor_brand(self):
		application_text = "\n".join(
			read(path)
			for path in (
				ROOT / "Source.lua",
				ROOT / "NA testing.lua",
				ROOT / "NAUI.lua",
				ROOT / "NAUITEST.lua",
			)
		)
		self.assertIn("Lvyzge Executor", application_text)

	def test_legacy_storage_namespace_is_preserved(self):
		required_paths = (
			'NAFILEPATH = "Nameless-Admin"',
			'NAMAINSETTINGSPATH = "Nameless-Admin/Settings.json"',
			'NAALIASPATH = "Nameless-Admin/Aliases.json"',
			'NAAUTOEXECPATH = "Nameless-Admin/AutoExecCommands.json"',
			'NACOMMANDKEYBINDS = "Nameless-Admin/CommandKeybinds.json"',
		)
		for path in SOURCE_PATHS:
			with self.subTest(path=path.name):
				source = read(path)
				for persisted_path in required_paths:
					self.assertIn(persisted_path, source)


class CommandExperienceTests(unittest.TestCase):
	def test_history_navigation_and_quoted_arguments_are_present(self):
		for path in SOURCE_PATHS:
			with self.subTest(path=path.name):
				source = read(path)
				for marker in (
					"CommandHistoryNavigate",
					"cmdAutofillSelectedIndex",
					"MoveCmdAutofillSelection",
					"TokenizeCommandArguments",
					'"Unclosed quote in command input."',
				):
					self.assertIn(marker, source)

	def test_high_risk_legacy_commands_are_quarantined(self):
		result = result_for(ROOT / "Source.lua")
		exposed_aliases = {
			alias
			for section in ("commands", "patched_commands")
			for command in result[section]
			for alias in command["aliases"]
		}
		for alias in (
			"adonisbypass",
			"antikick",
			"spoofclientid",
			"blockremote",
			"bypassspeed",
			"tpwalk",
			"handlekill",
			"loopfling",
			"remotespy",
			"httpspy",
			"url",
		):
			with self.subTest(alias=alias):
				self.assertNotIn(alias, exposed_aliases)

		source = read(ROOT / "Source.lua")
		self.assertIn("cmd.addDisabled", source)
		self.assertNotIn(
			'local defaultBarCommands = { "settings", "commands", "cmdloop", "adonisbypass"',
			source,
		)

	def test_command_bar_theme_contract(self):
		for path in (ROOT / "NAUI.lua", ROOT / "NAUITEST.lua"):
			with self.subTest(path=path.name):
				ui = read(path)
				self.assertIn('Text = "Lvyzge Executor"', ui)
				self.assertIn("Color3.fromRGB(45, 212, 191)", ui)
				self.assertIn("Vector2.new(640, 52)", ui)


if __name__ == "__main__":
	unittest.main()
