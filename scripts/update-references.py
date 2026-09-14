#!/usr/bin/env python3
"""Preservation-first reference refresh under native controls and trusted inputs.

H's reference workflow permits same-project relocation after pinned-ID checks.
Detected drift refuses; Git locks and atomic manifest replacement do not provide
multi-repository atomicity or containment against concurrent/untrusted writers.
"""

import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


class Refusal(Exception):
    pass


class Drift(Refusal):
    """Stop the selection when its shared input has changed."""


CANCELLED = 0


def interrupt(signum, _frame):
    # Defer exceptions across Popen's spawn/handle-assignment boundary.
    global CANCELLED
    CANCELLED = signum


def cancellation_check():
    if CANCELLED:
        raise KeyboardInterrupt


def require(condition, message):
    if not condition:
        raise Refusal(message)


def command(argv, category, *, write=False, allowed=(0,), timeout=60):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never",
               GH_PROMPT_DISABLED="1", GH_PAGER="cat")
    if not write:
        env["GIT_OPTIONAL_LOCKS"] = "0"
    proc = None
    try:
        cancellation_check()
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, env=env, start_new_session=True)
        deadline = time.monotonic() + timeout
        while True:
            cancellation_check()
            remaining = deadline - time.monotonic()
            require(remaining > 0, category + ": timed out")
            try:
                output, _ = proc.communicate(timeout=min(remaining, 0.25))
                break
            except subprocess.TimeoutExpired:
                pass
        require(proc.returncode in allowed, category)
        cancellation_check()
        return proc.returncode, output.decode("utf-8")
    except (OSError, UnicodeError):
        raise Refusal(category + ": unavailable or invalid output") from None
    finally:
        if proc is not None:
            if proc.returncode is None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    raise Drift(category + ": process cleanup unconfirmed; preserve state") from None
            proc.stdout.close()


def git(clone, *args, category="Git inspection failed", **kwargs):
    return command(["git", "-C", str(clone), *args], category, **kwargs)


def endpoint(url):
    require(isinstance(url, str) and re.fullmatch(r"[!-~]+", url)
            and not any(c in url for c in "?#\\%"), "unsafe or unsupported endpoint")
    # The fixed GitHub SSH user is supported; arbitrary URI userinfo is not.
    for prefix in ("git@github.com:", "ssh://git@github.com/"):
        if url.startswith(prefix):
            url = "https://github.com/" + url[len(prefix):]
    try:
        parts = urlsplit(url)
        if url.startswith("/") or url.startswith("file:///"):
            require(not parts.netloc, "unsupported local endpoint")
        else:
            require(parts.scheme in ("https", "http") and parts.hostname
                    and "@" not in parts.netloc and parts.port != 0
                    and re.fullmatch(r"[A-Za-z0-9.:[\]-]+", parts.netloc),
                    "unsafe or unsupported endpoint")
        require(not any(p in (".", "..") for p in parts.path.split("/")),
                "unsupported endpoint path")
    except ValueError:
        raise Refusal("malformed endpoint") from None
    github = (parts.hostname or "").rstrip(".") == "github.com"
    normalized = url.removesuffix("/").removesuffix(".git") if github else url
    if github:
        require(parts.scheme == "https" and parts.netloc == "github.com"
                and project_name(normalized.removeprefix("https://github.com/")),
                "unsupported GitHub endpoint")
    return normalized, github


def project_name(value):
    return (isinstance(value, str)
            and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", value)
            and value.split("/")[1] not in (".", ".."))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "malformed GitHub metadata")
        result[key] = value
    return result


def identity(url, pin):
    _, raw = command(["gh", "repo", "view", url, "--json", "id,nameWithOwner,url"],
                     "GitHub metadata unavailable")
    require(len(raw) <= 64_000, "oversized GitHub metadata")
    try:
        data = json.loads(raw, object_pairs_hook=unique_object)
    except (ValueError, RecursionError):
        raise Refusal("malformed GitHub metadata") from None
    require(isinstance(data, dict) and set(data) == {"id", "nameWithOwner", "url"}
            and project_name(data["nameWithOwner"])
            and data["url"] == "https://github.com/" + data["nameWithOwner"],
            "malformed GitHub canonical metadata")
    require(data["id"] == pin, "GitHub identity mismatch; foreign or reused endpoint")
    endpoint(data["url"])
    return data["url"]


def stamp(info):
    return tuple(getattr(info, "st_" + key) for key in
                 ("dev", "ino", "mode", "uid", "gid", "nlink", "size", "mtime_ns", "ctime_ns"))


class Manifest:
    def __init__(self, path):
        self.path = path
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and path.resolve() == path
                and info.st_size <= 1_000_000, "unsafe manifest layout or size")
        self.version = stamp(info)
        self.data = path.read_bytes()
        self.lines = self.data.splitlines(keepends=True)
        self.entries = {}
        pins = set()
        for number, line in enumerate(self.lines):
            # A comment starts at a token boundary, never inside a URL fragment.
            body = re.split(rb"(?:^|[ \t])#", line, maxsplit=1)[0]
            tokens = list(re.finditer(rb"[^ \t\r\n]+", body))
            if not tokens:
                continue
            require(len(tokens) in (2, 3), "invalid reference manifest entry")
            fields = [t.group().decode("ascii") for t in tokens]
            name, url = fields[:2]
            require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name)
                    and name not in self.entries, "invalid or duplicate reference name")
            _, github = endpoint(url)
            pin = fields[2].removeprefix("github:") if len(fields) == 3 else None
            require((github and len(fields) == 3 and fields[2].startswith("github:")
                     and re.fullmatch(r"[A-Za-z0-9_+/=-]{1,256}", pin))
                    or (not github and len(fields) == 2), "GitHub entries require a reviewed pin")
            require(pin is None or pin not in pins, "duplicate GitHub identity pin")
            if pin:
                pins.add(pin)
            self.entries[name] = (url, pin, number, tokens[1].span())
        require(self.entries, "reference manifest is empty")
        self.check()

    def check(self, writable=False):
        cancellation_check()
        try:
            info = self.path.lstat()
            if (stamp(info) != self.version or self.path.resolve() != self.path
                    or self.path.read_bytes() != self.data):
                raise Drift("manifest drift detected; remaining selection stopped")
        except OSError:
            raise Drift("manifest unavailable; remaining selection stopped") from None
        if writable:
            require(info.st_uid == os.geteuid() and info.st_nlink == 1
                    and info.st_mode & stat.S_IWUSR and os.access(self.path, os.W_OK)
                    and self.path.parent.stat().st_uid == os.geteuid()
                    and os.access(self.path.parent, os.W_OK | os.X_OK),
                    "migration requires an owned single-link writable manifest and parent")

    def replace(self, name, url, recheck):
        self.check(writable=True)
        _, _, number, (start, end) = self.entries[name]
        lines = self.lines.copy()
        lines[number] = lines[number][:start] + url.encode("ascii") + lines[number][end:]
        data = b"".join(lines)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=self.path.parent, prefix=".references-",
                                             delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(data)
                handle.flush()
                os.fchmod(handle.fileno(), stat.S_IMODE(self.version[2]))
                os.fsync(handle.fileno())
            recheck()
            self.check(writable=True)
            os.replace(temporary, self.path)
            directory_fd = os.open(self.path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
            self.data, self.lines = data, lines
            self.version = stamp(self.path.lstat())
            self.check()
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def origin(clone):
    values = []
    for scope in (("--local", "--no-includes"), ("--includes",)):
        _, output = git(clone, "config", *scope, "--null", "--get-all", "remote.origin.url",
                        category="cannot inspect origin fetch URL")
        items = output.split("\0")
        require(len(items) == 2 and items[-1] == "", "multiple or missing origin fetch URLs")
        endpoint(items[0])
        values.append(items[0])
    _, effective = git(clone, "remote", "get-url", "--all", "origin",
                       category="cannot resolve origin fetch URL")
    effective = effective.removesuffix("\n")
    require(values[0] == values[1] and endpoint(effective) == endpoint(values[0]),
            "ambiguous origin configuration or redirecting URL rewrite")
    return values[0], effective


def preflight(clone):
    require(clone.is_dir(), "missing clone; explicit bootstrap required")
    require(clone.resolve() == clone and (clone / ".git").is_dir()
            and not (clone / ".git").is_symlink(), "linked or non-standalone checkout")
    require(stat.S_ISREG((clone / ".git/config").lstat().st_mode)
            and not os.path.lexists(clone / ".git/objects/info/alternates")
            and not os.path.lexists(clone / ".git/worktrees"), "unsupported shared Git layout")
    for flag, expected in (("--show-toplevel", clone), ("--absolute-git-dir", clone / ".git"),
                           ("--git-common-dir", clone / ".git")):
        _, value = git(clone, "rev-parse", "--path-format=absolute", flag)
        require(value.removesuffix("\n") == str(expected), "not a standalone checkout")
    git(clone, "symbolic-ref", "--quiet", "--short", "HEAD", category="detached checkout")
    clean(clone)


def clean(clone):
    _, status = git(clone, "status", "--porcelain", "--untracked-files=no")
    require(not status, "tracked changes; leave local work for inspection")


def parity(clone, branch):
    _, head = git(clone, "rev-parse", "--verify", "HEAD^{commit}")
    _, upstream = git(clone, "rev-parse", "--verify", "refs/remotes/origin/" + branch + "^{commit}")
    _, current = git(clone, "symbolic-ref", "--quiet", "HEAD", category="detached refreshed checkout")
    require(re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\n", head) and head == upstream
            and current == "refs/heads/" + branch + "\n", "checkout does not match fetched upstream")
    clean(clone)


def refresh(name, clone, manifest, dry_run, progress):
    declared, pin, _, _ = manifest.entries[name]
    preflight(clone)
    original = origin(clone)
    expected, github = endpoint(declared)
    actual, actual_github = endpoint(original[0])
    migration = False
    destination = "origin"
    if github:
        require(actual_github, "origin is not a supported GitHub endpoint")
        canonical = identity(expected, pin)
        if actual != expected:
            require(identity(actual, pin) == canonical, "GitHub canonical metadata disagreement")
        destination = canonical + ".git"
        migration = expected != canonical or actual != canonical
        if migration:
            manifest.check(writable=True)
            config = clone / ".git/config"
            info = config.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid()
                    and info.st_nlink == 1 and info.st_mode & stat.S_IWUSR,
                    "unsupported origin configuration layout for migration")
            print(f"verified: {name}: canonical relocation to {canonical}")
    else:
        require(actual == expected, "origin does not match the declared endpoint")

    def recheck():
        manifest.check(writable=migration)
        require(origin(clone) == original, "origin drift detected")
        if github:
            _, expanded = git(clone, "ls-remote", "--get-url", destination)
            require(endpoint(expanded.removesuffix("\n"))[0] == canonical
                    and expanded.startswith("https://github.com/"), "canonical Git URL rewrite refused")

    recheck()
    if dry_run:
        print(f"plan: {name}: conditional tag-preserving fetch/fast-forward"
              + (" and verified URL migration" if migration else "")
              + "; later parity requires successful refresh and rechecks")
        return

    _, remote = git(clone, "ls-remote", "--symref", destination, "HEAD",
                    category="default-branch lookup failed")
    branches = re.findall(r"^ref: refs/heads/([^\n]+)\tHEAD$", remote, re.MULTILINE)
    require(len(branches) == 1, "unsupported default branch")
    branch = branches[0]
    git(clone, "check-ref-format", "--branch", branch, category="unsupported default branch")
    recheck()
    clean(clone)
    progress.append("fetch may have changed objects/refs; state preserved, no rollback")
    git(clone, "-c", "fetch.pruneTags=false", "-c", "remote.origin.pruneTags=false",
        "fetch", "--quiet", "--atomic", "--no-force", "--tags", "--prune", "--no-prune-tags",
        "--refmap=", destination, "refs/heads/*:refs/remotes/origin/*", write=True,
        timeout=180, category="fetch failed or would replace a tag")
    progress[:] = ["fetch completed; checkout may have advanced; state preserved, no rollback"]
    recheck()
    clean(clone)
    tracking = "refs/remotes/origin/" + branch
    exists, _ = git(clone, "show-ref", "--verify", "--quiet", "refs/heads/" + branch,
                    allowed=(0, 1))
    if exists == 0:
        git(clone, "merge-base", "--is-ancestor", "refs/heads/" + branch, tracking,
            category="default branch is ahead or diverged")
        checkout = [branch, "--"]
    else:
        checkout = ["-b", branch, "--track", "origin/" + branch, "--"]
    git(clone, "checkout", "--quiet", "--no-overwrite-ignore", *checkout, write=True,
        category="checkout refused; inspect local files")
    git(clone, "merge", "--quiet", "--ff-only", "--no-overwrite-ignore", tracking, write=True,
        category="fast-forward refused; inspect local files")
    parity(clone, branch)
    progress[:] = ["refresh completed; state preserved, no rollback"]
    recheck()
    if migration:
        progress[:] = ["refresh completed; URL migration may be partial; state preserved, no rollback"]
        if actual != canonical:
            git(clone, "config", "--local", "--fixed-value", "--replace-all", "remote.origin.url",
                destination, original[0], write=True, category="origin URL migration failed")
            original = (destination, destination)
            recheck()
        if expected != canonical:
            manifest.replace(name, destination, recheck)
        parity(clone, branch)
    recheck()
    print(f"ok:   {name}: exact fetched default-branch parity"
          + ("; verified URL migration completed" if migration else ""))


def main():
    overrides = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_NAMESPACE",
                 "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_OBJECT_DIRECTORY",
                 "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_SHALLOW_FILE", "GIT_GRAFT_FILE",
                 "GIT_PREFIX", "GIT_SUPER_PREFIX", "GIT_QUARANTINE_PATH", "GIT_REPLACE_REF_BASE",
                 "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_IMPLICIT_WORK_TREE")
    require(not any(key in os.environ for key in overrides), "Git context environment override refused")
    root = Path(__file__).resolve().parent.parent
    manifest = Manifest(root / "references.txt")
    args = sys.argv[1:]
    dry_run = bool(args and args[0] == "--dry-run")
    if dry_run:
        args = args[1:]
    if any(name not in manifest.entries for name in args):
        print("FAIL: arguments must name declared references (optional --dry-run first)", file=sys.stderr)
        return 64
    quarry = Path(os.path.abspath(os.environ.get("QUARRY") or str(Path.home() / "Projects/quarry")))
    failed = 0
    for name in manifest.entries:
        if args and name not in args:
            continue
        progress = []
        try:
            manifest.check()
            refresh(name, quarry / name, manifest, dry_run, progress)
        except (Refusal, OSError, ValueError, RuntimeError, KeyboardInterrupt) as error:
            category = str(error) if isinstance(error, Refusal) else "local input failure or interruption"
            print(f"FAIL: {name}: {category}" + ("; " + progress[0] if progress else ""), file=sys.stderr)
            failed = 1
            if isinstance(error, (Drift, KeyboardInterrupt)):
                break
    return 128 + CANCELLED if CANCELLED else failed


if __name__ == "__main__":
    for interrupted_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(interrupted_signal, interrupt)
    try:
        sys.exit(main())
    except (Refusal, OSError, ValueError, RuntimeError, KeyboardInterrupt) as error:
        category = str(error) if isinstance(error, Refusal) else "local input unavailable or interrupted"
        print("FAIL: " + category, file=sys.stderr)
        sys.exit(128 + CANCELLED if CANCELLED else 1)
