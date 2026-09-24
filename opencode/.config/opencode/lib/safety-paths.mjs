// Shared native-file preflight, not a filesystem sandbox or content classifier.
// Keep this helper outside plugins/: OpenCode autoloads every plugin export.
import { lstat, readFile, realpath } from "node:fs/promises"
import { basename, dirname, isAbsolute, join, normalize } from "node:path"

const SYSTEM_ROOT = "/"
const MOUNTINFO = "/proc/self/mountinfo"
const files = [
  "etc/shadow", "etc/shadow-", "etc/gshadow", "etc/gshadow-",
  "etc/security/opasswd", "etc/security/opasswd.old", "etc/krb5.keytab",
  "etc/ipsec.secrets", "var/lib/NetworkManager/secret_key", "var/lib/systemd/credential.secret",
  "proc/kcore", "proc/vmcore", "dev/mem", "dev/port",
]
const trees = [
  "etc/ssl/private", "etc/credstore", "etc/credstore.encrypted", "usr/lib/credstore",
  "usr/lib/credstore.encrypted", "etc/cryptsetup-keys.d", "etc/NetworkManager/system-connections",
  "usr/lib/NetworkManager/system-connections", "var/lib/iwd", "etc/wireguard", "etc/openvpn",
  "etc/ipsec.d/private", "etc/samba/private", "var/lib/samba/private", "etc/pacman.d/gnupg",
  "etc/letsencrypt", "var/lib/systemd/coredump", "var/crash", "sys/kernel/debug", "sys/kernel/tracing",
]
const homeTrees = [
  ".ssh", ".aws", ".gnupg", ".kube", ".mozilla", ".password-store",
  ".claude/projects", ".claude/sessions", ".claude/session-env", ".claude/tasks", ".claude/debug",
  ".codex/sessions", ".codex/archived_sessions",
  ".local/share/opencode/storage", ".local/share/opencode/log",
]
const homeFiles = [
  ".aws/credentials", ".aws/config", ".kube/config", ".ssh/id_rsa", ".ssh/id_dsa", ".ssh/id_ecdsa", ".ssh/id_ed25519",
  ".claude/.credentials.json", ".claude/history.jsonl", ".codex/config.toml", ".codex/auth.json",
  ".codex/history.jsonl", ".docker/config.json",
  ".env", ".envrc", ".netrc", ".npmrc", ".pypirc", ".bash_history", ".zsh_history",
]
const configStores = ["BraveSoftware", "chromium", "google-chrome", "1Password", "Bitwarden"]
const dataStores = ["keyrings", "opencode/storage", "opencode/log"]
const dataFiles = ["opencode/auth.json", "opencode/opencode.db", "opencode/opencode.db-wal", "opencode/opencode.db-shm"]

export async function bounded(promise) {
  let timer
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("native file metadata lookup timed out")), 5_000)
    })])
  } finally { clearTimeout(timer) }
}

export const inside = (root, path) => path === root || path.startsWith(root === "/" ? "/" : root + "/")
export const safePath = (path) => typeof path === "string" && isAbsolute(path) && normalize(path) === path &&
  !/[\\*?\x00-\x1f\x7f]/.test(path)

const suffix = (path, name) => path === "/" + name || path.endsWith("/" + name)
const tree = (path, name) => suffix(path, name) || path.includes("/" + name + "/")

export function protectedPath(path) {
  // Exact files and component-delimited trees also recognize ordinary copies.
  // No generic core/shadow name ban; public SSH host keys remain readable.
  return files.some((name) => suffix(path, name)) || trees.some((name) => tree(path, name)) ||
    homeTrees.some((name) => tree(path, name)) || homeFiles.some((name) => suffix(path, name)) ||
    configStores.some((name) => tree(path, ".config/" + name)) ||
    dataStores.some((name) => tree(path, ".local/share/" + name)) ||
    dataFiles.some((name) => suffix(path, ".local/share/" + name)) ||
    /\/(?:secrets|\.agents\/hooks)(?:\/|$)/.test(path) ||
    /\/(?:\.env(?:\.[^/]*)?|\.envrc|\.netrc|\.npmrc|\.pypirc|auth\.json|credentials(?:\.[^/]*)?|\.credentials\.json|id_(?:rsa|dsa|ecdsa|ed25519)|ssh_host_[^/]*_key)(?:\/|$)/.test(path) ||
    /\/(?:[^/]*\.(?:key|pem|p12|pfx|keytab))(?:\/|$)/.test(path) ||
    suffix(path, ".config/gh/hosts.yml") ||
    /^\/(?:var\/)?tmp\/(?:claude-[^/]+|codex[^/]*)(?:\/|$)/.test(path)
}

export async function resolveKnown(path) {
  try { return await realpath(path) } catch (error) {
    // A missing descendant can still have a symlinked existing ancestor.
    // Permission errors and loops are ambiguous, not evidence of a safe path.
    if (error.code !== "ENOENT" || path === "/") throw error
    const leaf = await lstat(path).catch((failure) => {
      if (failure.code !== "ENOENT") throw failure
    })
    if (leaf?.isSymbolicLink()) throw Object.assign(new Error("unresolved target link"), { code: "EUNRESOLVED" })
    return join(await resolveKnown(dirname(path)), basename(path))
  }
}

async function inventoryAlias(path) {
  try { return { path: await resolveKnown(path), incomplete: false } } catch (error) {
    // Inventory discovery is not a request to access a protected store. Keep
    // its literal exclusion and any accessible ancestor spelling without
    // requiring traversal permission on root-owned credential parents.
    // Outward aliases hidden behind an inaccessible/ambiguous component cannot
    // be discovered this way. Requested-target resolution remains strict.
    if (!["EACCES", "EPERM", "ELOOP", "ENOTDIR", "EUNRESOLVED"].includes(error.code) || path === "/") throw error
    const parent = await inventoryAlias(dirname(path))
    return { path: join(parent.path, basename(path)), incomplete: true }
  }
}

export async function protectedLayout(home) {
  const canonicalHome = await realpath(home)
  const config = process.env.XDG_CONFIG_HOME || join(home, ".config")
  const data = process.env.XDG_DATA_HOME || join(home, ".local/share")
  const cache = process.env.XDG_CACHE_HOME || join(home, ".cache")
  const state = process.env.XDG_STATE_HOME || join(home, ".local/state")
  const homes = [...new Set([home, canonicalHome])]
  const xdg = [config, data, cache, state]
  if (![...homes, ...xdg].every(safePath) || homes.includes("/") ||
      xdg.some((root) => root === "/" || homes.includes(root))) throw new Error("unsupported home/XDG layout")
  const discovered = await Promise.all(xdg.map(inventoryAlias))
  const canonical = discovered.map((alias) => alias.path)
  if (!canonical.every(safePath) || canonical.some((root) => root === "/" || homes.includes(root))) throw new Error("unsupported resolved XDG layout")
  const configs = [...new Set([...homes.map((root) => join(root, ".config")), config, canonical[0]])]
  const datas = [...new Set([...homes.map((root) => join(root, ".local/share")), data, canonical[1]])]
  const hardFiles = [...files.map((name) => join(SYSTEM_ROOT, name)),
    ...homes.flatMap((root) => homeFiles.map((name) => join(root, name))),
    ...configs.map((root) => join(root, "gh/hosts.yml")),
    ...datas.flatMap((root) => dataFiles.map((name) => join(root, name)))]
  const hardTrees = [...trees.map((name) => join(SYSTEM_ROOT, name)),
    ...homes.flatMap((root) => [...homeTrees, ".agents/hooks"].map((name) => join(root, name))),
    ...configs.flatMap((root) => configStores.map((name) => join(root, name))),
    ...datas.flatMap((root) => dataStores.map((name) => join(root, name)))]
  // These older, deliberately stricter categories refuse adaptation, not all
  // native access: Git config, tool output, learning memory, all XDG state, etc.
  const noAdapt = [...hardFiles, ...hardTrees, state, canonical[3],
    ...xdg.filter((_, index) => discovered[index].incomplete),
    ...canonical.filter((_, index) => discovered[index].incomplete),
    ...homes.flatMap((root) => [".local/state", ".docker", ".claude.json"].map((name) => join(root, name))),
    ...configs.flatMap((root) => ["gh", "git"].map((name) => join(root, name))),
    ...datas.map((root) => join(root, "opencode")),
  ]
  const aliases = async (paths) => [...new Set([...paths, ...await Promise.all(paths.map(async (path) => (await inventoryAlias(path)).path))])]
  const [protectedFiles, protectedTrees, stores] = await Promise.all([aliases(hardFiles), aliases(hardTrees), aliases(noAdapt)])
  if (![...protectedFiles, ...protectedTrees, ...stores].every((root) => safePath(root) && root !== "/")) throw new Error("unsupported protected layout")
  return { homes, protectedFiles, protectedTrees, stores,
    // Preserve the earlier positive scope for the auditor, including its
    // lexical-home distinction. Canonical-home support must not widen it.
    roots: [join(home, "Projects"), join(home, ".local/bin"),
      config, data, cache, ...canonical.slice(0, 3),
      "/tmp", "/var/tmp", "/usr", "/etc", "/opt", "/sys", "/var/lib/pacman"] }
}

export function protectedTarget(path, layout) {
  return protectedPath(path) || layout.protectedFiles.includes(path) || layout.protectedTrees.some((root) => inside(root, path))
}

export async function readMountLayout(homes) {
  const text = await readFile(MOUNTINFO, "utf8")
  if (!text.endsWith("\n") || Buffer.byteLength(text) > 1_048_576) throw new Error("unsupported mount metadata")
  const unescape = (value) => value.replace(/\\(040|011|012|134)/g, (_, octal) => String.fromCharCode(parseInt(octal, 8)))
  const mounts = text.trimEnd().split("\n").map((line) => {
    const fields = line.split(" ")
    const separator = fields.indexOf("-")
    if (fields.some((field) => !field) || separator < 6 || fields.length !== separator + 4 ||
        !/^[1-9]\d*$/.test(fields[0]) || !/^[1-9]\d*$/.test(fields[1]) || !/^\d+:\d+$/.test(fields[2]) ||
        !/^[a-zA-Z0-9_.-]+$/.test(fields[separator + 1])) throw new Error("unsupported mount record")
    const root = unescape(fields[3])
    const point = unescape(fields[4])
    if (!safePath(point)) throw new Error("unlocatable mount path")
    const unsupported = !safePath(root) || !fields.slice(6, separator)
      .every((field) => /^(?:(?:shared|master|propagate_from):[1-9]\d*|unbindable)$/.test(field))
    return { root, point, device: fields[2], type: fields[separator + 1], id: fields[0], parent: fields[1], unsupported }
  })
  const roots = mounts.filter((mount) => mount.point === "/")
  if (roots.length !== 1 || mounts.filter((mount) => mount.id === roots[0].id).length !== 1) throw new Error("ambiguous root mount")
  const system = new Set(["/", "/usr", "/usr/local", "/var", "/var/log", "/var/cache", "/var/lib", "/opt", "/boot", "/efi", "/home", ...homes])
  const subvolumes = { "/": "/@", "/home": "/@home", "/var/log": "/@log", "/var/cache": "/@cache", "/tmp": "/@tmp" }
  for (const mount of mounts) {
    // Overmounts are ordinary Linux topology. We do not infer a visible winner
    // or grant through ambiguous topology, but only its subtree is affected.
    const parents = mounts.filter((parent) => parent.id === mount.parent)
    const ambiguous = mount.unsupported || mounts.filter((other) => other.point === mount.point).length !== 1 ||
      mounts.filter((other) => other.id === mount.id).length !== 1 ||
      mount.point !== "/" && (parents.length !== 1 || parents[0] === mount || !inside(parents[0].point, mount.point))
    const local = ["ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs"].includes(mount.type)
    const subvolume = mount.type === "btrfs" && subvolumes[mount.point] === mount.root
    // A whole filesystem or subvolume can be bound from an unrelated user
    // mount into an otherwise supported system/home location. Compare the
    // device/root pair across the full table, not just pathname ancestors.
    // The unique actual / mount is the anchor: its mirrors lose eligibility,
    // not unrelated paths on /. Root ambiguity was rejected above.
    const duplicateRoot = mount.point !== "/" && mounts.some((other) => other !== mount &&
      other.device === mount.device && other.root === mount.root)
    mount.allowed = !ambiguous && !duplicateRoot && (
      local && (mount.root === "/" || subvolume) && (system.has(mount.point) || mount.point === "/tmp" || mount.point === "/var/tmp") ||
      mount.type === "tmpfs" && mount.root === "/" && ["/tmp", "/var/tmp"].includes(mount.point) ||
      ["vfat", "fat"].includes(mount.type) && mount.root === "/" && ["/boot", "/efi", "/boot/efi"].includes(mount.point) ||
      mount.type === "sysfs" && mount.root === "/" && mount.point === "/sys")
  }
  return mounts
}

export const classifiedMount = (path, mounts, recursive = false) => mounts.filter((mount) =>
  inside(mount.point, path) || recursive && inside(path, mount.point)).every((mount) => mount.allowed)
