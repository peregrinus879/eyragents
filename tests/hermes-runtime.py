#!/usr/bin/env python3
"""Offline installed-Hermes dispatch check, run with its venv Python -I -B.

Fake HOME/profile, no model client, account, network, server or live session.
Confirms real plugin loading, middleware and native patch parsing.
"""
import errno
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import types
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="hermes-runtime-") as temporary:
    home = Path(temporary)
    repo = home / "Projects/work"
    repo.mkdir(parents=True)
    (repo / ".git").mkdir()
    persistent = home / "Projects/scratch"
    persistent.mkdir()
    keep = persistent / "user-work.txt"
    keep.write_text("preserve unrelated persistent work")
    keep_before = keep.read_bytes(), keep.stat().st_mtime_ns
    ordinary = repo / "ordinary.txt"
    ordinary.write_text("ordinary-fixture-content\n")
    profile = home / ".hermes"
    plugin = profile / "plugins/eyragents"
    plugin.mkdir(parents=True)
    for name in ("plugin.yaml", "__init__.py"):
        shutil.copyfile(ROOT / "hermes/.hermes/plugins/eyragents" / name, plugin / name)
    gate = home / ".agents/hooks/commit-gate"
    gate.parent.mkdir(parents=True)
    shutil.copy2(ROOT / "templates/hooks/commit-gate", gate)
    (profile / "config.yaml").write_text("plugins:\n  enabled: [eyragents]\nterminal:\n  backend: local\n")
    path = os.environ.get("PATH", "/usr/bin:/bin")
    scratch = os.environ.get("TMPDIR", temporary)
    os.environ.clear()
    os.environ.update(HOME=str(home), HERMES_HOME=str(profile), PATH=path,
                      TMPDIR=scratch, HISTFILE="/dev/null", PYTHONDONTWRITEBYTECODE="1",
                      XDG_CONFIG_HOME=str(home / ".config"), XDG_DATA_HOME=str(home / ".local/share"),
                      XDG_CACHE_HOME=str(home / ".cache"), HERMES_MANAGED_DIR=str(home / "managed"),
                      XDG_STATE_HOME=str(home / ".local/state"), TERMINAL_CWD=str(repo),
                      GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
    os.chdir(repo)
    from tools import file_tools
    from hermes_cli import plugins
    from hermes_cli.middleware import apply_tool_request_middleware, run_tool_execution_middleware
    plugins.discover_plugins()
    policy = next(module for module in tuple(sys.modules.values())
                  if getattr(module, "__file__", None) == str(plugin / "__init__.py"))
    # The complete fake HOME is inside OpenCode-owned execution scratch. Model
    # foreign sessions separately so fixture operations do not waive the real
    # production exclusion. Mount metadata is likewise a synthetic local layout.
    policy.OTHER_SESSION_ROOT = home / "foreign-session"
    metadata = ("1 0 8:1 / / rw - ext4 /dev/fixture rw\n"
                "2 1 0:4 / /sys rw - sysfs sysfs rw\n"
                "3 2 0:5 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n"
                "4 3 0:6 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n"
                "5 1 8:1 / /media/root-copy rw - ext4 /dev/fixture rw\n")
    with patch("builtins.open", return_value=io.StringIO(metadata)):
        mounts = policy.mount_table()
    assert mounts, "one stacked subtree disabled the complete mount table"
    policy.mount_table = lambda: mounts
    for target in ("/sys/fs/cgroup", "/sys/fs/cgroup/nested/status"):
        assert policy.pre_tool_call(tool_name="read_file", args={"path": target})["action"] == "approve"
    for ordered in (mounts, list(reversed(mounts))):
        with patch.object(policy, "mount_table", return_value=ordered):
            assert policy.pre_tool_call(tool_name="read_file", args={"path": "/etc/passwd"}) is None
            assert policy.pre_tool_call(tool_name="write_file", args={"path": str(persistent / "root-mirror-control.txt")}) is None
            decision = policy.pre_tool_call(tool_name="read_file", args={"path": "/media/root-copy/etc/passwd"})
            assert decision and decision["action"] == "approve", "root mirror inherited the actual root's eligibility"
            assert not policy.mounted_readable(Path("/media/root-copy/etc/passwd"), home, ordered)
    assert not (persistent / "root-mirror-control.txt").exists()
    aliased_home = [(Path("/"), "/@", "btrfs", "8:1", "/@"),
                    (home, "/@home", "btrfs", "8:1", "/@home"),
                    (Path("/media/disk"), "/@home", "btrfs", "8:1", "/@home")]
    with patch.object(policy, "mount_table", return_value=aliased_home):
        for tool, target in (("read_file", home / ".bashrc"), ("search_files", home / "Projects"),
                             ("write_file", persistent / "aliased-home.txt")):
            decision = policy.pre_tool_call(tool_name=tool, args={"path": str(target)})
            assert decision and decision["action"] == "approve", "whole-subvolume alias received an automatic grant"
        assert policy.pre_tool_call(tool_name="read_file", args={"path": "/usr/lib/os-release"}) is None
        assert not (persistent / "aliased-home.txt").exists()
    decision = plugins.resolve_pre_tool_block("read_file", {"path": str(home / ".ssh/config")})
    assert decision, "real plugin failed to deny a protected read"
    decision = plugins.resolve_pre_tool_block("terminal", {"command": "git commit -m fixture", "workdir": str(home)})
    assert decision, "real plugin failed to dispatch the commit gate"
    assert not plugins.resolve_pre_tool_block("read_file", {"path": "/usr/lib/os-release"})
    assert file_tools.get_read_block_error(Path("/nonexistent/fixture/.env.unusual"))
    request = apply_tool_request_middleware("read_file", {"path": "/usr/lib/os-release"})
    assert request.payload["path"] == "/usr/lib/os-release"
    for patch_text in (
        "*** Begin Patch\n***Add File: /tmp/eyragents-fixture/.git/config\n+bad\n*** End Patch",
        "***Move File: /tmp/eyragents-fixture/ordinary -> /tmp/eyragents-fixture/.env.unusual",
        f"***Move File: {ordinary} -> {persistent / 'copy/etc/shadow'}",
        f"***Move File: {repo / '.claude/projects/session.jsonl'} -> {persistent / 'new.txt'}",
        f"***Move File: {ordinary} -> {home / '.local/share/opencode/session'}",
    ):
        request = apply_tool_request_middleware("patch", {"mode": "patch", "patch": patch_text})
        assert plugins.resolve_pre_tool_block("patch", request.payload), "native parser target escaped guard"
    called = []
    result = run_tool_execution_middleware("write_file", {"path": str(home / ".ssh/config"), "content": "fixture"},
                                           lambda args: called.append(args))
    assert not called and "error" in json.loads(result), "execution backstop failed"
    for name in ("memory", "delegate_task", "execute_code", "session_search", "web_search"):
        assert not plugins.resolve_pre_tool_block(name, {}), f"capability disabled: {name}"
    corpus = json.loads((ROOT / "tests/safety-paths.json").read_text())
    blocked_paths = []
    for kind in ("system_files", "system_trees", "raw_files", "raw_trees"):
        for name in corpus[kind]:
            path = repo / "copy" / name
            if kind.endswith("trees"):
                path /= "payload.txt"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic-protected-fixture")
            blocked_paths.append(path)
    alias = repo / "ordinary-looking-alias"
    alias.symlink_to(blocked_paths[0])
    lexical_copy = repo / "copied-store/.claude/projects/ordinary-alias"
    lexical_copy.parent.mkdir(parents=True)
    lexical_copy.symlink_to(ordinary)
    blocked_paths += [alias, lexical_copy, profile / "skills/.hub/metadata.json"]
    # Native result filtering composes both policies and handles all result
    # modes. No protected fixture content needs to be traversed to prove this.
    search = types.SimpleNamespace(files=[str(p) for p in (*blocked_paths, ordinary)],
                                   matches=[types.SimpleNamespace(path=str(p)) for p in (*blocked_paths, ordinary)],
                                   counts={str(p): 1 for p in (*blocked_paths, ordinary)})
    omitted = file_tools._filter_read_blocked_search_results(search, "dispatch-fixture")
    assert omitted == 3 * len(blocked_paths), omitted
    assert search.files == [str(ordinary)] and list(search.counts) == [str(ordinary)]
    assert [m.path for m in search.matches] == [str(ordinary)]
    relative_search = types.SimpleNamespace(files=["copy/etc/shadow", "copied-store/.claude/projects/ordinary-alias", "ordinary.txt"])
    assert file_tools._filter_read_blocked_search_results(relative_search, "dispatch-fixture") == 2
    assert relative_search.files == ["ordinary.txt"]
    for path in (profile / "memories/MEMORY.md", profile / "skills/learned/SKILL.md",
                 profile / "skills/.curator_state", profile / "skills/.curator_backups/fixture/manifest.json"):
        assert not file_tools.get_read_block_error(str(path)), "own learning store classified as foreign history"
    # Exercise the real public dispatcher, not only individual hook helpers.
    # The witness wraps the actual backend dispatch and never substitutes its
    # result. A denial must happen before that backend is called.
    from model_tools import handle_function_call
    from tools.registry import registry
    from tools.terminal_tool import cleanup_all_environments
    try:
        with patch.object(registry, "dispatch", wraps=registry.dispatch) as dispatch:
            for name, args in (
                ("read_file", {"path": "/nonexistent/eyragents-fixture/.env.unusual"}),
                ("terminal", {"command": "git commit -m fixture", "workdir": str(home)}),
                *(("read_file", {"path": str(path)}) for path in blocked_paths[:-1]),
            ):
                result = json.loads(handle_function_call(name, args, task_id="dispatch-fixture"))
                assert "error" in result and "EyrAgents" in result["error"], result
                dispatch.assert_not_called()
            result = json.loads(handle_function_call("read_file", {"path": str(ordinary), "limit": 1},
                                                     task_id="dispatch-fixture"))
            assert "error" not in result and result.get("content"), result
            dispatch.assert_called_once()
        original_lstat = os.lstat

        def inaccessible_inventory(path, *args, **kwargs):
            if Path(path) == Path("/etc/ipsec.d"):
                raise PermissionError(errno.EACCES, "synthetic inaccessible system parent")
            return original_lstat(path, *args, **kwargs)

        with patch("os.lstat", inaccessible_inventory):
            assert not file_tools.get_read_block_error(str(ordinary)), "inventory EACCES poisoned native reads"
            result = json.loads(handle_function_call("read_file", {"path": str(ordinary)}, task_id="dispatch-fixture"))
            assert "error" not in result and result.get("content"), result
            target = persistent / "metadata-error-control.txt"
            result = json.loads(handle_function_call("write_file", {"path": str(target), "content": "fixture"}, task_id="dispatch-fixture"))
            assert "error" not in result and target.read_text() == "fixture", result
            result = json.loads(handle_function_call("read_file", {"path": "/etc/ipsec.d/ordinary-name"}, task_id="dispatch-fixture"))
            assert "error" in result and "EyrAgents" in result["error"], result
        # Real native mutation accepts the independently checked persistent
        # root. A native write-safe-root restriction still wins afterwards.
        destination = persistent / "generated.txt"
        result = json.loads(handle_function_call("write_file", {"path": str(destination), "content": "generated fixture"},
                                                 task_id="dispatch-fixture"))
        assert "error" not in result and destination.read_text() == "generated fixture", result
        move_source = repo / "move-source.txt"
        move_source.write_text("move fixture")
        move_destination = persistent / "moved.txt"
        move_patch = f"***Move File: {move_source} -> {move_destination}"
        result = json.loads(handle_function_call("patch", {"mode": "patch", "patch": move_patch}, task_id="dispatch-fixture"))
        assert "error" not in result and not move_source.exists() and move_destination.read_text() == "move fixture", result
        with patch.dict(os.environ, {"HERMES_WRITE_SAFE_ROOT": str(repo)}):
            denied = persistent / "native-denied.txt"
            assert policy.pre_tool_call(tool_name="write_file", args={"path": str(denied)}) is None
            result = json.loads(handle_function_call("write_file", {"path": str(denied), "content": "fixture"},
                                                     task_id="dispatch-fixture"))
            assert "error" in result and not denied.exists(), "native write restriction lost"
        # Execute ordinary OS use without adding a blanket /proc or /dev mask.
        result = json.loads(handle_function_call("terminal", {"command": "true </dev/null", "workdir": str(repo)},
                                                 task_id="dispatch-fixture"))
        assert not result.get("error") and result.get("exit_code") == 0, result
        # Native learned skills, memory persistence and curator snapshots use
        # only the fake profile. No curator/model client is started.
        result = json.loads(handle_function_call("skill_manage", {"action": "create", "name": "fixture-learning",
                            "content": "---\nname: fixture-learning\ndescription: Offline fixture\n---\nUse a fixture.\n"},
                                                 task_id="dispatch-fixture"))
        assert "error" not in result and (profile / "skills/fixture-learning/SKILL.md").is_file(), result
        from tools.memory_tool import MemoryStore, memory_tool
        store = MemoryStore()
        result = json.loads(run_tool_execution_middleware("memory", {"action": "add", "target": "memory",
                            "content": "Offline fixture preference."}, lambda args: memory_tool(**args, store=store)))
        assert result.get("success") and (profile / "memories/MEMORY.md").is_file(), result
        from agent.curator_backup import snapshot_skills
        snapshot = snapshot_skills(reason="offline policy fixture")
        assert snapshot and snapshot.is_dir(), "native curator backup unavailable"
        assert (keep.read_bytes(), keep.stat().st_mtime_ns) == keep_before, "unrelated persistent work changed"
    finally:
        cleanup_all_environments()
    print("ok:   installed Hermes discovery, native dispatch, parsed Move endpoints, search filtering, native denials, persistent scratch and memory/learning/curator fixtures")
