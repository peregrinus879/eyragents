"""EyrAgents guardrails for Hermes 0.19's local native-tool dispatch.

Keep Hermes's toolset and learning intact. This is not a sandbox: arbitrary
shell/Python, interactive-process input, remote backends and foreign plugins
have distinct authority. Missing/disabled plugins are an upstream fail-open
condition, checked by deployment, not an isolation guarantee.

Request middleware makes local file operands task-absolute because 0.19's
backend may otherwise use a shared environment cwd. The internal binding
adaptations compose file_tools' read and search-result safety helpers, retaining
native denials and checking lexical search paths before they lose their spelling
to resolution. They filter returned paths, not backend traversal. Revalidate
these interfaces on Hermes updates.
"""

from __future__ import annotations

from collections import Counter
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess

SECRET_DIRS = {".ssh", ".aws", ".gnupg", ".kube", ".mozilla", ".password-store", "secrets"}
SECRET_FILES = {
    ".env", ".envrc", ".netrc", ".npmrc", ".pypirc", "auth.json",
    "credentials", ".credentials.json", ".bash_history", ".zsh_history",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
}
SECRET_GLOBS = (".env.*", "credentials.*", "*.key", "*.pem", "*.p12", "*.pfx",
                "*.keytab", "ssh_host_*_key")
SECRET_SUFFIXES = (
    ".config/gh/hosts.yml", ".docker/config.json", ".hermes/config.yaml",
    ".codex/config.toml",
)
SECRET_TREES = (".config/BraveSoftware", ".config/chromium", ".config/google-chrome",
                ".config/1Password", ".config/Bitwarden", ".local/share/keyrings")
# Component suffixes also cover recognisable copies. This finite inventory
# cannot identify arbitrary renamed copies or every hardlink alias.
SYSTEM_FILES = (
    "etc/shadow", "etc/shadow-", "etc/gshadow", "etc/gshadow-",
    "etc/security/opasswd", "etc/security/opasswd.old", "etc/krb5.keytab",
    "etc/ipsec.secrets", "var/lib/NetworkManager/secret_key", "var/lib/systemd/credential.secret",
)
SYSTEM_TREES = (
    "etc/ssl/private", "etc/credstore", "etc/credstore.encrypted",
    "usr/lib/credstore", "usr/lib/credstore.encrypted", "etc/cryptsetup-keys.d",
    "etc/NetworkManager/system-connections", "usr/lib/NetworkManager/system-connections",
    "var/lib/iwd", "etc/wireguard", "etc/openvpn", "etc/ipsec.d/private",
    "etc/samba/private", "var/lib/samba/private", "etc/pacman.d/gnupg", "etc/letsencrypt",
)
RAW_FILES = ("proc/kcore", "proc/vmcore", "dev/mem", "dev/port")
RAW_TREES = ("var/lib/systemd/coredump", "var/crash", "sys/kernel/debug", "sys/kernel/tracing")
SESSION_FILES = (".claude.json", ".claude/history.jsonl", ".codex/history.jsonl",
                 ".codex/session_index.jsonl", ".local/share/fish/fish_history",
                 ".local/state/fish/fish_history")
SESSION_TREES = (
    ".claude/projects", ".claude/sessions", ".claude/session-env", ".claude/tasks", ".claude/debug",
    ".codex/sessions", ".codex/archived_sessions", ".codex/log",
    ".local/share/opencode", ".local/state/opencode", ".cache/opencode",
)
CONFIG_STORES = ("BraveSoftware", "chromium", "google-chrome", "1Password", "Bitwarden")
XDG_DEFAULTS = {"XDG_CONFIG_HOME": ".config", "XDG_DATA_HOME": ".local/share",
                "XDG_CACHE_HOME": ".cache", "XDG_STATE_HOME": ".local/state"}
BROWSE_EXCLUDED = tuple(Path(p) for p in ("/home", "/root", "/proc", "/dev", "/run", "/mnt", "/media", "/Volumes"))
LOCAL_FILESYSTEMS = {"ext2", "ext3", "ext4", "xfs", "btrfs", "f2fs", "zfs", "erofs", "squashfs", "overlay"}
FILE_TOOLS = {"read_file", "search_files", "write_file", "patch"}
HEADER = re.compile(r"^(\*\*\*\s*(?:Update|Add|Delete)\s+File:\s*)(.+)$")
MOVE = re.compile(r"^(\*\*\*\s*Move\s+File:\s*)(.+?)\s*->\s*(.+)$")
_ERROR = "_eyragents_refusal"
_ready = False
OTHER_SESSION_ROOT = Path("/tmp/opencode")
_ALLOW_MISSING = getattr(os.path, "ALLOW_MISSING", None)


def below(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def absolute(value: str, cwd: Path) -> Path:
    if not isinstance(value, str) or not value or any(ord(x) < 32 for x in value):
        raise ValueError("invalid path")
    path = Path(value).expanduser()
    # Retain '..' until realpath resolves preceding symlinks. abspath would
    # silently select a different file for link/../name.
    return path if path.is_absolute() else cwd / path


def resolve_target(path: Path) -> Path:
    # Tolerate prospective leaves, not EACCES, ENOTDIR or symlink loops. Keep
    # symlink-before-'..' semantics without adding a Python-version prerequisite.
    if _ALLOW_MISSING is not None:
        return Path(os.path.realpath(path, strict=_ALLOW_MISSING))
    resolved = path.resolve()
    # Older realpath may suppress errors. Probe both spellings and all their
    # traversed prefixes so an inaccessible path cannot masquerade as missing.
    for spelling in (path, resolved):
        for prefix in (spelling, *spelling.parents):
            try:
                prefix.stat()
            except FileNotFoundError:
                pass
    return resolved


def inventory_target(path: Path) -> Path:
    # Discovery of outward aliases is best-effort for inaccessible declared
    # stores. Retain the literal exclusion without disabling unrelated work.
    # Such aliases cannot be completely discovered through an inaccessible
    # parent. Requested-target resolution remains strict and never uses this
    # fallback; other metadata errors still refuse the unverifiable layout.
    try:
        return resolve_target(path)
    except PermissionError:
        return path


def home_paths(home: Path) -> set[Path]:
    # context supplies the lexical HOME; keep its canonical spelling as well.
    if not home.is_absolute() or home == Path("/"):
        raise ValueError("unsupported home")
    return {home, resolve_target(home)}


def xdg_paths(home: Path) -> dict[str, set[Path]]:
    result = {}
    for variable, suffix in XDG_DEFAULTS.items():
        roots = {h / suffix for h in home_paths(home)}
        value = os.environ.get(variable)
        if value:
            root = absolute(value, home)
            # XDG requires an absolute path. Unsupported layouts must not
            # silently fall back and leave a relocated store uncovered.
            if not Path(value).is_absolute() or root == Path("/") or root in home_paths(home):
                raise ValueError("unsupported XDG root")
            roots.add(root)
        roots |= {inventory_target(p) for p in roots}
        if Path("/") in roots or roots & home_paths(home):
            raise ValueError("unsupported resolved XDG root")
        result[variable] = roots
    return result


def protected_paths(home: Path) -> tuple[set[Path], set[Path]]:
    homes = home_paths(home)
    files = {h / p for h in homes for p in (*SECRET_SUFFIXES, *SECRET_FILES, *SESSION_FILES)}
    trees = {h / p for h in homes for p in (*SECRET_DIRS, *SECRET_TREES, *SESSION_TREES)}
    # Resolve the declared store itself, not just its containing XDG root:
    # an ordinary-looking alias directly to a relocated store stays protected.
    xdg = xdg_paths(home)
    for root in xdg["XDG_CONFIG_HOME"]:
        trees.update(root / p for p in CONFIG_STORES)
        files.add(root / "gh/hosts.yml")
    for root in xdg["XDG_DATA_HOME"]:
        trees.update(root / p for p in ("keyrings", "opencode"))
        files.add(root / "fish/fish_history")
    for variable in ("XDG_STATE_HOME", "XDG_CACHE_HOME"):
        trees.update(root / "opencode" for root in xdg[variable])
    files.update(root / "fish/fish_history" for root in xdg["XDG_STATE_HOME"])
    for variable, file_names, tree_names in (
        ("CODEX_HOME", ("config.toml", "auth.json", "history.jsonl", "session_index.jsonl"),
         ("sessions", "archived_sessions", "log")),
        ("CLAUDE_CONFIG_DIR", (".credentials.json", "history.jsonl"),
         ("projects", "sessions", "session-env", "tasks", "debug")),
        ("HERMES_HOME", ("config.yaml", "auth.json", ".env"), ()),
    ):
        value = os.environ.get(variable)
        if value:
            root = absolute(value, home)
            if not Path(value).is_absolute() or inventory_target(root) == Path("/"):
                raise ValueError("unsupported application root")
            files.update(root / p for p in file_names)
            trees.update(root / p for p in tree_names)
    files.update(Path("/") / p for p in (*SYSTEM_FILES, *RAW_FILES))
    trees.update(Path("/") / p for p in (*SYSTEM_TREES, *RAW_TREES))
    files |= {inventory_target(p) for p in files}
    trees |= {inventory_target(p) for p in trees}
    return files, trees


def suffix_match(path: Path, files, trees) -> bool:
    text = path.as_posix()
    return (any(text.endswith("/" + suffix) for suffix in files) or
            any("/" + tree + "/" in text + "/" for tree in trees))


def secret(path: Path) -> bool:
    for candidate in (path, resolve_target(path)):
        parts = candidate.parts
        if any(part in SECRET_DIRS for part in parts):
            return True
        if any(part in SECRET_FILES or any(fnmatch.fnmatchcase(part, p) for p in SECRET_GLOBS)
               for part in parts):
            return True
        if suffix_match(candidate, (*SECRET_SUFFIXES, *SYSTEM_FILES), (*SECRET_TREES, *SYSTEM_TREES)):
            return True
    return False


def workspace(cwd: Path) -> Path:
    for directory in (cwd, *cwd.parents):
        if (directory / ".git").exists():
            return directory
    return cwd


def path_denial(path: Path, write: bool, home: Path) -> str | None:
    if secret(path):
        return "credential-shaped files and stores are not accessible"
    files, trees = protected_paths(home)
    homes = home_paths(home)
    for candidate in (path, resolve_target(path)):
        if candidate in files or any(below(candidate, p) for p in trees):
            return "protected stores and other tools' histories are not accessible"
        if suffix_match(candidate, RAW_FILES, RAW_TREES):
            return "raw payloads and sensitive kernel interfaces require scoped diagnostics"
        if suffix_match(candidate, SESSION_FILES, SESSION_TREES):
            return "other tools' histories are protected"
        if any(below(candidate, p) for h in homes for p in (h / ".agents/hooks", inventory_target(h / ".agents/hooks"))):
            return "the installed commit gate is protected"
        if below(candidate, OTHER_SESSION_ROOT) or below(candidate, inventory_target(OTHER_SESSION_ROOT)) or re.match(
            r"^/(?:var/)?tmp/(?:claude-[^/]+|codex[^/]*)(?:/|$)", str(candidate)
        ):
            return "other tools' session roots are protected"
        if write:
            if ".git" in candidate.parts:
                return "Git internals must be changed through the reviewed Git workflow"
            if any(below(candidate, h / ".hermes/plugins") or candidate == h / ".hermes/SOUL.md" for h in homes):
                return "managed policy and agent identity require an explicit configuration task"
            if any(below(candidate, h / ".agents") for h in homes):
                return "shared guidance and skills are repository-owned; edit their authorized source checkout"
            if any(below(candidate, root / "git") for root in xdg_paths(home)["XDG_CONFIG_HOME"]):
                return "Git configuration requires an explicit configuration task"
    if write and path.exists() and path.is_file() and path.stat().st_nlink != 1:
        return "native mutation of multiply-linked files requires ownership review"
    return None


def mount_table() -> list[tuple[Path, str, str, str, str | None]] | None:
    """Bounded OS metadata only. Unknown layouts provide no new standing grant."""
    try:
        with open("/proc/self/mountinfo", encoding="utf-8") as stream:
            text = stream.read(1024 * 1024 + 1)
        if not text or len(text) > 1024 * 1024:
            return None

        def unescape(value):
            value = re.sub(r"\\(040|011|012|134)", lambda m: chr(int(m[1], 8)), value)
            if "\\" in value or any(ord(c) < 32 or ord(c) == 127 for c in value):
                raise ValueError("unsupported mount field")
            return value

        mounts, ids, points = [], set(), set()
        for line in text.splitlines():
            fields = line.split(" ")
            separator = fields.index("-")
            if separator < 6 or len(fields) != separator + 4 or any(not f for f in fields):
                return None
            if not re.fullmatch(r"[1-9]\d*", fields[0]) or not re.fullmatch(r"0|[1-9]\d*", fields[1]) or not re.fullmatch(r"\d+:\d+", fields[2]):
                return None
            if fields[0] in ids or any(not re.fullmatch(r"(?:shared|master|propagate_from):\d+|unbindable", f)
                                       for f in fields[6:separator]):
                return None
            fields = [unescape(field) for field in fields]
            if any(options.split(",")[0] not in {"rw", "ro"} or "" in options.split(",")
                   for options in (fields[5], fields[-1])):
                return None
            root, point = fields[3], fields[4]
            if any(not p.startswith("/") or os.path.normpath(p) != p or p.startswith("//") for p in (root, point)):
                return None
            if point == "/" and point in points:
                return None  # Without a unique root no subtree is classifiable.
            ids.add(fields[0])
            points.add(point)
            subvolumes = [option.removeprefix("subvol=") for option in fields[-1].split(",") if option.startswith("subvol=")]
            if len(subvolumes) > 1:
                return None
            mounts.append((Path(point), root, fields[separator + 1], fields[2], subvolumes[0] if subvolumes else None))
        return mounts if "/" in points else None
    except (OSError, ValueError, UnicodeError):
        return None


def mounted_readable(path: Path, home: Path, mounts, recursive: bool = False) -> bool:
    if not mounts:
        return False
    counts = Counter(mount[0] for mount in mounts)
    if counts[Path("/")] != 1:
        return False
    sources = Counter((mount[3], mount[1]) for mount in mounts)
    homes = home_paths(home)

    def classified(mount):
        point, source_root, filesystem, device, subvolume = mount
        if counts[point] != 1:
            # Preserve stacked entries in the table: their entire subtree is
            # ambiguous, including apparently ordinary descendants. A recursive
            # query crossing that subtree also asks; unrelated paths still work.
            return False
        if point == Path("/"):
            # The unique actual '/' is an independently identified anchor,
            # regardless of record order or whole-root mirrors elsewhere.
            # Only this mountpoint gets the exception; its mirrors still fail
            # the full-table source-identity check below.
            return filesystem in LOCAL_FILESYSTEMS
        if sources[(device, source_root)] != 1:
            # A whole filesystem/subvolume can also be visible at a non-ancestor
            # user-storage mountpoint. Check the complete table before any
            # non-root positive fast path. Distinct Btrfs subvolumes on the same device
            # keep their independent eligibility.
            return False
        if filesystem == "sysfs" and point == Path("/sys") and source_root == "/":
            return True
        if filesystem == "cgroup2" and point == Path("/sys/fs/cgroup") and source_root == "/":
            return True
        # Standard separate OS/home filesystems are useful on Arch/WSL. A
        # second mount of the same device/root may be a bind, so leave it asking.
        if point in {Path("/home"), *homes} and filesystem == "btrfs" and subvolume == source_root:
            # A mount of the declared subvolume root is distinguishable from a
            # bind of an interior directory. Other nested mounts still ask.
            return source_root.startswith("/")
        standard = {Path("/boot"), Path("/efi"), Path("/boot/efi"), Path("/usr"), Path("/home"), *homes}
        if point in {Path("/tmp"), Path("/var/tmp")} and filesystem == "tmpfs" and source_root == "/":
            return not any(other[0] != point and other[3] == device for other in mounts)
        if point not in standard or filesystem not in LOCAL_FILESYSTEMS | {"vfat"} or source_root != "/":
            return False
        return not any(other[0] != point and other[3] == device for other in mounts)

    parents = [m for m in mounts if below(path, m[0])]
    if not parents or not all(classified(m) for m in parents):
        return False
    return not recursive or all(classified(m) for m in mounts if below(m[0], path))


def standing_read(path: Path, home: Path, mounts, recursive: bool = False) -> bool:
    homes = home_paths(home)
    for candidate in (Path(os.path.normpath(path)), resolve_target(path)):
        if candidate == Path("/") or candidate in homes:
            return False
        # The home exception is narrower than a containing /tmp or system
        # root, including when HOME itself uses a nonstandard resolved location.
        local_homes = [h for h in homes if below(candidate, h)]
        if local_homes:
            for h in local_homes:
                first = candidate.relative_to(h).parts[0]
                if first != "Projects" and not first.startswith("."):
                    return False
        elif any(below(candidate, r) for r in BROWSE_EXCLUDED):
            return False
        if any(below(candidate, Path(p)) for p in ("/mnt", "/media", "/Volumes", "/proc", "/dev", "/run")):
            return False
        if not mounted_readable(candidate, home, mounts, recursive):
            return False
    return True


def persistent_write(path: Path, home: Path, mounts) -> bool:
    """Eligibility only: never create, repair, clean up or enumerate user work.

    Inspect the real root and every traversed component before normalizing '..'.
    HOME may have a lexical alias; Projects/eyrie/scrape and its contents may not.
    Metadata checks are not a transaction against concurrent same-user writers.
    """
    homes = home_paths(home)
    real_home = resolve_target(home)
    root = real_home / "Projects/eyrie/scrape"
    lexical_roots = {h / "Projects/eyrie/scrape" for h in homes}
    containing = [r for r in lexical_roots if below(path, r)]
    resolved = resolve_target(path)
    if not containing or not below(resolved, root) or resolved == root:
        return False
    if not mounted_readable(root, home, mounts) or not mounted_readable(resolved, home, mounts):
        return False
    try:
        for ancestor in (*reversed(real_home.parents), real_home):
            info = ancestor.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid not in {0, os.getuid()}:
                return False
            if info.st_mode & 0o022 and not (ancestor != real_home and info.st_mode & stat.S_ISVTX):
                return False
        for directory in (real_home, real_home / "Projects", real_home / "Projects/eyrie", root):
            info = directory.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
                return False
        relative = path.relative_to(max(containing, key=lambda p: len(p.parts)))
        current = root
        for index, part in enumerate(relative.parts):
            current /= part
            if not below(resolve_target(current), root):
                return False
            try:
                info = current.lstat()
            except FileNotFoundError:
                continue
            if info.st_uid != os.getuid() or info.st_mode & 0o022:
                return False
            if stat.S_ISDIR(info.st_mode) and index != len(relative.parts) - 1:
                continue
            if index != len(relative.parts) - 1 or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                return False
        return True
    except OSError:
        return False


def context(task_id: str) -> tuple[Path, Path]:
    from tools import file_tools
    if file_tools._terminal_env_type_for_task(task_id) != "local":
        raise ValueError("EyrAgents native path checks require the configured local backend")
    cwd = Path(file_tools._resolve_base_dir(task_id, container_paths=False))
    if not cwd.is_absolute() or not cwd.is_dir():
        raise ValueError("task cwd unavailable")
    return resolve_target(cwd), Path.home()


def prepare(tool_name: str, args: dict, cwd: Path, home: Path) -> tuple[dict, list[Path], bool]:
    """Return normalized args and all file subjects, including both move ends."""
    args = dict(args)
    if _ERROR in args:
        raise ValueError("request normalization failed")
    paths = []
    write = tool_name in {"write_file", "patch"}

    def operand(value):
        path = absolute(value, cwd)
        denial = path_denial(path, write, home)
        if denial:
            raise ValueError(denial)
        paths.append(path)
        return str(path)

    if tool_name == "patch" and args.get("mode") == "patch":
        from tools.patch_parser import parse_v4a_patch
        patch = args.get("patch")
        if not isinstance(patch, str):
            raise ValueError("missing patch")
        operations, error = parse_v4a_patch(patch)
        if error or not operations:
            raise ValueError("unsupported patch")
        # Validate the parser's actual operation set before changing headers.
        for operation in operations:
            operand(operation.file_path)
            if operation.new_path:
                operand(operation.new_path)
        lines = []
        for line in patch.split("\n"):
            move = MOVE.match(line)
            header = HEADER.match(line)
            if move:
                line = move[1] + operand(move[2].strip()) + " -> " + operand(move[3].strip())
            elif header:
                line = header[1] + operand(header[2].strip())
            lines.append(line)
        args["patch"] = "\n".join(lines)
    elif tool_name in FILE_TOOLS:
        args["path"] = operand(args.get("path", "." if tool_name == "search_files" else ""))
    return args, paths, write


def command_denial(command: str, cwd: Path, home: Path) -> str | None:
    if not isinstance(command, str) or not command.strip() or "\0" in command:
        return "invalid terminal command"
    gate = home / ".agents/hooks/commit-gate"
    info = gate.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        return "installed commit-gate endpoint is unsafe"
    payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}
    result = subprocess.run([str(gate)], input=json.dumps(payload), text=True,
                            capture_output=True, cwd=cwd, timeout=8, check=False)
    if result.returncode != 0:
        return "commit-gate refused the command; use the commit skill and H's exact approval"
    if result.stdout.strip():
        return "commit-gate returned an unexpected response"
    # Named consequential forms, not a parser or arbitrary-script containment.
    normalized = command.replace("\\\n", " ")
    normalized = re.sub(r"['\"\\]", "", normalized)
    if re.search(r"(?:^|[\s;&|()])(?:\S*/)?(?:sudo|doas|pkexec|su)(?:\s|$)", normalized):
        return "privilege escalation is H-run"
    if re.search(r"\bgit\s+(?:(?:-[Cc]\s+\S+|--\S+)\s+)*(?:push|clean)\b", normalized):
        return "raw push and clean are blocked; publication requires H's exact-approved publish-apply ID workflow"
    return None


def inspect(tool_name: str, args: dict, task_id="default") -> tuple[dict, dict | None]:
    if not _ready:
        return args, {"action": "block", "message": "EyrAgents plugin initialization is incomplete"}
    try:
        cwd, home = context(task_id or "default")
        normalized, paths, write = prepare(tool_name, args, cwd, home)
        if tool_name == "terminal":
            workdir = resolve_target(absolute(args.get("workdir") or str(cwd), cwd))
            if not workdir.is_dir():
                raise ValueError("terminal working directory must exist")
            normalized["workdir"] = str(workdir)
            denial = command_denial(args.get("command"), workdir, home)
            if denial:
                return normalized, {"action": "block", "message": denial}
        if tool_name == "skill_manage":
            from hermes_constants import get_hermes_home
            from tools.skill_manager_tool import _find_skill, _resolve_skill_dir
            name = args.get("name", "")
            if not isinstance(name, str) or not name or "/" in name or "\\" in name:
                raise ValueError("invalid skill name")
            if (home / ".agents/skills" / name).exists():
                raise ValueError("local learning must not shadow a shared skill")
            local_path = get_hermes_home() / "skills"
            local = resolve_target(local_path)
            if local_path.is_symlink() or local != resolve_target(get_hermes_home()) / "skills":
                raise ValueError("local learning root must not redirect into a shared library")
            if args.get("action") == "create":
                target = _resolve_skill_dir(args.get("name", ""), args.get("category"))
            else:
                entry = _find_skill(args.get("name", ""))
                target = Path(entry["path"]) if entry else local
            if not below(resolve_target(Path(target)), local):
                raise ValueError("shared/external skills are repository-owned; use an authorized source edit")
            if path_denial(Path(target), True, home):
                raise ValueError("protected learning target")
            # create/edit/default patch implicitly read or replace SKILL.md.
            # Checking only the directory misses a leaf symlink into shared
            # guidance or credential material followed by Hermes atomic writes.
            leaf = "SKILL.md" if args.get("action") in {"create", "edit"} else args.get("file_path") or "SKILL.md"
            attachment = absolute(leaf, Path(target))
            if not below(resolve_target(attachment), resolve_target(Path(target))) or path_denial(attachment, True, home):
                raise ValueError("protected skill attachment")
        root = workspace(cwd)
        mounts = mount_table() if paths else None
        homes = home_paths(home)
        scratch_roots = {h / "Projects/eyrie/scrape" for h in homes}
        external = []
        for path in paths:
            resolved = resolve_target(path)
            if write:
                scratch = any(below(p, r) for p in (path, resolved) for r in scratch_roots)
                allowed = persistent_write(path, home, mounts) if scratch else below(resolved, root)
            else:
                aggregate = any(p == Path("/") or p in homes for p in (path, resolved))
                allowed = not aggregate and ((root != Path("/") and below(resolved, root)) or
                          standing_read(path, home, mounts, tool_name == "search_files"))
            if not allowed:
                external.append(resolved)
        if external:
            subject = json.dumps([tool_name, sorted(str(p) for p in external)])
            return normalized, {"action": "approve", "message": "EyrAgents: confirm this external " +
                                ("write" if write else "read") + ": " + ", ".join(map(str, external)),
                                "rule_key": "eyragents:" + hashlib.sha256(subject.encode()).hexdigest()}
        return normalized, None
    except Exception:
        # Hook/middleware exceptions are fail-open upstream. Never raise here or
        # expose a command, patch body, credential-bearing value or parser error.
        return args, {"action": "block", "message": "EyrAgents: protected path/command or unverifiable tool input; check the access policy"}


def request(*, tool_name, args, task_id="default", **_):
    normalized, decision = inspect(tool_name, args, task_id)
    if decision and decision["action"] == "block":
        normalized = {**args, _ERROR: True}
    return {"args": normalized}


def pre_tool_call(*, tool_name, args, task_id="default", **_):
    return inspect(tool_name, args, task_id)[1]


def execute(*, tool_name, args, next_call, task_id="default", **_):
    normalized, decision = inspect(tool_name, args, task_id)
    if decision and decision["action"] == "block":
        return json.dumps({"error": decision["message"]})
    # The normal pre-hook owns native approval. This backstop prevents an
    # earlier plugin's approve directive from overriding our hard denials.
    return next_call(normalized)


def register(ctx):
    global _ready
    ctx.register_hook("pre_tool_call", pre_tool_call)
    ctx.register_middleware("tool_request", request)
    ctx.register_middleware("tool_execution", execute)
    try:
        from tools import file_tools
        original = file_tools.get_read_block_error
        original_search = file_tools._search_result_read_block_error

        def read_error(path):
            try:
                native = original(path)
                if native:
                    return native
                return path_denial(Path(path), False, Path.home())
            except Exception:
                return "EyrAgents: read target could not be checked"

        def search_error(path, task_id="default"):
            try:
                native = original_search(path, task_id)
                if native:
                    return native
                cwd, home = context(task_id)
                return path_denial(absolute(path, cwd), False, home)
            except Exception:
                return "EyrAgents: search target could not be checked"

        file_tools.get_read_block_error = read_error
        file_tools._search_result_read_block_error = search_error
        _ready = True
    except Exception:
        _ready = False
