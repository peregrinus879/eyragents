#!/usr/bin/env python3
"""Hermetic CLI migration tests; tests/update-references.sh owns basic local refresh.

Only fixture GitHub endpoints reach real Git, mapped to local repositories at
fetch/ls-remote execution time. URL preflight sees the literal configured URLs.
Run: python3 tests/reference-migration.py
"""

from dataclasses import dataclass
import json
import os
from pathlib import Path
import select
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
REAL_GIT = shutil.which("git", path=os.defpath)
BASH = shutil.which("bash", path=os.defpath)

# A shared executable, installed as both git and gh in each private fixture.
# File-only Git transport is a second boundary behind this endpoint allowlist.
SHIM = r'''
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

state = json.loads(Path(os.environ["FIXTURE_STATE"]).read_text())
args = sys.argv[1:]
tool = Path(sys.argv[0]).name

def log(**fields):
    with open(state["log"], "a") as out:
        out.write(json.dumps(dict(tool=tool, argv=args, **fields)) + "\n")

def refuse(reason):
    log(blocked=reason)
    sys.exit(97)

if tool == "gh":
    if (len(args) != 5 or args[:2] != ["repo", "view"]
            or args[3:] != ["--json", "id,nameWithOwner,url"]):
        refuse("unexpected gh command")
    if args[2] not in state["metadata"]:
        refuse("unexpected gh endpoint")
    log(endpoint=args[2])
    reply = state["metadata"][args[2]]
    sys.stdout.write(reply["stdout"])
    sys.exit(reply.get("code", 0))

if len(args) < 3 or args[0] != "-C":
    refuse("Git requires an explicit fixture clone")
clone = Path(args[1]).resolve()
if clone.parent != Path(state["quarry"]):
    refuse("Git escaped fixture quarry")
position = 2
while position < len(args) and args[position] == "-c":
    if position + 1 >= len(args) or args[position + 1] not in (
            "fetch.pruneTags=false", "remote.origin.pruneTags=false"):
        refuse("unexpected Git override")
    position += 2
command = args[position]
operands = args[position + 1:]
allowed = {"rev-parse", "symbolic-ref", "status", "config", "remote",
           "ls-remote", "check-ref-format", "fetch", "show-ref", "merge-base",
           "checkout", "merge"}
if command not in allowed:
    refuse("unexpected Git command")
if command == "remote" and operands[:1] != ["get-url"]:
    refuse("unexpected remote mutation")

network = command in ("fetch", "ls-remote") and "--get-url" not in operands
if network:
    options = {"--symref", "--quiet", "--atomic", "--no-force", "--tags",
               "--prune", "--no-prune-tags", "--refmap="}
    offset = 0
    while offset < len(operands) and operands[offset].startswith("-"):
        if operands[offset] not in options:
            refuse("unexpected network option")
        offset += 1
    if offset == len(operands):
        refuse("missing network endpoint")
    endpoint = operands[offset]
    if endpoint == "origin":
        result = subprocess.run(
            [state["git"], "-C", str(clone), "config", "--local", "--get", "remote.origin.url"],
            check=True, capture_output=True, text=True, timeout=5)
        endpoint = result.stdout.rstrip("\n")
    if endpoint not in state["endpoints"]:
        refuse("unexpected network endpoint: " + endpoint)
    expected_tail = ["HEAD"] if command == "ls-remote" else ["refs/heads/*:refs/remotes/origin/*"]
    if operands[offset + 1:] != expected_tail:
        refuse("unexpected network refspec")
    log(network=command, endpoint=endpoint)
    event = state.get("event", {})
    marker = Path(state["marker"])
    if event.get("when") == command and not marker.exists():
        if event["action"] == "hang":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            marker.write_text(json.dumps({"pid": os.getpid(), "pgid": os.getpgrp()}))
            # A broken updater cannot leave this synthetic worker alive indefinitely.
            time.sleep(15)
            sys.exit(98)
        marker.write_text("injected")
        if event["action"] == "manifest-drift":
            with open(state["manifest"], "ab") as out:
                out.write(b"# concurrent fixture edit\r\n")
        elif event["action"] == "origin-drift":
            subprocess.run([state["git"], "-C", str(clone), "config", "--local",
                            "remote.origin.url", event["url"]], check=True, timeout=5)
        else:
            refuse("unknown fixture event")
    args[position + 1 + offset] = state["endpoints"][endpoint]
else:
    log(preflight=command == "ls-remote" and "--get-url" in operands)

event = state.get("event", {})
if (command == "config" and "--replace-all" in operands
        and event.get("action") == "drift-after-origin" and not Path(state["marker"]).exists()):
    subprocess.run([state["git"], *args], check=True, timeout=5)
    Path(state["marker"]).write_text("injected")
    with open(state["manifest"], "ab") as out:
        out.write(b"# concurrent edit after origin migration\n")
    sys.exit(0)

os.execve(state["git"], [state["git"], *args], os.environ)
'''


@dataclass
class Reference:
    name: str
    declared: str
    canonical: str
    pin: str
    upstream: Path
    clone: Path


def snapshot(path):
    """Bytes and non-access metadata, including the index and loose Git objects."""
    paths = [path, *sorted(path.rglob("*"))] if path.is_dir() else [path]
    result = {}
    for entry in paths:
        info = entry.lstat()
        content = (os.readlink(entry) if entry.is_symlink() else
                   entry.read_bytes() if stat.S_ISREG(info.st_mode) else None)
        result[str(entry.relative_to(path))] = (
            info.st_mode, info.st_ino, info.st_nlink, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns, content)
    return result


class Fixture:
    def __init__(self, scratch):
        self.temporary = tempfile.TemporaryDirectory(prefix="case-", dir=scratch)
        self.root = Path(self.temporary.name)
        self.harness = self.root / "harness"
        self.quarry = self.root / "quarry"
        home = self.root / "home"
        bin_dir = self.root / "bin"
        for path in (self.harness / "scripts", self.quarry, home, bin_dir,
                     self.root / "tmp", self.root / "upstreams", home / "empty-hooks"):
            path.mkdir(parents=True, mode=0o700)
        for name in ("update-references.sh", "update-references.py"):
            shutil.copyfile(ROOT / "scripts" / name, self.harness / "scripts" / name)
        for name in ("git", "gh"):
            shim = bin_dir / name
            shim.write_text(f"#!{sys.executable}\n" + SHIM)
            shim.chmod(0o700)
        config = home / ".gitconfig"
        config.write_text(
            "[user]\n\tname = fixture\n\temail = fixture@example.invalid\n"
            "[commit]\n\tgpgSign = false\n[tag]\n\tgpgSign = false\n"
            f"[core]\n\thooksPath = {home / 'empty-hooks'}\n")
        self.manifest = self.harness / "references.txt"
        self.manifest.write_bytes(b"")
        self.state_path = self.root / "shim-state.json"
        self.log_path = self.root / "calls.jsonl"
        self.marker = self.root / "event-marker"
        self.state = dict(git=REAL_GIT, quarry=str(self.quarry),
                          manifest=str(self.manifest), log=str(self.log_path),
                          marker=str(self.marker), metadata={}, endpoints={})
        # No inherited Git, auth, proxy, shell-startup, XDG or client environment.
        self.env = dict(
            PATH=str(bin_dir) + os.pathsep + os.defpath, HOME=str(home),
            TMPDIR=str(self.root / "tmp"), HISTFILE="/dev/null",
            XDG_CONFIG_HOME=str(home / "config"), XDG_DATA_HOME=str(home / "data"),
            XDG_CACHE_HOME=str(home / "cache"), XDG_STATE_HOME=str(home / "state"),
            XDG_RUNTIME_DIR=str(self.root / "tmp"), GH_CONFIG_DIR=str(home / "gh"),
            GIT_CONFIG_GLOBAL=str(config), GIT_CONFIG_SYSTEM="/dev/null",
            GIT_CONFIG_NOSYSTEM="1", GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0",
            GIT_OPTIONAL_LOCKS="0", GIT_ATTR_NOSYSTEM="1", LC_ALL="C", TZ="UTC",
            QUARRY=str(self.quarry), FIXTURE_STATE=str(self.state_path))

    def close(self):
        self.harness.chmod(0o700)
        self.temporary.cleanup()

    def git(self, directory, *args):
        return subprocess.run([REAL_GIT, "-C", str(directory), *args], env=self.env,
                              cwd=self.root, check=True, capture_output=True,
                              text=True, timeout=10).stdout.rstrip("\n")

    def add_reference(self, name="reference", declared="https://github.com/old/project.git",
                      canonical="https://github.com/old/renamed", pin="R_fixture_1"):
        upstream = self.root / "upstreams" / name
        upstream.mkdir()
        self.git(upstream, "init", "--quiet", "-b", "main")
        (upstream / "README.md").write_text("initial\n")
        self.git(upstream, "add", "README.md")
        self.git(upstream, "commit", "--quiet", "-m", "initial")
        self.git(upstream, "tag", "stable")
        clone = self.quarry / name
        self.git(self.root, "clone", "--quiet", upstream.as_uri(), str(clone))
        self.git(clone, "config", "remote.origin.url", declared)
        reference = Reference(name, declared, canonical, pin, upstream, clone)
        with self.manifest.open("ab") as handle:
            handle.write(f"{name} {declared} github:{pin}\n".encode())
        for url in (declared, declared.removesuffix(".git"), canonical, canonical + ".git"):
            self.state["endpoints"][url] = upstream.as_uri()
        self.metadata(declared.removesuffix(".git"), pin, canonical)
        self.metadata(canonical, pin, canonical)
        return reference

    def metadata(self, endpoint, pin, canonical):
        self.state["metadata"][endpoint] = {"stdout": json.dumps(dict(
            id=pin, nameWithOwner=canonical.removeprefix("https://github.com/"), url=canonical))}

    def advance(self, ref, filename="README.md"):
        (ref.upstream / filename).write_text("upstream advance\n")
        self.git(ref.upstream, "add", filename)
        self.git(ref.upstream, "commit", "--quiet", "-m", "advance")

    def prepare(self):
        self.state_path.write_text(json.dumps(self.state))

    def argv(self, *args):
        return [BASH, str(self.harness / "scripts/update-references.sh"), *args]

    def run(self, *args):
        self.prepare()
        return subprocess.run(self.argv(*args), env=self.env, cwd=self.root,
                              capture_output=True, text=True, timeout=25)

    def calls(self):
        return [json.loads(line) for line in self.log_path.read_text().splitlines()] if self.log_path.exists() else []


class MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not REAL_GIT or not BASH:
            raise RuntimeError("git and bash are required")
        cls.scratch = tempfile.TemporaryDirectory(prefix="eyragents-migration-")
        print(f"Private fixture root: {cls.scratch.name}", flush=True)
        cls.addClassCleanup(cls.scratch.cleanup)

    def fixture(self):
        fixture = Fixture(self.scratch.name)
        self.addCleanup(fixture.close)
        return fixture

    def result(self, fixture, result, message=None):
        output = result.stdout + result.stderr
        self.assertFalse([call for call in fixture.calls() if "blocked" in call], output)
        if message is None:
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("exact fetched default-branch parity", output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
            self.assertIn(message, output)

    def unchanged_urls(self, fixture, ref, manifest, config):
        self.assertEqual(fixture.manifest.read_bytes(), manifest)
        self.assertEqual((ref.clone / ".git/config").read_bytes(), config)

    def refuse_before_fetch(self, fixture, ref, message):
        before_clone = snapshot(ref.clone)
        before_manifest = snapshot(fixture.manifest)
        self.result(fixture, fixture.run(ref.name), message)
        self.assertEqual(snapshot(ref.clone), before_clone)
        self.assertEqual(snapshot(fixture.manifest), before_manifest)
        self.assertFalse([call for call in fixture.calls() if call.get("network") == "fetch"])

    def test_same_id_rename_and_owner_move_preserve_config_and_manifest(self):
        for canonical in ("https://github.com/old/renamed", "https://github.com/new-owner/project"):
            with self.subTest(canonical=canonical):
                f = self.fixture()
                ref = f.add_reference(canonical=canonical)
                f.advance(ref)
                pushurls = ["https://github.com/publisher/one.git", "git@github.com:publisher/two.git"]
                for url in pushurls:
                    f.git(ref.clone, "config", "--add", "remote.origin.pushurl", url)
                f.git(ref.clone, "config", "fixture.keep", "spacing and values")
                config_path = ref.clone / ".git/config"
                with config_path.open("ab") as handle:
                    handle.write(b"\n# retain unrelated configuration\n")
                config = config_path.read_bytes()
                manifest = (f"# pinned references\r\n\t{ref.name}  {ref.declared}\tgithub:{ref.pin}"
                            "  # retained comment\r\n\r\n# final comment without newline").encode()
                f.manifest.write_bytes(manifest)
                f.manifest.chmod(0o640)
                tag = f.git(ref.clone, "rev-parse", "refs/tags/stable")
                self.result(f, f.run())
                destination = (canonical + ".git").encode()
                self.assertEqual(f.manifest.read_bytes(), manifest.replace(ref.declared.encode(), destination))
                self.assertEqual(config_path.read_bytes(), config.replace(ref.declared.encode(), destination, 1))
                self.assertEqual(stat.S_IMODE(f.manifest.stat().st_mode), 0o640)
                self.assertEqual(f.git(ref.clone, "config", "--get-all", "remote.origin.pushurl").splitlines(), pushurls)
                self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), f.git(ref.upstream, "rev-parse", "HEAD"))
                self.assertEqual(f.git(ref.clone, "rev-parse", "refs/tags/stable"), tag)
                network = [call for call in f.calls() if "network" in call]
                self.assertEqual([call["network"] for call in network], ["ls-remote", "fetch"])
                self.assertTrue(all(call["endpoint"] == canonical + ".git" for call in network))
                self.assertTrue(any(call.get("preflight") for call in f.calls()))
                migrated_manifest = snapshot(f.manifest)
                migrated_config = snapshot(config_path)
                self.result(f, f.run(ref.name))
                self.assertEqual(snapshot(f.manifest), migrated_manifest, "idempotence rewrote manifest")
                self.assertEqual(snapshot(config_path), migrated_config, "idempotence rewrote config")

    def test_dry_run_before_and_after_migration_is_byte_and_metadata_preserving(self):
        f = self.fixture()
        ref = f.add_reference()
        f.advance(ref)
        for migrated in (False, True):
            with self.subTest(migrated=migrated):
                before_clone, before_manifest = snapshot(ref.clone), snapshot(f.manifest)
                call_start = len(f.calls())
                result = f.run("--dry-run", ref.name)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("plan: reference:", result.stdout)
                self.assertEqual(snapshot(ref.clone), before_clone)
                self.assertEqual(snapshot(f.manifest), before_manifest)
                self.assertFalse([call for call in f.calls()[call_start:] if "network" in call or "blocked" in call])
            if not migrated:
                self.result(f, f.run(ref.name))

    def test_distinct_origin_and_manifest_require_agreeing_identity(self):
        for failure in (None, "origin-id", "manifest-id", "canonical"):
            with self.subTest(failure=failure):
                f = self.fixture()
                ref = f.add_reference()
                origin = "https://github.com/earlier-owner/earlier-name"
                f.git(ref.clone, "config", "remote.origin.url", origin + ".git")
                f.metadata(origin, ref.pin, ref.canonical)
                if failure == "origin-id":
                    f.metadata(origin, "R_foreign", ref.canonical)
                elif failure == "manifest-id":
                    f.metadata(ref.declared.removesuffix(".git"), "R_reused", ref.canonical)
                elif failure == "canonical":
                    f.metadata(origin, ref.pin, "https://github.com/different/canonical")
                if failure:
                    self.refuse_before_fetch(f, ref, "canonical metadata disagreement" if failure == "canonical" else "identity mismatch")
                else:
                    f.advance(ref)
                    self.result(f, f.run(ref.name))
                    self.assertEqual(f.git(ref.clone, "config", "remote.origin.url"), ref.canonical + ".git")
                    self.assertIn((ref.canonical + ".git").encode(), f.manifest.read_bytes())
                    self.assertEqual({call["endpoint"] for call in f.calls() if call["tool"] == "gh"},
                                     {origin, ref.declared.removesuffix(".git")})

    def test_reused_declared_endpoint_cannot_adopt_new_id(self):
        f = self.fixture()
        ref = f.add_reference()
        f.metadata(ref.declared.removesuffix(".git"), "R_reused_name", ref.canonical)
        self.refuse_before_fetch(f, ref, "foreign or reused endpoint")

    def test_distinct_local_dot_git_endpoint_and_rewrite_refuse(self):
        for rewrite in (False, True):
            with self.subTest(rewrite=rewrite):
                f = self.fixture()
                ref = f.add_reference()
                other = ref.upstream.with_name(ref.upstream.name + ".git")
                f.git(f.root, "clone", "--quiet", ref.upstream.as_uri(), str(other))
                (other / "README.md").write_text("different endpoint advance\n")
                f.git(other, "commit", "--quiet", "-a", "-m", "advance other endpoint")
                declared = ref.upstream.as_uri()
                f.manifest.write_text(f"{ref.name} {declared}\n")
                f.git(ref.clone, "config", "remote.origin.url", declared if rewrite else other.as_uri())
                if rewrite:
                    f.git(ref.clone, "config", f"url.{other.as_uri()}.insteadOf", declared)
                self.refuse_before_fetch(f, ref, "redirecting URL rewrite" if rewrite
                                          else "origin does not match the declared endpoint")

    def test_legacy_suite_preserves_an_inherited_external_index(self):
        f = self.fixture()
        ref = f.add_reference()
        external_index = f.root / "caller.index"
        shutil.copyfile(ref.clone / ".git/index", external_index)
        before = snapshot(external_index)
        before_clone = snapshot(ref.clone)
        env = {**f.env, "PATH": os.defpath, "GIT_INDEX_FILE": str(external_index),
               "GIT_DIR": str(ref.clone / ".git"), "GIT_WORK_TREE": str(ref.clone),
               "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "fixture.injected",
               "GIT_CONFIG_VALUE_0": "caller-only"}
        result = subprocess.run([BASH, str(ROOT / "tests/update-references.sh")],
                                cwd=f.root, env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(snapshot(external_index), before)
        self.assertEqual(snapshot(ref.clone), before_clone)

    def test_partial_origin_migration_preserves_state_and_resumes(self):
        f = self.fixture()
        ref = f.add_reference()
        f.advance(ref)
        f.git(ref.clone, "config", "remote.origin.pushurl", "https://github.com/publisher/repo.git")
        before_config = (ref.clone / ".git/config").read_bytes()
        before_manifest = f.manifest.read_bytes()
        f.state["event"] = dict(action="drift-after-origin")
        result = f.run(ref.name)
        self.result(f, result, "manifest drift")
        self.assertIn("URL migration may be partial", result.stdout + result.stderr)
        migrated_config = before_config.replace(ref.declared.encode(), (ref.canonical + ".git").encode(), 1)
        self.assertEqual((ref.clone / ".git/config").read_bytes(), migrated_config)
        drifted_manifest = before_manifest + b"# concurrent edit after origin migration\n"
        self.assertEqual(f.manifest.read_bytes(), drifted_manifest)
        self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), f.git(ref.upstream, "rev-parse", "HEAD"))
        self.result(f, f.run(ref.name))
        self.assertEqual((ref.clone / ".git/config").read_bytes(), migrated_config)
        self.assertEqual(f.manifest.read_bytes(), drifted_manifest.replace(ref.declared.encode(), (ref.canonical + ".git").encode()))

    def test_detached_linked_and_shared_checkouts_refuse(self):
        for layout in ("detached", "linked", "git-link", "worktrees", "alternates"):
            with self.subTest(layout=layout):
                f = self.fixture()
                ref = f.add_reference()
                actual = ref.clone
                if layout == "detached":
                    f.git(ref.clone, "checkout", "--quiet", "--detach")
                elif layout == "linked":
                    actual = f.quarry / "linked-target"
                    ref.clone.rename(actual)
                    ref.clone.symlink_to(actual, target_is_directory=True)
                elif layout == "git-link":
                    store = f.root / "git-store"
                    (ref.clone / ".git").rename(store)
                    (ref.clone / ".git").symlink_to(store, target_is_directory=True)
                elif layout == "worktrees":
                    f.git(ref.clone, "worktree", "add", "--detach", str(f.root / "other-worktree"))
                else:
                    (ref.clone / ".git/objects/info/alternates").write_text(str(ref.upstream / ".git/objects") + "\n")
                before = snapshot(actual)
                manifest = snapshot(f.manifest)
                result = f.run(ref.name)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(snapshot(actual), before)
                self.assertEqual(snapshot(f.manifest), manifest)
                self.assertFalse([call for call in f.calls() if call["tool"] == "gh" or "network" in call])

    def test_malformed_duplicate_oversized_and_unavailable_metadata(self):
        cases = [
            ("not json", 0, "malformed GitHub metadata"),
            ('{"id":"R_fixture_1","id":"R_fixture_1"}', 0, "malformed GitHub metadata"),
            (" " * 64_001, 0, "oversized GitHub metadata"),
            ("", 1, "GitHub metadata unavailable"),
            ("[]", 0, "malformed GitHub canonical metadata"),
            ('{"id":"R_fixture_1","nameWithOwner":"old/renamed"}', 0, "malformed GitHub canonical metadata"),
            (json.dumps(dict(id="R_fixture_1", nameWithOwner="old/renamed",
                             url="https://github.com/another/project")), 0, "malformed GitHub canonical metadata"),
        ]
        for number, (raw, code, message) in enumerate(cases):
            with self.subTest(case=number):
                f = self.fixture()
                ref = f.add_reference()
                f.state["metadata"][ref.declared.removesuffix(".git")] = dict(stdout=raw, code=code)
                self.refuse_before_fetch(f, ref, message)

    def test_missing_invalid_and_duplicate_pins(self):
        for pin in ("", "github:", "gitlab:R_fixture_1", "github:bad:pin", "github:" + "x" * 257, "duplicate"):
            with self.subTest(pin=pin[:30]):
                f = self.fixture()
                ref = f.add_reference()
                if pin == "duplicate":
                    with f.manifest.open("ab") as handle:
                        handle.write(f"other https://github.com/other/repo.git github:{ref.pin}\n".encode())
                    message = "duplicate GitHub identity pin"
                else:
                    f.manifest.write_text(f"{ref.name} {ref.declared} {pin}\n")
                    message = "GitHub entries require a reviewed pin"
                self.refuse_before_fetch(f, ref, message)
                self.assertFalse(f.calls(), "invalid manifest reached external tools")

    def test_multiple_fetch_urls_and_origin_or_canonical_rewrites(self):
        for case in ("multiple", "origin-rewrite", "canonical-rewrite"):
            with self.subTest(case=case):
                f = self.fixture()
                ref = f.add_reference()
                if case == "multiple":
                    f.git(ref.clone, "config", "--add", "remote.origin.url", ref.canonical + ".git")
                    message = "multiple or missing origin fetch URLs"
                else:
                    rewritten = ref.declared if case == "origin-rewrite" else ref.canonical
                    f.git(ref.clone, "config", f"url.{ref.upstream.as_uri()}.insteadOf", rewritten)
                    message = "redirecting URL rewrite" if case == "origin-rewrite" else "canonical Git URL rewrite refused"
                self.refuse_before_fetch(f, ref, message)
                self.assertFalse([call for call in f.calls() if "network" in call])

    def test_dirty_ahead_and_diverged_clones_never_migrate_urls(self):
        for case in ("dirty", "ahead", "diverged"):
            with self.subTest(case=case):
                f = self.fixture()
                ref = f.add_reference()
                (ref.clone / "README.md").write_text("local work\n")
                if case != "dirty":
                    f.git(ref.clone, "commit", "--quiet", "-a", "-m", "local work")
                if case == "diverged":
                    f.advance(ref)
                manifest, config = f.manifest.read_bytes(), (ref.clone / ".git/config").read_bytes()
                head = f.git(ref.clone, "rev-parse", "HEAD")
                self.result(f, f.run(ref.name), "tracked changes" if case == "dirty" else "ahead or diverged")
                self.unchanged_urls(f, ref, manifest, config)
                self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), head)
                self.assertEqual((ref.clone / "README.md").read_text(), "local work\n")

    def test_untracked_and_ignored_collisions_preserve_local_files_and_urls(self):
        for ignored in (False, True):
            with self.subTest(ignored=ignored):
                f = self.fixture()
                ref = f.add_reference()
                collision = ref.clone / "local.txt"
                collision.write_text("keep me\n")
                if ignored:
                    (ref.clone / ".git/info/exclude").write_text("local.txt\n")
                f.advance(ref, "local.txt")
                manifest, config = f.manifest.read_bytes(), (ref.clone / ".git/config").read_bytes()
                head = f.git(ref.clone, "rev-parse", "HEAD")
                index = (ref.clone / ".git/index").read_bytes()
                self.result(f, f.run(ref.name), "refused; inspect local files")
                self.unchanged_urls(f, ref, manifest, config)
                self.assertEqual(collision.read_text(), "keep me\n")
                self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), head)
                self.assertEqual((ref.clone / ".git/index").read_bytes(), index)

    def test_moved_tag_refuses_atomic_fetch_and_url_migration(self):
        f = self.fixture()
        ref = f.add_reference()
        f.advance(ref)
        f.git(ref.upstream, "tag", "-d", "stable")
        f.git(ref.upstream, "tag", "stable")
        before_refs = f.git(ref.clone, "show-ref")
        manifest, config = f.manifest.read_bytes(), (ref.clone / ".git/config").read_bytes()
        self.result(f, f.run(ref.name), "fetch failed or would replace a tag")
        self.assertEqual(f.git(ref.clone, "show-ref"), before_refs)
        self.unchanged_urls(f, ref, manifest, config)

    def test_manifest_symlink_hardlink_and_read_only_layouts(self):
        for layout in ("symlink", "hardlink", "read-only", "read-only-parent"):
            with self.subTest(layout=layout):
                f = self.fixture()
                ref = f.add_reference()
                backing = f.root / "manifest-backing"
                if layout == "symlink":
                    f.manifest.rename(backing)
                    f.manifest.symlink_to(backing)
                    message = "unsafe manifest layout"
                else:
                    if layout == "hardlink":
                        os.link(f.manifest, backing)
                    elif layout == "read-only":
                        f.manifest.chmod(0o400)
                    else:
                        if os.geteuid() == 0:
                            continue  # Root's access check ignores directory write permission.
                        f.harness.chmod(0o500)
                    message = "single-link writable manifest and parent"
                original = f.manifest.read_bytes()
                self.refuse_before_fetch(f, ref, message)
                self.assertEqual(f.manifest.read_bytes(), original)
                if backing.exists():
                    self.assertEqual(backing.read_bytes(), original)

    def test_detected_manifest_drift_stops_remaining_selection(self):
        f = self.fixture()
        ref = f.add_reference()
        second = f.add_reference("second", "https://github.com/second/old.git",
                                 "https://github.com/second/new", "R_fixture_2")
        f.advance(ref)
        before_second = snapshot(second.clone)
        manifest, config = f.manifest.read_bytes(), (ref.clone / ".git/config").read_bytes()
        head = f.git(ref.clone, "rev-parse", "HEAD")
        f.state["event"] = dict(when="fetch", action="manifest-drift")
        self.result(f, f.run(ref.name, second.name), "manifest drift detected; remaining selection stopped")
        self.unchanged_urls(f, ref, manifest + b"# concurrent fixture edit\r\n", config)
        self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), head)
        self.assertEqual(snapshot(second.clone), before_second)
        self.assertFalse([call for call in f.calls() if call["tool"] == "gh" and "/second/" in call["endpoint"]])

    def test_detected_origin_drift_preserves_external_edit(self):
        f = self.fixture()
        ref = f.add_reference()
        f.advance(ref)
        manifest, config = f.manifest.read_bytes(), (ref.clone / ".git/config").read_bytes()
        head = f.git(ref.clone, "rev-parse", "HEAD")
        external = "https://github.com/external/edited.git"
        f.state["event"] = dict(when="fetch", action="origin-drift", url=external)
        self.result(f, f.run(ref.name), "origin drift detected")
        self.unchanged_urls(f, ref, manifest, config.replace(ref.declared.encode(), external.encode(), 1))
        self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), head)

    def test_multiple_selected_references_preserve_independent_lines(self):
        f = self.fixture()
        first = f.add_reference()
        second = f.add_reference("second", "https://github.com/two/old.git",
                                 "https://github.com/much-longer-owner/new-name", "R_fixture_2")
        untouched = f.add_reference("untouched", "https://github.com/three/old.git",
                                    "https://github.com/three/new", "R_fixture_3")
        manifest = (f"# selection\r\n{first.name}\t{first.declared}  github:{first.pin} # first\r\n"
                    f"# middle\r\n  {second.name}  {second.declared}\tgithub:{second.pin}\r\n"
                    f"{untouched.name} {untouched.declared} github:{untouched.pin}\r\n"
                    f"local {f.root.as_uri()}/absent-local-clone # two fields, unselected").encode()
        f.manifest.write_bytes(manifest)
        before_untouched = snapshot(untouched.clone)
        for ref in (first, second):
            f.advance(ref)
        self.result(f, f.run(second.name, first.name))
        expected = manifest
        for ref in (first, second):
            expected = expected.replace(ref.declared.encode(), (ref.canonical + ".git").encode())
            self.assertEqual(f.git(ref.clone, "rev-parse", "HEAD"), f.git(ref.upstream, "rev-parse", "HEAD"))
            self.assertEqual(f.git(ref.clone, "config", "remote.origin.url"), ref.canonical + ".git")
        self.assertEqual(f.manifest.read_bytes(), expected)
        self.assertEqual(snapshot(untouched.clone), before_untouched)

    def test_unsupported_and_local_endpoint_mismatches(self):
        for case in ("unsupported", "local-mismatch", "github-with-local-origin", "http-github"):
            with self.subTest(case=case):
                f = self.fixture()
                ref = f.add_reference()
                if case == "unsupported":
                    f.git(ref.clone, "config", "remote.origin.url", "ssh://git@example.invalid/owner/project.git")
                    message = "unsafe or unsupported endpoint"
                elif case == "local-mismatch":
                    f.manifest.write_text(f"{ref.name} {ref.upstream.as_uri()}\n")
                    f.git(ref.clone, "config", "remote.origin.url", (f.root / "different").as_uri())
                    message = "origin does not match the declared endpoint"
                elif case == "github-with-local-origin":
                    f.git(ref.clone, "config", "remote.origin.url", ref.upstream.as_uri())
                    message = "origin is not a supported GitHub endpoint"
                else:
                    f.manifest.write_text(f"{ref.name} http://github.com/old/project github:{ref.pin}\n")
                    message = "unsupported GitHub endpoint"
                self.refuse_before_fetch(f, ref, message)
                self.assertFalse([call for call in f.calls() if "network" in call])

    def test_network_shim_never_maps_get_url_and_refuses_unknown_endpoints(self):
        f = self.fixture()
        ref = f.add_reference()
        f.prepare()
        for endpoint, network in ((ref.canonical + ".git", False),
                                  ("https://github.com/not-allowed/repo.git", True)):
            args = ["--symref", endpoint, "HEAD"] if network else ["--get-url", endpoint]
            result = subprocess.run([str(f.root / "bin/git"), "-C", str(ref.clone), "ls-remote", *args],
                                    env=f.env, cwd=f.root, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 97 if network else 0, result.stderr)
            if not network:
                self.assertEqual(result.stdout, endpoint + "\n")
        self.assertIn("unexpected network endpoint", f.calls()[-1]["blocked"])

    def test_sigterm_reaps_active_owned_child_and_preserves_urls(self):
        f = self.fixture()
        ref = f.add_reference()
        f.advance(ref)
        before_clone, before_manifest = snapshot(ref.clone), snapshot(f.manifest)
        f.state["event"] = dict(when="fetch", action="hang")
        f.prepare()
        proc = subprocess.Popen(f.argv(ref.name), env=f.env, cwd=f.root, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                start_new_session=True)
        child_fd = None
        try:
            deadline = time.monotonic() + 10
            while not f.marker.exists() and proc.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(f.marker.exists(), "updater did not reach the bounded fake fetch")
            # Marker creation and writing are distinct; wait for its complete JSON.
            while True:
                try:
                    child = json.loads(f.marker.read_text())
                    break
                except json.JSONDecodeError:
                    self.assertLess(time.monotonic(), deadline, "incomplete child marker")
                    time.sleep(0.01)
            self.assertEqual(child["pgid"], child["pid"], "child is not in its owned process group")
            child_fd = os.pidfd_open(child["pid"])
            self.assertFalse(select.select([child_fd], [], [], 0)[0], "synthetic child already exited")
            start = time.monotonic()
            proc.send_signal(signal.SIGTERM)
            stdout, stderr = proc.communicate(timeout=6)
            self.assertEqual(proc.returncode, 128 + signal.SIGTERM, stdout + stderr)
            self.assertIn("interruption", stderr)
            self.assertTrue(select.select([child_fd], [], [], 1)[0], "active child survived updater exit")
            self.assertLess(time.monotonic() - start, 7)
            self.assertEqual(snapshot(ref.clone), before_clone)
            self.assertEqual(snapshot(f.manifest), before_manifest)
            self.assertFalse([call for call in f.calls() if "blocked" in call])
        finally:
            # pidfd binds failure cleanup to this worker, even if the numeric PID is reused.
            if child_fd is not None:
                if not select.select([child_fd], [], [], 0)[0]:
                    signal.pidfd_send_signal(child_fd, signal.SIGKILL)
                os.close(child_fd)
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
