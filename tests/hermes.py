#!/usr/bin/env python3
"""Hermes policy and opaque config-preservation fixtures, no provider calls."""

import errno
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    result = types.ModuleType(name)
    exec(compile(path.read_bytes(), str(path), "exec"), result.__dict__)
    return result


class HermesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.repo = self.home / "Projects/work"
        self.repo.mkdir(parents=True)
        (self.repo / ".git").mkdir()
        self.profile = self.home / ".hermes"
        self.profile.mkdir(mode=0o700)
        self.config = self.profile / "config.yaml"
        self.env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "TMPDIR": os.environ.get("TMPDIR", tempfile.gettempdir()),
                    "HOME": str(self.home), "HERMES_HOME": str(self.profile), "HISTFILE": "/dev/null",
                    "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_DATA_HOME": str(self.home / ".local/share"),
                    "XDG_CACHE_HOME": str(self.home / ".cache"),
                    "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
        environment = patch.dict(os.environ, self.env, clear=True)
        environment.start()
        self.addCleanup(environment.stop)

    def reconcile(self, mode="install", success=True):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/reconcile-hermes-config.py"),
                                 mode, str(ROOT)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        self.assertNotIn("private-fixture-value", result.stdout + result.stderr)
        return result

    def host(self, value):
        self.config.write_text(yaml.safe_dump(value), encoding="utf-8")
        self.config.chmod(0o600)

    def test_defaults_preservation_and_idempotence(self):
        original = {"providers": {"fixture": {"api_key": "private-fixture-value"}},
                    "skills": {"external_dirs": ["/team/skills"], "trusted_project_dirs": ["/work"]},
                    "plugins": {"enabled": ["other"]}, "display": {"compact": True}}
        self.host(original)
        soul = self.profile / "SOUL.md"
        soul.write_text("Hermes identity", encoding="utf-8")
        self.reconcile()
        data = yaml.safe_load(self.config.read_text())
        self.assertEqual(data["providers"], original["providers"])
        self.assertEqual(data["skills"]["trusted_project_dirs"], ["/work"])
        self.assertEqual(data["plugins"]["enabled"], ["other", "eyragents"])
        self.assertEqual(data["skills"]["external_dirs"], ["/team/skills", "~/.agents/skills"])
        self.assertEqual(data["model"]["default"], "gpt-6-astra")
        self.assertEqual(data["agent"]["reasoning_effort"], "xhigh")
        self.assertEqual(data["agent"]["coding_context"], "auto")
        self.assertNotIn("disabled_toolsets", data["agent"])
        self.assertTrue(data["memory"]["memory_enabled"])
        self.assertTrue(data["curator"]["enabled"])
        self.assertIn("Native learning", data["agent"]["environment_hint"])
        self.assertEqual(soul.read_text(), "Hermes identity")
        before = self.config.stat().st_mtime_ns
        self.reconcile()
        self.reconcile("check")
        self.assertEqual(self.config.stat().st_mtime_ns, before)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_refuse_invalid_or_ambiguous_host_unchanged(self):
        for content in ("model: [private-fixture-value", "model: one\nmodel: two\n",
                        "thing: &anchor private-fixture-value\nother: *anchor\n"):
            self.config.write_text(content)
            self.config.chmod(0o600)
            self.reconcile(success=False)
            self.assertEqual(self.config.read_text(), content)
        for value in ({"plugins": {"disabled": ["eyragents"]}},
                      {"model": {"base_url": "https://example.invalid"}},
                      {"model": {"base_url": "https://chatgpt.com.example.invalid/backend-api/codex"}},
                      {"model": {"base_url": "https://chatgpt.com/backend-api/codex?route=other"}},
                      {"model": {"api_key": "private-fixture-value"}},
                      {"model": {"model": "different-model"}},
                      {"skills": {"external_dirs": "wrong-shape"}}):
            self.host(value)
            before = self.config.read_bytes()
            self.reconcile(success=False)
            self.assertEqual(self.config.read_bytes(), before)

    def test_native_model_wizard_endpoint_and_agreeing_alias_survive(self):
        self.reconcile()
        data = yaml.safe_load(self.config.read_text())
        data["model"]["base_url"] = "https://chatgpt.com/backend-api/codex"
        self.host(data)
        for alias in (False, True):
            if alias:
                data["model"]["model"] = "gpt-6-astra"
                self.host(data)
            before = self.config.read_bytes(), self.config.stat().st_mtime_ns
            self.reconcile("check")
            self.reconcile()
            self.assertEqual((self.config.read_bytes(), self.config.stat().st_mtime_ns), before)
        # Also exercise the YAML write path, not only the no-op early return.
        del data["plugins"]
        data["model"]["default"] = "host-drift"
        self.host(data)
        self.reconcile("check", success=False)
        self.reconcile()
        written = yaml.safe_load(self.config.read_text())
        self.assertEqual(written["model"]["base_url"], "https://chatgpt.com/backend-api/codex")
        self.assertEqual(written["model"]["model"], "gpt-6-astra")
        self.assertEqual(written["model"]["default"], "gpt-6-astra")
        self.assertEqual(written["plugins"]["enabled"], ["eyragents"])

    def test_refuse_linked_or_exposed_config(self):
        target = self.base / "keep.yaml"
        target.write_text("display: {}\n")
        self.config.symlink_to(target)
        self.reconcile(success=False)
        self.assertTrue(self.config.is_symlink())
        self.config.unlink()
        os.link(target, self.config)
        self.config.chmod(0o600)
        self.reconcile(success=False)
        self.config.unlink()
        self.host({})
        self.config.chmod(0o644)
        self.reconcile(success=False)

    def policy(self):
        policy = module("hermes_policy", ROOT / "hermes/.hermes/plugins/eyragents/__init__.py")
        policy._ready = True
        # The fake Hermes home lives in this OpenCode session's scratch. Model
        # the foreign-session root separately; the production deny stays fixed.
        policy.OTHER_SESSION_ROOT = self.base / "foreign-tool"
        policy.mount_table = lambda: [(Path("/"), "/", "ext4", "8:1", None)]
        policy.context = lambda task: (self.repo if task != "child" else self.repo / "sub", self.home)
        (self.repo / "sub").mkdir(exist_ok=True)
        return policy

    def test_path_inventory_and_actual_alias_targets(self):
        policy = self.policy()
        for name in (".env", ".env.custom", "secrets/a.txt", ".aws/anything", ".ssh/config",
                     "auth.json", "credentials.json", "id_ed25519", "private.pem",
                     ".config/gh/hosts.yml", ".hermes/config.yaml"):
            for tool in ("read_file", "write_file", "patch"):
                with self.subTest(name=name, tool=tool):
                    decision = policy.pre_tool_call(tool_name=tool, args={"path": name})
                    self.assertEqual(decision["action"], "block")
        for name in ("README.md", "example.env", "credentials-policy.md"):
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": name}))
        (self.repo / "alias").symlink_to(self.repo / ".env.custom")
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "alias"})["action"], "block")
        (self.repo / "dir-alias").symlink_to(self.home / ".ssh", target_is_directory=True)
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "dir-alias/config"})["action"], "block")
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": str(policy.OTHER_SESSION_ROOT / "note")})["action"], "block")

    def test_normalization_task_cwd_and_external_asks(self):
        policy = self.policy()
        output = policy.request(tool_name="read_file", args={"path": "file.txt"}, task_id="child")
        self.assertEqual(output["args"]["path"], str(self.repo / "sub/file.txt"))
        self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(self.home / "Projects/other/a") }))
        for tool in ("read_file", "write_file"):
            target = str(self.home / "Documents/a")
            decision = policy.pre_tool_call(tool_name=tool, args={"path": target})
            self.assertEqual(decision["action"], "approve")
            self.assertTrue(decision["rule_key"].startswith("eyragents:"))
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": ".git/config"})["action"], "block")

    def test_gate_and_fail_closed_dependencies(self):
        policy = self.policy()
        gate = self.home / ".agents/hooks/commit-gate"
        gate.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "templates/hooks/commit-gate", gate)
        with patch.dict(os.environ, self.env):
            self.assertIsNone(policy.pre_tool_call(tool_name="terminal", args={"command": "git status"}))
            self.assertIsNone(policy.pre_tool_call(tool_name="terminal", args={
                "command": "~/.agents/skills/publish/scripts/publish-apply " + "a" * 64}))
            for command in ("git commit -m fixture", "git push", "sudo true", "git stash drop"):
                self.assertEqual(policy.pre_tool_call(tool_name="terminal", args={"command": command})["action"], "block")
            gate.unlink()
            self.assertEqual(policy.pre_tool_call(tool_name="terminal", args={"command": "git status"})["action"], "block")

    def test_symlink_parent_traversal_keeps_native_target(self):
        policy = self.policy()
        nested = self.repo / "actual/nested"
        nested.mkdir(parents=True)
        (self.repo / "link").symlink_to(nested, target_is_directory=True)
        output = policy.request(tool_name="write_file", args={"path": "link/../target.txt", "content": "new"})
        self.assertEqual(Path(output["args"]["path"]).resolve(), self.repo / "actual/target.txt")
        self.assertNotEqual(Path(output["args"]["path"]).resolve(), self.repo / "target.txt")

    def test_shared_system_and_raw_corpus_copies_aliases_and_boundaries(self):
        policy = self.policy()
        corpus = json.loads((ROOT / "tests/safety-paths.json").read_text())
        for kind, constants in (("system_files", policy.SYSTEM_FILES), ("system_trees", policy.SYSTEM_TREES),
                                ("raw_files", policy.RAW_FILES), ("raw_trees", policy.RAW_TREES)):
            self.assertEqual(set(corpus[kind]), set(constants), kind)
            for index, name in enumerate(corpus[kind]):
                leaf = name + ("/fixture.txt" if kind.endswith("trees") else "")
                copy = self.repo / "copy" / leaf
                copy.parent.mkdir(parents=True, exist_ok=True)
                copy.write_text("synthetic protected-path fixture")
                alias = self.repo / f"alias-{kind}-{index}"
                alias.symlink_to(copy)
                for target in (Path("/") / leaf, copy, alias):
                    for tool in ("read_file", "search_files", "write_file", "patch"):
                        with self.subTest(kind=kind, target=target, tool=tool):
                            self.assertEqual(policy.pre_tool_call(tool_name=tool, args={"path": str(target)})["action"], "block")
                # Exact filenames and component boundaries, not a prefix ban.
                self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(self.repo / (name + "-policy.md"))}))
        for name in (*corpus["positive_files"], "etc/ssh/ssh_host_ed25519_key.pub", "agent/auth.py"):
            with self.subTest(positive=name):
                self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(self.repo / name)}))
                if name.startswith(("etc/", "usr/", "var/", "sys/")):
                    self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": "/" + name}))
        for name in ("host.keytab", "ssh_host_ed25519_key"):
            self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": name})["action"], "block")

    def test_broad_read_scope_is_not_home_or_runtime_browsing(self):
        policy = self.policy()
        for name in ("/bin/fixture", "/boot/fixture", "/efi/fixture", "/etc/crypttab", "/lib/fixture",
                     "/lib64/fixture", "/sbin/fixture", "/srv/fixture", "/var/log/fixture", "/custom-system/fixture",
                     str(self.home / ".bashrc"), str(self.home / ".tool/deps/auth.py"),
                     str(self.home / "Projects/other/notes.md"), str(self.profile / "memories/MEMORY.md")):
            with self.subTest(positive=name):
                self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": name}))
        for name in ("/", "/home", "/home/someone/.bashrc", "/root", "/proc/cpuinfo", "/dev/null",
                     "/run/fixture", "/mnt/work/notes.md", "/media/drive/notes.md", "/Volumes/drive/a",
                     str(self.home), str(self.home / "Documents/report.md")):
            for tool in ("read_file", "search_files"):
                with self.subTest(external=name, tool=tool):
                    self.assertEqual(policy.pre_tool_call(tool_name=tool, args={"path": name})["action"], "approve")
        # Even starting a task at / or HOME must not auto-approve their searches.
        for cwd in (Path("/"), self.home):
            policy.context = lambda task, cwd=cwd: (cwd, self.home)
            self.assertEqual(policy.pre_tool_call(tool_name="search_files", args={"path": str(cwd)})["action"], "approve")

    def test_home_spellings_and_symlink_before_parent_exclusions(self):
        policy = self.policy()
        alias = self.base / "home-alias"
        alias.symlink_to(self.home, target_is_directory=True)
        policy.context = lambda task: (self.repo, alias)
        with patch.dict(os.environ, {"HOME": str(alias)}):
            for home in (alias, self.home):
                for name in (".bashrc", ".config/tool/settings.json", "Projects/other/file"):
                    self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(home / name)}))
                for name in (".codex/config.toml", ".claude/projects/session.jsonl", ".local/share/opencode/a"):
                    self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": str(home / name)})["action"], "block")
                self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": str(home / "Documents/a")})["action"], "approve")
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": "~/.bashrc"}))
        nested = self.home / ".claude/projects/nested"
        nested.mkdir(parents=True)
        (self.repo / "session-link").symlink_to(nested, target_is_directory=True)
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "session-link/../session.jsonl"})["action"], "block")
        (self.repo / "runtime-link").symlink_to("/run", target_is_directory=True)
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "runtime-link/fixture"})["action"], "approve")

    def test_relocated_xdg_stores_resolved_store_aliases_and_foreign_histories(self):
        policy = self.policy()
        config, data, state, cache = [self.base / p for p in ("config", "data", "state", "cache")]
        for root in (config, data, state, cache):
            root.mkdir()
        config_alias = self.base / "config-alias"
        config_alias.symlink_to(config, target_is_directory=True)
        relocated = self.base / "opaque-store"
        relocated.mkdir()
        (data / "opencode").symlink_to(relocated, target_is_directory=True)
        env = {"XDG_CONFIG_HOME": str(config_alias), "XDG_DATA_HOME": str(data),
               "XDG_STATE_HOME": str(state), "XDG_CACHE_HOME": str(cache),
               "CODEX_HOME": str(self.base / "codex-profile"), "CLAUDE_CONFIG_DIR": str(self.base / "claude-profile")}
        with patch.dict(os.environ, env):
            denied = [r / p for r in (config_alias, config) for p in
                      ("gh/hosts.yml", "google-chrome/Default/Cookies", "Bitwarden/data.json", "1Password/store")]
            denied += [data / "keyrings/login", data / "opencode/db", relocated / "db", state / "opencode/history",
                       cache / "opencode/session", state / "fish/fish_history",
                       self.base / "codex-profile/sessions/log", self.base / "claude-profile/history.jsonl"]
            for target in denied:
                with self.subTest(target=target):
                    self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": str(target)})["action"], "block")
            for target in (config / "ordinary/settings.json", data / "tool/lib/auth.py", state / "ordinary/status",
                           self.profile / "memories/MEMORY.md", self.profile / "skills/learned/SKILL.md"):
                self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(target)}))
        for name in (".claude.json", ".claude/debug/log", ".codex/archived_sessions/a", ".codex/history.jsonl",
                     ".local/share/opencode/db", ".cache/opencode/db", ".local/state/opencode/db"):
            self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": str(self.repo / "copy" / name)})["action"], "block")
        # Environment metadata identifies protected stores; it does not grant
        # arbitrary containing home directories or runtime/mounted storage.
        for root in ("/home", "/home/eyragents-foreign-fixture", "/mnt/fixture", "/run/fixture"):
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": root}):
                self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": root + "/ordinary"})["action"], "approve")

    def test_mount_metadata_unknown_nested_bind_and_recursive_scopes(self):
        policy = self.policy()
        root = (Path("/"), "/@", "btrfs", "8:1", "/@")
        for extra in ((Path("/srv/user-data"), "/", "nfs4", "0:90", None),
                      (Path("/srv/user-data"), "/private", "ext4", "8:1", None),
                      (Path("/srv/user-data"), "/", "ext4", "8:2", None)):
            policy.mount_table = lambda extra=extra: [root, extra]
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": "/srv/ordinary"}))
            for tool, target in (("read_file", "/srv/user-data/a"), ("search_files", "/srv")):
                self.assertEqual(policy.pre_tool_call(tool_name=tool, args={"path": target})["action"], "approve")
        for metadata in (None, []):
            policy.mount_table = lambda metadata=metadata: metadata
            self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "/srv/ordinary"})["action"], "approve")
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": "README.md"}))
        policy.mount_table = lambda: [root, (Path("/sys"), "/", "sysfs", "0:1", None),
                                     (Path("/boot"), "/", "vfat", "8:2", None)]
        for target in ("/boot/fixture", "/sys/class/power_supply/BAT0/status"):
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": target}))
        for source_root, subvolume, expected in (("/@home", "/@home", True), ("/@home/private", "/@home", False),
                                                ("/@home", None, False)):
            policy.mount_table = lambda: [root, (self.home, source_root, "btrfs", "8:1", subvolume)]
            decision = policy.pre_tool_call(tool_name="read_file", args={"path": str(self.home / ".bashrc")})
            self.assertEqual(decision is None, expected)

    def test_mount_parser_fail_closed_without_payload_reads(self):
        policy = module("hermes_mount_policy", ROOT / "hermes/.hermes/plugins/eyragents/__init__.py")
        valid = "1 0 8:1 / / rw,relatime - ext4 /dev/fixture rw\n"
        for text in ("", "bad", valid.replace(" / / ", " / /../ "), valid + valid,
                     valid.replace(" - ", " opaque:1 - "), valid.replace("8:1", "x"),
                     valid.replace("rw,relatime", "unknown"), valid.replace("rw,relatime", "rw\\bad"),
                     "x" * (1024 * 1024 + 1)):
            with patch("builtins.open", return_value=io.StringIO(text)) as metadata:
                self.assertIsNone(policy.mount_table())
                metadata.assert_called_once_with("/proc/self/mountinfo", encoding="utf-8")
        with patch("builtins.open", return_value=io.StringIO(valid)):
            self.assertEqual(policy.mount_table(), [(Path("/"), "/", "ext4", "8:1", None)])
        with patch("builtins.open", return_value=io.StringIO(valid + "2 1 8:1 /@home /home rw - btrfs /dev/fixture rw,subvolid=257,subvol=/@home\n")):
            self.assertEqual(policy.mount_table()[-1], (Path("/home"), "/@home", "btrfs", "8:1", "/@home"))

    def test_whole_root_aliases_precede_supported_mount_fast_paths(self):
        policy = self.policy()
        root = (Path("/"), "/@", "btrfs", "8:1", "/@")
        # Identical device/root at a non-ancestor user-storage point must be
        # seen even by the Btrfs-home and kernel-filesystem positive fast paths.
        cases = ((self.home, "/@home", "btrfs", "8:1", "/@home"),
                 (Path("/home"), "/@home", "btrfs", "8:1", "/@home"),
                 (Path("/usr"), "/", "ext4", "8:2", None),
                 (Path("/boot"), "/", "vfat", "8:2", None),
                 (Path("/tmp"), "/", "tmpfs", "0:2", None),
                 (Path("/sys"), "/", "sysfs", "0:3", None),
                 (Path("/sys/fs/cgroup"), "/", "cgroup2", "0:4", None))
        for supported in cases:
            target = supported[0] / "ordinary"
            with self.subTest(supported=supported[0]):
                self.assertTrue(policy.mounted_readable(target, self.home, [root, supported]))
                for alias_point in (Path("/media/disk"), Path("/srv/user-volume")):
                    alias = (alias_point, *supported[1:])
                    for mounts in ([root, supported, alias], [root, alias, supported]):
                        self.assertFalse(policy.mounted_readable(target, self.home, mounts))
                        self.assertFalse(policy.mounted_readable(supported[0], self.home, mounts, recursive=True))
                        self.assertFalse(policy.mounted_readable(alias_point / "ordinary", self.home, mounts))
                        self.assertTrue(policy.standing_read(Path("/etc/passwd"), self.home, mounts))
        # Ordinary Arch root/home subvolumes share a device, not a source root.
        home_mount = cases[0]
        mounts = [root, home_mount]
        self.assertTrue(policy.standing_read(self.home / ".bashrc", self.home, mounts))
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        policy.mount_table = lambda: mounts
        self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "new.txt")}))
        mounts.append((Path("/media/disk"), *home_mount[1:]))
        for tool, target in (("read_file", self.home / ".bashrc"),
                             ("read_file", self.home / "Projects/other/ordinary"),
                             ("search_files", self.home / "Projects"), ("write_file", scratch / "new.txt")):
            decision = policy.pre_tool_call(tool_name=tool, args={"path": str(target)})
            self.assertIsNotNone(decision)
            self.assertEqual(decision["action"], "approve")
        self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": "/usr/lib/os-release"}))
        self.assertFalse((scratch / "new.txt").exists())

    def test_unique_actual_root_survives_whole_root_mirrors(self):
        policy = self.policy()
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        prospective = scratch / "prospective.txt"
        for filesystem, source_root, subvolume in (("ext4", "/", None), ("btrfs", "/@", "/@")):
            root = (Path("/"), source_root, filesystem, "8:1", subvolume)
            for point in (Path("/media/root-copy"), Path("/srv/root-copy"), Path("/usr")):
                mirror = (point, *root[1:])
                for mounts in ([root, mirror], [mirror, root]):
                    with self.subTest(filesystem=filesystem, mirror=point, root_first=mounts[0] == root):
                        policy.mount_table = lambda: mounts
                        for target in (Path("/etc/passwd"), Path("/srv/ordinary"), self.home / ".bashrc"):
                            self.assertTrue(policy.standing_read(target, self.home, mounts))
                            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(target)}))
                        self.assertTrue(policy.mounted_readable(Path("/etc"), self.home, mounts, recursive=True))
                        self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(prospective)}))
                        for target in (point, point / "etc/passwd"):
                            self.assertFalse(policy.mounted_readable(target, self.home, mounts))
                            self.assertFalse(policy.standing_read(target, self.home, mounts))
                            decision = policy.pre_tool_call(tool_name="read_file", args={"path": str(target)})
                            self.assertIsNotNone(decision)
                            self.assertEqual(decision["action"], "approve")
                        self.assertFalse(policy.mounted_readable(point.parent, self.home, mounts, recursive=True))
                for ambiguous in ([root, mirror, root], [mirror],
                                  [(Path("/"), "/", "nfs4", "0:8", None), mirror]):
                    self.assertFalse(policy.standing_read(Path("/etc/passwd"), self.home, ambiguous))
                    self.assertFalse(policy.persistent_write(prospective, self.home, ambiguous))
        self.assertFalse(prospective.exists())

    def test_stacked_mount_ambiguity_is_local_to_its_subtree(self):
        policy = self.policy()
        parser = module("hermes_mount_policy", ROOT / "hermes/.hermes/plugins/eyragents/__init__.py").mount_table
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        # gu605c's observed failure shape: one stacked point with a unique,
        # supported root. Use synthetic locations/options, not a host snapshot.
        base = "1 0 8:1 /@ / rw - btrfs /dev/fixture rw,subvol=/@\n"
        base += f"2 1 8:1 /@home {self.home} rw - btrfs /dev/fixture rw,subvol=/@home\n"
        base += "3 1 0:4 / /sys rw - sysfs sysfs rw\n"
        stacked = ("4 3 0:5 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n"
                   "5 4 0:6 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n")
        with patch("builtins.open", return_value=io.StringIO(base + stacked)):
            mounts = parser()
        self.assertIsNotNone(mounts)
        self.assertEqual(sum(n > 1 for n in policy.Counter(m[0] for m in mounts).values()), 1)
        policy.mount_table = lambda: mounts
        for target in ("/usr/lib/os-release", "/sys/class/power_supply/BAT0/status", str(self.home / ".bashrc")):
            self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": target}))
        self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "prospective.txt")}))
        for tool, target in (("read_file", "/sys/fs/cgroup"), ("read_file", "/sys/fs/cgroup/nested/status"),
                             ("search_files", "/sys")):
            self.assertEqual(policy.pre_tool_call(tool_name=tool, args={"path": target})["action"], "approve")
        # Stacks under scratch cannot authorize mutation, even if each record
        # alone looks like a supported mount. Sibling targets remain eligible.
        mounts.extend([(scratch / "stacked", "/", "ext4", "8:2", None),
                       (scratch / "stacked", "/", "ext4", "8:3", None)])
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "stacked/new.txt")})["action"], "approve")
        self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "ordinary.txt")}))
        for text in (base + "6 1 8:2 / / rw - ext4 /dev/second rw\n", stacked,
                     base + stacked + "7 3 0:7 / relative rw - ext4 /dev/fixture rw\n"):
            with patch("builtins.open", return_value=io.StringIO(text)):
                self.assertIsNone(parser(), "ambiguous root or unlocatable metadata must not be accepted")

    def test_inaccessible_inventory_parent_preserves_literals_and_unrelated_work(self):
        policy = self.policy()
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        private_parent = Path("/etc/ipsec.d")
        alias = self.repo / "outward-target"
        alias.symlink_to(private_parent / "ordinary-name")
        original = os.lstat

        def inaccessible(path, *args, **kwargs):
            if Path(path) == private_parent:
                raise PermissionError(errno.EACCES, "synthetic inaccessible parent")
            return original(path, *args, **kwargs)

        with patch("os.lstat", inaccessible):
            _, trees = policy.protected_paths(self.home)
            self.assertIn(private_parent / "private", trees)
            for target in (self.repo / "ordinary.txt", Path("/usr/lib/os-release"), self.home / ".bashrc"):
                self.assertIsNone(policy.pre_tool_call(tool_name="read_file", args={"path": str(target)}))
            self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "new.txt")}))
            for target in (private_parent / "ordinary-name", private_parent / "private/key", alias,
                           self.repo / "copied/etc/ipsec.d/private/key"):
                for tool in ("read_file", "write_file"):
                    self.assertEqual(policy.pre_tool_call(tool_name=tool, args={"path": str(target)})["action"], "block")
            with self.assertRaises(PermissionError):
                policy.resolve_target(alias)
            # No claim that outward aliases hidden behind this parent were
            # discovered: the inventory retains its literal spelling only.
            self.assertEqual(policy.inventory_target(private_parent / "private"), private_parent / "private")
        for category in (errno.EIO, errno.ELOOP):
            def invalid(path, *args, **kwargs):
                if Path(path) == private_parent:
                    raise OSError(category, "synthetic metadata failure")
                return original(path, *args, **kwargs)
            with patch("os.lstat", invalid):
                self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "ordinary.txt"})["action"], "block")

    def test_strict_resolution_on_older_python_without_allow_missing(self):
        policy = self.policy()
        nested = self.repo / "actual/nested"
        nested.mkdir(parents=True)
        link = self.repo / "link"
        link.symlink_to(nested, target_is_directory=True)
        inaccessible = self.repo / "inaccessible"
        inaccessible.mkdir()
        outward = self.repo / "outward"
        outward.symlink_to(inaccessible / "ordinary")
        original = Path.stat

        def denied(path, *args, **kwargs):
            if policy.below(path, inaccessible) or path == outward:
                raise PermissionError(errno.EACCES, "synthetic target refusal")
            return original(path, *args, **kwargs)

        with patch.object(policy, "_ALLOW_MISSING", None), patch.object(Path, "stat", denied):
            self.assertEqual(policy.resolve_target(link / "../prospective.txt"), self.repo / "actual/prospective.txt")
            for target in (inaccessible / "missing", outward):
                with self.assertRaises(PermissionError):
                    policy.resolve_target(target)
            self.assertEqual(policy.inventory_target(inaccessible / "missing"), inaccessible / "missing")

    def test_persistent_scratch_union_and_preservation(self):
        policy = self.policy()
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        keep = scratch / "user-work.txt"
        keep.write_text("preserve this unrelated work")
        before = keep.read_bytes(), keep.stat().st_mtime_ns
        with patch.dict(os.environ, {"TMPDIR": str(self.base / "unrelated-temp")}):
            for path in (scratch / "new/note.txt", scratch / "new/../note.txt", self.repo / "new.txt"):
                self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(path)}))
            # Nested workspace and persistent roots form a union.
            nested = scratch / "work"
            nested.mkdir()
            (nested / ".git").mkdir()
            policy.context = lambda task: (nested, self.home)
            self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "sibling/note.txt")}))
            self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(self.home / "Projects/other/note.txt")})["action"], "approve")
        self.assertEqual((keep.read_bytes(), keep.stat().st_mtime_ns), before)
        self.assertFalse((scratch / "new").exists(), "eligibility must not create or clean persistent work")
        for directory in (scratch, nested):
            self.assertEqual(policy.pre_tool_call(tool_name="patch", args={"path": str(directory)})["action"], "approve")
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / ".env")})["action"], "block")

    def test_persistent_scratch_links_unsafe_ancestry_and_mounts(self):
        policy = self.policy()
        scratch = self.home / "Projects/scratch"
        # Missing persistent root receives no automatic creation permission.
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "a")})["action"], "approve")
        scratch.mkdir()
        ordinary = scratch / "ordinary"
        ordinary.write_text("keep")
        (scratch / "link").symlink_to(ordinary)
        (scratch / "dir-link").symlink_to(self.repo, target_is_directory=True)
        os.link(ordinary, scratch / "hardlink")
        for name in ("link", "hardlink", "dir-link/../a"):
            self.assertIsNotNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / name)}))
        directory = scratch / "unsafe"
        directory.mkdir(mode=0o777)
        directory.chmod(0o777)
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(directory / "a")})["action"], "approve")
        scratch.chmod(0o777)
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "a")})["action"], "approve")
        scratch.chmod(0o755)
        original = Path.lstat
        def foreign_owner(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            if path == scratch:
                return types.SimpleNamespace(st_mode=info.st_mode, st_uid=os.getuid() + 1, st_nlink=info.st_nlink)
            return info
        with patch.object(Path, "lstat", foreign_owner):
            self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "a")})["action"], "approve")
        policy.mount_table = lambda: [(Path("/"), "/", "ext4", "8:1", None), (scratch / "mounted", "/", "nfs", "0:2", None)]
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "mounted/a")})["action"], "approve")
        policy.mount_table = lambda: None
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "a")})["action"], "approve")
        self.assertEqual(ordinary.read_text(), "keep")

    def test_scratch_home_alias_and_root_redirect(self):
        policy = self.policy()
        scratch = self.home / "Projects/scratch"
        scratch.mkdir()
        alias = self.base / "home-alias"
        alias.symlink_to(self.home, target_is_directory=True)
        policy.context = lambda task: (self.repo, alias)
        for home in (alias, self.home):
            self.assertIsNone(policy.pre_tool_call(tool_name="write_file", args={"path": str(home / "Projects/scratch/a")}))
        scratch.rmdir()
        scratch.symlink_to(self.repo, target_is_directory=True)
        self.assertEqual(policy.pre_tool_call(tool_name="write_file", args={"path": str(scratch / "a")})["action"], "approve")

    def test_capability_preservation_and_execution_backstop(self):
        policy = self.policy()
        for name in ("execute_code", "delegate_task", "memory", "session_search", "web_search", "cronjob", "browser_navigate"):
            self.assertIsNone(policy.pre_tool_call(tool_name=name, args={}))
        called = []
        result = policy.execute(tool_name="write_file", args={"path": ".git/config"}, next_call=called.append)
        self.assertFalse(called)
        self.assertIn("error", json.loads(result))
        policy._ready = False
        self.assertEqual(policy.pre_tool_call(tool_name="read_file", args={"path": "README.md"})["action"], "block")

    def test_local_learning_and_shared_skill_ownership(self):
        policy = self.policy()
        local = self.profile / "skills"
        helpers = types.ModuleType("tools.skill_manager_tool")
        helpers._resolve_skill_dir = lambda name, category=None: local / name
        helpers._find_skill = lambda name: {"path": local / name if name == "learned" else self.home / ".agents/skills" / name}
        constants = types.ModuleType("hermes_constants")
        constants.get_hermes_home = lambda: self.profile
        with patch.dict(sys.modules, {"tools": types.ModuleType("tools"), "tools.skill_manager_tool": helpers, "hermes_constants": constants}):
            self.assertIsNone(policy.pre_tool_call(tool_name="skill_manage", args={"action": "create", "name": "learned"}))
            self.assertIsNone(policy.pre_tool_call(tool_name="skill_manage", args={"action": "edit", "name": "learned"}))
            self.assertEqual(policy.pre_tool_call(tool_name="skill_manage", args={"action": "edit", "name": "commit"})["action"], "block")
            (self.home / ".agents/skills/commit").mkdir(parents=True)
            self.assertEqual(policy.pre_tool_call(tool_name="skill_manage", args={"action": "create", "name": "commit"})["action"], "block")
            self.assertEqual(policy.pre_tool_call(tool_name="skill_manage", args={"action": "write_file", "name": "learned", "file_path": "../../plugins/a.py"})["action"], "block")
            (local / "learned").mkdir(parents=True)
            shared = self.repo / "shared-skill.md"
            shared.write_text("keep this shared skill")
            (local / "learned/SKILL.md").symlink_to(shared)
            for action in ("create", "edit", "patch"):
                self.assertEqual(policy.pre_tool_call(tool_name="skill_manage", args={"action": action, "name": "learned"})["action"], "block")
            for action in ("create", "edit"):
                self.assertEqual(policy.pre_tool_call(tool_name="skill_manage", args={"action": action, "name": "learned", "file_path": "references/ordinary.md"})["action"], "block")
            self.assertEqual(shared.read_text(), "keep this shared skill")


def metadata_preflight():
    """Explicit opt-in host check: no client imports, registration or mutation.

    Read only this repository's plugin source and /proc/self/mountinfo. Other
    operations resolve/stat declared paths. Emit booleans/counts/error categories
    only; neither protected contents nor mount/options/environment values leave
    this helper. Prospective scratch eligibility never creates its target.
    """
    policy = module("hermes_metadata_policy", ROOT / "hermes/.hermes/plugins/eyragents/__init__.py")
    report = {"host_matches_gu605c": os.uname().nodename == "gu605c", "preflight_complete": False}
    inaccessible, errors = set(), set()
    original = policy.resolve_target

    def checked(path):
        try:
            return original(path)
        except PermissionError as error:
            inaccessible.add(path)
            errors.add(errno.errorcode.get(error.errno, "PERMISSION_ERROR"))
            raise

    policy.resolve_target = checked
    try:
        home = Path.home()
        mounts = policy.mount_table()
        counts = policy.Counter(m[0] for m in mounts or [])
        report.update(mount_table_valid=mounts is not None, mount_count=len(mounts or []),
                      stacked_subtree_count=sum(n > 1 for n in counts.values()), root_unique=counts[Path("/")] == 1)
        policy.protected_paths(home)
        report["inaccessible_inventory_path_count"] = len(inaccessible)
        for label, target in (("ordinary_system_read", Path("/usr/lib/os-release")),
                              ("own_dotfile_read", home / ".bashrc"),
                              ("projects_read", ROOT / "README.md")):
            report[label + "_eligible"] = (policy.path_denial(target, False, home) is None and
                                            policy.standing_read(target, home, mounts))
        prospective = home / "Projects/scratch/.eyragents-hermes-metadata-probe"
        try:
            prospective.lstat()
            absent = False
        except FileNotFoundError:
            absent = True
        report["prospective_scratch_target_absent"] = absent
        report["prospective_scratch_write_eligible"] = (absent and policy.path_denial(prospective, True, home) is None and
                                                       policy.persistent_write(prospective, home, mounts))
        report["preflight_complete"] = True
    except OSError as error:
        errors.add(errno.errorcode.get(error.errno, "OS_ERROR"))
    except (ValueError, RuntimeError, AttributeError):
        errors.add("UNSUPPORTED_METADATA")
    report["error_categories"] = sorted(errors)
    print(json.dumps(report, sort_keys=True))
    return 0 if report["preflight_complete"] else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--metadata-preflight"]:
        sys.exit(metadata_preflight())
    unittest.main()
