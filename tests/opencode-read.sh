#!/usr/bin/env bash
# Real adapter with synthetic native requests, SDK and filesystem subjects.
# No host configuration, provider calls, or live permission replies.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
umask 077
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home/.config/demo" "$TMP/work" "$TMP/data" "$TMP/cache"
env -i PATH="$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" \
  XDG_DATA_HOME="$TMP/data" XDG_CACHE_HOME="$TMP/cache" TMPDIR="$TMP" HISTFILE=/dev/null \
  node --input-type=module - "$ROOT" "$TMP" <<'JS'
import assert from "node:assert/strict"
import { mkdir, readFile, symlink, writeFile, unlink, rename } from "node:fs/promises"
import filesystem from "node:fs/promises"
import { syncBuiltinESMExports } from "node:module"
import { dirname, join, relative } from "node:path"
import { pathToFileURL } from "node:url"

const [repo, tmp] = process.argv.slice(2)
const home = process.env.HOME
const directory = join(tmp, "work")
const system = join(tmp, "system")
const mountFile = join(tmp, "mountinfo")
const ordinaryMounts = "10 1 8:1 / / rw - ext4 /dev/fixture rw\n"
// Deterministic OS metadata failures also run as root in disposable CI. Only
// this test process is instrumented; native file contents are never consulted.
const metadataFailures = new Map()
const actualRealpath = filesystem.realpath
filesystem.realpath = async (path) => {
  for (const [prefix, code] of metadataFailures) {
    if (String(path).startsWith(prefix)) throw Object.assign(new Error("fixture metadata failure"), { code })
  }
  return actualRealpath(path)
}
syncBuiltinESMExports()
await mkdir(join(tmp, "plugins"))
await mkdir(join(tmp, "lib"))
await mkdir(system)
await writeFile(mountFile, ordinaryMounts)
const helper = await readFile(join(repo, "opencode/.config/opencode/lib/safety-paths.mjs"), "utf8")
// Only the disposable module relocates metadata subjects. No host mount table
// or protected system/home store is inspected by these fixtures.
for (const anchor of ['const SYSTEM_ROOT = "/"', 'const MOUNTINFO = "/proc/self/mountinfo"']) assert.equal(helper.split(anchor).length, 2)
await writeFile(join(tmp, "lib/safety-paths.mjs"), helper
  .replace('const SYSTEM_ROOT = "/"', `const SYSTEM_ROOT = ${JSON.stringify(system)}`)
  .replace('const MOUNTINFO = "/proc/self/mountinfo"', `const MOUNTINFO = ${JSON.stringify(mountFile)}`)
  // A private temp fixture can model new system scope only when its containing
  // /tmp is not itself in the fixture's earlier auto-read inventory.
  .replace('"/tmp", "/var/tmp", "/usr"', '"/legacy-temp", "/legacy-var-temp", "/usr"'))
const { protectedPath, protectedLayout, protectedTarget, resolveKnown, readMountLayout, classifiedMount } = await import(pathToFileURL(join(tmp, "lib/safety-paths.mjs")))
const source = await readFile(join(repo, "opencode/.config/opencode/plugins/read-permissions.js"), "utf8")
await writeFile(join(tmp, "plugins/read.mjs"), source)
const { ReadPermissions } = await import(pathToFileURL(join(tmp, "plugins/read.mjs")))
await writeFile(join(tmp, "auditor.mjs"), await readFile(join(repo, "opencode/.config/opencode/plugins/auditor-permissions.js"), "utf8"))
const { AuditorPermissions } = await import(pathToFileURL(join(tmp, "auditor.mjs")))
const base = JSON.parse(await readFile(join(repo, "opencode/.config/opencode/opencode.json"), "utf8"))
assert.equal(Object.hasOwn(base.permission.external_directory, "*"), false, "fallback must retain native ownership")
// Fake HOME lives under private TMPDIR, possibly inside the managed scratch
// grant. Remove only that grant from fixtures to exercise actual fallback asks.
delete base.permission.external_directory["/tmp/opencode/*"]
const file = join(home, ".config/demo/settings.toml")
await writeFile(file, "ordinary configuration fixture\n")
let count = 0

function flatten(config) {
  if (!config) return []
  if (typeof config === "string") config = { "*": config }
  return Object.entries(config).flatMap(([permission, values]) =>
    Object.entries(typeof values === "string" ? { "*": values } : values)
      .map(([pattern, action]) => ({ permission, pattern, action })))
}
function native(config) {
  return [{ permission: "*", pattern: "*", action: "allow" },
    { permission: "external_directory", pattern: "*", action: "ask" }, ...flatten(config.permission)]
}
async function fixture(change = {}) {
  const config = structuredClone(base)
  change.config?.(config)
  await change.prepare?.(config)
  const args = change.args ?? { filePath: change.path ?? file }
  const input = { tool: change.tool ?? "read", sessionID: "ses_fixture", callID: "call_fixture" }
  const target = args.filePath ?? args.path ?? directory
  const parent = change.isDirectory || input.tool === "glob" ? target : dirname(target)
  const request = { id: "per_fixture", sessionID: input.sessionID, permission: "external_directory",
    patterns: [join(parent, "*")], always: [join(parent, "*")],
    metadata: { filepath: target, parentDir: parent }, tool: { messageID: "msg_fixture", callID: input.callID } }
  change.request?.(request)
  const session = { id: input.sessionID, permission: change.session ?? [] }
  const actor = change.actor ?? "build"
  const message = { info: { id: "msg_fixture", sessionID: input.sessionID, role: "assistant", agent: actor },
    parts: [{ type: "tool", callID: input.callID, tool: input.tool, state: { status: "running", input: structuredClone(args) } }] }
  change.message?.(message)
  const agents = [{ name: actor, permission: change.permissions ?? [...native(config), ...flatten(config.agent?.[actor]?.permission)] }]
  const replies = []
  const lookups = []
  let submitted
  const replySubmitted = new Promise((done) => { submitted = done })
  const response = async (name, value, opts) => {
    lookups.push(name)
    assert.equal(opts.query.directory, directory)
    assert.ok(opts.signal instanceof AbortSignal)
    if (change.failure === name) throw new Error("synthetic lookup failure")
    await change.wait?.(name)
    return { data: value }
  }
  const client = {
    session: {
      get: (opts) => response("session", session, opts),
      message: (opts) => response("message", message, opts),
    },
    app: { agents: (opts) => response("agents", agents, opts) },
    postSessionIdPermissionsPermissionId: async (opts) => {
      assert.equal(opts.path.id, "ses_fixture")
      assert.ok((change.requestIDs ?? [request.id]).includes(opts.path.permissionID))
      assert.deepEqual(opts.body, { response: "once" }, "never a session/location grant")
      assert.equal(opts.query.directory, directory)
      submitted()
      if (change.nativeReplyEvent) {
        // Native Permission.reply removes the pending request and publishes
        // Replied BEFORE resolving the tool's deferred permission. Cancelling
        // this RPC from that event can strand the tool after its card vanishes.
        await hooks.event({ event: { type: "permission.replied", properties: { requestID: request.id } } })
      }
      await change.replyWait?.()
      if (opts.signal?.aborted) throw new Error("synthetic native reply cancelled before resolving the tool")
      replies.push(opts)
    },
  }
  const hooks = await ReadPermissions({ client, directory, worktree: change.worktree ?? directory })
  const before = structuredClone(config)
  if (!change.noConfig) await hooks.config(config)
  assert.deepEqual(config, before, "adapter must not mutate tool or location policy")
  let blocked = false
  if (!change.noCall) {
    try { await hooks["tool.execute.before"](input, { args }) }
    catch (error) { assert.match(error.message, /read-permissions: protected/); blocked = true }
  }
  const event = () => hooks.event({ event: { type: "permission.asked", properties: request } })
  return { hooks, event, input, args, request, replies, lookups, config, replySubmitted, blocked }
}
async function check(accepted, change = {}) {
  const test = await fixture(change)
  if (change.hard !== undefined) assert.equal(test.blocked, change.hard, change.label ?? change.path)
  await change.before?.(test)
  await test.event()
  assert.equal(test.replies.length, accepted ? 1 : 0, change.label ?? JSON.stringify(change))
  await test.event()
  assert.equal(test.replies.length, accepted ? 1 : 0, "duplicate events cannot reply again")
  await test.hooks.dispose()
  count++
}

await check(true)
await check(true, { nativeReplyEvent: true, label: "native Replied event must not cancel approval completion" })
await check(true, { worktree: "/" })
await check(true, { args: { filePath: dirname(file) }, isDirectory: true })
await check(true, { tool: "glob", args: { pattern: "**/*.toml", path: dirname(file) }, isDirectory: true })
await check(true, { args: { filePath: file, limit: 10 }, message: (m) => { m.parts[0].state.input = { limit: 10, filePath: file } } })
for (const name of [".bashrc", ".profile", ".some-editor/preferences.conf", ".cargo/registry/source.rs",
                    ".local/share/mise/installs/opencode/9.9/lib/python3.13/site-packages/agent/auth.py",
                    ".local/share/nvim/lazy/plugin/lua/config.lua"]) {
  const path = join(home, name)
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, "ordinary fixture\n")
  await check(true, { path })
}
for (const name of [".env", ".npmrc", "auth.json", "private.key", ".ssh/config", ".claude/projects/session.jsonl",
                    ".codex/sessions/history.jsonl", ".codex/config.toml",
                    ".local/share/opencode/history", ".config/BraveSoftware/Profile/config"]) {
  const path = join(home, name)
  // Real fixture targets containing only synthetic non-secret text, so an
  // absent file cannot make a broken exclusion appear to work.
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, "synthetic non-secret policy fixture\n")
  await check(false, { path })
}
await symlink(file, join(home, ".config/demo/link.toml"))
await check(true, { path: join(home, ".config/demo/link.toml") })
await symlink(join(home, ".ssh/config"), join(home, ".config/demo/private-link.toml"))
await check(false, { path: join(home, ".config/demo/private-link.toml") })
const restrictedPath = join(home, "Projects/restricted/settings.toml")
await mkdir(dirname(restrictedPath), { recursive: true })
await writeFile(restrictedPath, "ordinary destination fixture\n")
const restrictedLink = join(home, ".config/demo/restricted-link.toml")
await symlink(restrictedPath, restrictedLink)
await check(true, { path: restrictedLink })
for (const action of ["ask", "deny"]) {
  const pattern = dirname(restrictedPath) + "/*"
  await check(false, { path: restrictedLink, config: (c) => { c.permission.external_directory[pattern] = action } })
  await check(false, { path: restrictedLink, config: (c) => { c.agent.build = { permission: { external_directory: { [pattern]: action } } } } })
  await check(false, { path: restrictedLink, session: [{ permission: "external_directory", pattern, action }] })
}
for (const [variable, names] of [
  ["XDG_CONFIG_HOME", ["demo/settings.toml", "gh/hosts.yml", "chromium/Default/Cookies", "BraveSoftware/Profile/config"]],
  ["XDG_DATA_HOME", ["nvim/lazy/plugin.lua", "opencode/history.json", "keyrings/login"]],
  ["XDG_CACHE_HOME", ["compiler/reference.txt"]],
]) {
  const original = process.env[variable]
  process.env[variable] = join(tmp, variable)
  try {
    for (const [index, name] of names.entries()) {
      const path = join(process.env[variable], name)
      await mkdir(dirname(path), { recursive: true })
      await writeFile(path, "synthetic non-secret XDG fixture\n")
      await check(index === 0, { path })
    }
  } finally { process.env[variable] = original }
}
for (const path of [restrictedPath, join(home, ".local/bin/example")]) {
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, "ordinary fixture\n")
  await check(true, { path })
}
const corpus = JSON.parse(await readFile(join(repo, "tests/safety-paths.json"), "utf8"))
const protectedNames = [...corpus.system_files, ...corpus.raw_files,
  ...[...corpus.system_trees, ...corpus.raw_trees].map((name) => name + "/ordinary.txt"),
  "service.keytab", ".keytab", ".key", ".pem", "etc/ssh/ssh_host_ed25519_key"]
for (const prefix of ["", "copy/deep/"]) {
  for (const name of protectedNames) {
    const path = join(system, prefix, name)
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, "synthetic protected-path fixture\n")
    assert.ok(protectedPath(path), name)
    await check(false, { path, hard: true })
  }
  for (const name of [...corpus.positive_files, "etc/ssh/ssh_host_ed25519_key.pub", "etc/shadow-policy",
    "etc/shadow-copy", "etc/credstore-other/ordinary.txt", "var/crashes/note", "sys/kernel/debugger/note", "proc/meminfo"]) {
    const path = join(system, prefix, name)
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, "ordinary positive fixture\n")
    assert.equal(protectedPath(path), false, name)
    await check(true, { path, hard: false })
  }
}
// New system eligibility belongs to the primary, not the existing auditor.
const newSystemFile = join(system, "srv/reference.txt")
await mkdir(dirname(newSystemFile), { recursive: true })
await writeFile(newSystemFile, "ordinary new system scope\n")
await check(true, { path: newSystemFile })
await check(false, { path: newSystemFile, actor: "auditor", prepare: async (c) => (await AuditorPermissions()).config(c), hard: false })
// Protected aliases are vetoed before native work, even if the native location
// policy already allows the call and therefore no approval event would occur.
const protectedAlias = join(home, ".config/demo/system-alias")
await symlink(join(system, "etc/shadow"), protectedAlias)
await check(false, { path: protectedAlias, hard: true })
const rawAlias = join(home, ".config/demo/raw-alias")
await symlink(join(system, "proc/kcore"), rawAlias)
await check(false, { path: rawAlias, hard: true })
const providerTarget = join(system, "provider-leaf")
await writeFile(providerTarget, "synthetic credential leaf alias\n")
await mkdir(join(home, ".aws"), { recursive: true })
await symlink(providerTarget, join(home, ".aws/config"))
await check(false, { path: providerTarget, hard: true })
const storeTarget = join(system, "innocent-store")
await mkdir(storeTarget)
await writeFile(join(storeTarget, "note"), "synthetic store alias\n")
await rename(join(system, "etc/ssl/private"), join(system, "etc/ssl/private-saved"))
await symlink(storeTarget, join(system, "etc/ssl/private"))
await check(false, { path: join(storeTarget, "note"), hard: true })
await unlink(join(system, "etc/ssl/private"))
await rename(join(system, "etc/ssl/private-saved"), join(system, "etc/ssl/private"))
// Real host regression: a root-owned credential parent need not be traversable
// to admit unrelated ordinary calls. Its known paths remain hard exclusions.
const privateParent = join(system, "var/lib/NetworkManager")
const privateLeaf = join(privateParent, "secret_key")
const unreadable = join(privateParent, "ordinary.txt")
await writeFile(unreadable, "synthetic unreadable-target fixture\n")
for (const code of ["EACCES", "EPERM", "ELOOP"]) {
  metadataFailures.set(privateParent + "/", code)
  try {
    const origins = await protectedLayout(home)
    assert.ok(protectedTarget(privateLeaf, origins), "inaccessible inventory keeps its literal deny")
    await check(true, { path: file, hard: false })
    await check(true, { path: newSystemFile, hard: false })
    await check(false, { path: newSystemFile, actor: "auditor", prepare: async (c) => (await AuditorPermissions()).config(c), hard: false })
    await check(false, { path: privateLeaf, hard: true })
    await check(false, { path: unreadable, hard: true })
    await check(false, { path: providerTarget, hard: true })
    await assert.rejects(resolveKnown(unreadable), (error) => error.code === code)
  } finally { metadataFailures.clear() }
}
// Accessible ancestors still contribute aliases when their descendants cannot
// be resolved. The metadata failure follows both spellings of the same parent.
const parentAlias = privateParent + "-actual"
await rename(privateParent, parentAlias)
await symlink(parentAlias, privateParent)
metadataFailures.set(privateParent + "/", "EACCES")
metadataFailures.set(parentAlias + "/", "EACCES")
try {
  assert.ok(protectedTarget(join(parentAlias, "secret_key"), await protectedLayout(home)))
  await check(true, { path: file, hard: false })
} finally {
  metadataFailures.clear()
  await unlink(privateParent)
  await rename(parentAlias, privateParent)
}
// Honest limit: an outward link hidden inside an inaccessible store cannot be
// discovered. The target here contains only benign synthetic text. Once the
// link's metadata is accessible, direct access through that spelling is vetoed.
const hiddenOutward = join(system, "hidden-outward-fixture")
await writeFile(hiddenOutward, "benign alias-discovery fixture\n")
await unlink(privateLeaf)
await symlink(hiddenOutward, privateLeaf)
metadataFailures.set(privateParent + "/", "EACCES")
try {
  assert.equal(protectedTarget(hiddenOutward, await protectedLayout(home)), false)
  await check(true, { path: file, hard: false })
} finally { metadataFailures.clear() }
await check(false, { path: hiddenOutward, hard: true })
await unlink(privateLeaf)
await writeFile(privateLeaf, "restored synthetic inventory fixture\n")
const dangling = join(home, ".config/demo/dangling")
await symlink(join(system, "missing-target"), dangling)
await check(false, { path: dangling, hard: true })
await check(false, { path: join(home, ".config/demo/missing-ordinary"), hard: false })
// Older no-adaptation distinctions are not elevated to hard material vetoes.
for (const name of [".config/git/settings", ".local/state/editor/note", ".local/share/opencode/tool-output/note", ".claude.json", ".docker/ordinary", ".config/demo/shadow"]) {
  const path = join(home, name)
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, "ordinary no-adaptation fixture\n")
  await check(false, { path, hard: false })
}
await check(false, { path: home, isDirectory: true, hard: false })
await check(false, { tool: "glob", args: { path: home, pattern: ".*" }, isDirectory: true, hard: false })
await check(false, { path: "/", isDirectory: true, hard: false })
await check(false, { tool: "glob", args: { path: "/", pattern: "**/*" }, isDirectory: true, hard: false })
const documents = join(home, "Documents/ordinary.txt")
await mkdir(dirname(documents), { recursive: true })
await writeFile(documents, "unrelated personal fixture\n")
await check(false, { path: documents, hard: false })
// A symlinked actual home must not expose non-dot documents at its other name.
const originalHome = process.env.HOME
const homeAlias = join(tmp, "home-alias")
await symlink(home, homeAlias)
process.env.HOME = homeAlias
try {
  await check(true, { path: file })
  await check(true, { path: join(homeAlias, ".config/demo/settings.toml") })
  await check(false, { path: documents, hard: false })
  await check(true, { path: restrictedPath })
  await check(false, { path: restrictedPath, actor: "auditor", prepare: async (c) => (await AuditorPermissions()).config(c), hard: false })
} finally { process.env.HOME = originalHome }

// Mount records are synthetic. Unknown filesystem types, arbitrary nested/bind
// mounts and ambiguous metadata never turn into an automatic grant.
for (const record of [
  `20 10 8:1 /somewhere ${system} rw - ext4 /dev/fixture rw\n`,
  `20 10 8:2 / ${system} rw - ext4 /dev/other rw\n`,
  `20 10 0:2 / ${system} rw - nfs server:/export rw\n`,
  `20 10 0:2 / ${system} rw - 9p drvfs rw\n`,
  `20 10 0:2 / ${system} rw - fuse.sshfs remote rw\n`,
]) {
  await writeFile(mountFile, ordinaryMounts + record)
  await check(false, { path: newSystemFile, hard: false })
  await check(true, { path: file, hard: false })
  await check(false, { tool: "glob", args: { path: tmp, pattern: "**/*.txt" }, isDirectory: true, hard: false })
}
// Known mountpoints localize topology uncertainty. Stacks, missing parents,
// duplicate IDs and unknown optional tags do not poison unrelated subtrees.
const stacked = "20 10 8:2 / /usr rw - ext4 /dev/fixture rw\n30 20 8:3 / /usr rw - ext4 /dev/other rw\n"
for (const records of [stacked,
  "20 999 8:2 / /usr rw - ext4 /dev/fixture rw\n",
  "20 10 8:2 / /usr rw - ext4 /dev/fixture rw\n20 10 8:3 / /var rw - ext4 /dev/other rw\n",
  "20 10 8:2 / /usr rw unknown:1 - ext4 /dev/fixture rw\n",
  "20 20 8:2 / /usr rw - ext4 /dev/fixture rw\n"]) {
  await writeFile(mountFile, ordinaryMounts + records)
  const topology = await readMountLayout([home])
  assert.equal(classifiedMount("/usr/share/ordinary", topology), false)
  await check(true, { path: file, hard: false })
  await check(true, { path: newSystemFile, hard: false })
  await check(false, { path: newSystemFile, actor: "auditor", prepare: async (c) => (await AuditorPermissions()).config(c), hard: false })
}
const affectedStack = `20 10 8:2 / ${dirname(newSystemFile)} rw - ext4 /dev/fixture rw\n30 20 8:3 / ${dirname(newSystemFile)} rw - ext4 /dev/other rw\n`
await writeFile(mountFile, ordinaryMounts + affectedStack)
await check(false, { path: newSystemFile, hard: false })
await check(true, { path: file, hard: false })
await check(false, { tool: "glob", args: { path: system, pattern: "**/*.txt" }, isDirectory: true, hard: false })
await writeFile(mountFile, ordinaryMounts)
await check(true, { path: file, before: () => writeFile(mountFile, ordinaryMounts + stacked) })
await writeFile(mountFile, ordinaryMounts)
await check(false, { path: newSystemFile, before: () => writeFile(mountFile, ordinaryMounts + affectedStack) })
for (const text of ["", "malformed\n", ordinaryMounts.trimEnd(), ordinaryMounts + ordinaryMounts,
  ordinaryMounts + "10 10 8:2 / /usr rw - ext4 /dev/fixture rw\n",
  ordinaryMounts + "20 10 8:2 / relative-path rw - ext4 /dev/fixture rw\n"]) {
  await writeFile(mountFile, text)
  await check(false, { path: file, hard: false })
  await check(false, { path: protectedAlias, hard: true })
}
await writeFile(mountFile, "10 1 8:1 /@ / rw - btrfs /dev/fixture rw\n20 10 8:1 /@home /home rw - btrfs /dev/fixture rw\n30 10 0:3 / /sys rw - sysfs sysfs rw\n")
const mounts = await readMountLayout([home])
assert.ok(classifiedMount("/sys/class/power_supply/BAT0/status", mounts))
assert.ok(classifiedMount("/home/fixture/Projects/example", mounts))
await check(true, { path: file })
// Whole-filesystem/subvolume aliases can appear at nonancestor mountpoints.
// The otherwise supported OS/home mount must not turn user storage into a new
// grant. Distinct roots on the same Btrfs device remain ordinary mounts.
for (const [filesystem, sourceRoot, destination, subject] of [
  ["ext4", "/", "/var/log", "/var/log/ordinary.txt"],
  ["btrfs", "/@log", "/var/log", "/var/log/ordinary.txt"],
  ["btrfs", "/@home", "/home", "/home/fixture/Projects/ordinary.txt"],
]) {
  const supported = `20 10 8:2 ${sourceRoot} ${destination} rw - ${filesystem} /dev/fixture rw\n`
  const alias = `30 10 8:2 ${sourceRoot} /media/disk rw - ${filesystem} /dev/fixture rw\n`
  await writeFile(mountFile, ordinaryMounts + supported)
  assert.equal(classifiedMount(subject, await readMountLayout([home])), true, "positive control: supported mount without alias")
  for (const rows of [supported + alias, alias + supported]) {
    await writeFile(mountFile, ordinaryMounts + rows)
    const topology = await readMountLayout([home])
    assert.equal(classifiedMount(subject, topology), false, "nonancestor device/root alias must withhold grants")
    assert.equal(classifiedMount(destination, topology, true), false)
    assert.equal(classifiedMount("/media/disk/ordinary.txt", topology), false)
    assert.equal(classifiedMount("/etc/os-release", topology), true, "unrelated subtree remains eligible")
    await check(true, { path: file, hard: false })
  }
}
const splitSubvolumes = "10 1 8:1 /@ / rw - btrfs /dev/fixture rw\n20 10 8:1 /@home /home rw - btrfs /dev/fixture rw\n30 10 8:1 /@log /var/log rw - btrfs /dev/fixture rw\n"
await writeFile(mountFile, splitSubvolumes)
const split = await readMountLayout([home])
assert.equal(classifiedMount("/home/fixture/Projects/ordinary.txt", split), true)
assert.equal(classifiedMount("/var/log/ordinary.txt", split), true)
// The unique actual root is the anchor, not an alias-derived grant. Mirroring
// it elsewhere withholds that other subtree, not every path on the machine.
await writeFile(mountFile, ordinaryMounts + "20 10 8:1 / /var/log rw - ext4 /dev/fixture rw\n30 10 8:1 / /media/root-copy rw - ext4 /dev/fixture rw\n")
const rootMirror = await readMountLayout([home])
assert.equal(classifiedMount("/", rootMirror), true)
assert.equal(classifiedMount("/etc/os-release", rootMirror), true)
assert.equal(classifiedMount("/var/log/ordinary.txt", rootMirror), false)
await check(true, { path: file, hard: false })
// Exercise the actual adapter at a supported, existing fixture-home mount,
// including drift after call capture. All file IO stays inside private TMPDIR.
const homeMount = `20 10 8:2 / ${home} rw - ext4 /dev/fixture rw\n`
const homeMirror = "30 10 8:2 / /media/disk rw - ext4 /dev/fixture rw\n"
await writeFile(mountFile, ordinaryMounts + homeMount)
await check(true, { path: file })
await check(false, { path: file, hard: false, before: () => writeFile(mountFile, ordinaryMounts + homeMount + homeMirror) })
await check(false, { path: file, hard: false })
await check(false, { tool: "glob", args: { path: dirname(file), pattern: "*.toml" }, isDirectory: true, hard: false })
await check(false, { path: file, actor: "auditor", prepare: async (c) => (await AuditorPermissions()).config(c), hard: false })
await check(true, { path: newSystemFile, hard: false })
await writeFile(mountFile, ordinaryMounts)
await check(false, { path: file, hard: false, before: () => writeFile(mountFile, "broken\n") })
await writeFile(mountFile, ordinaryMounts)
for (const [variable, protectedName] of [["XDG_CONFIG_HOME", "gh/hosts.yml"], ["XDG_DATA_HOME", "opencode/history.json"]]) {
  const original = process.env[variable]
  const real = join(tmp, variable + "-real")
  const alias = join(tmp, variable + "-alias")
  await mkdir(dirname(join(real, protectedName)), { recursive: true })
  await writeFile(join(real, protectedName), "synthetic non-secret protected fixture\n")
  await writeFile(join(real, "ordinary.txt"), "ordinary XDG alias fixture\n")
  await symlink(real, alias)
  process.env[variable] = alias
  try {
    await check(false, { path: join(real, protectedName) })
    await check(false, { path: join(alias, protectedName) })
    await check(true, { path: join(real, "ordinary.txt") })
    await check(true, { path: join(alias, "ordinary.txt") })
  } finally { process.env[variable] = original }
}
for (const [variable, store, leaf] of [
  ["XDG_CONFIG_HOME", "gh", "hosts.yml"], ["XDG_DATA_HOME", "opencode", "history.json"],
  ["XDG_DATA_HOME", "keyrings", "login"], ["HOME", ".ssh", "config"],
]) {
  const original = process.env[variable]
  const root = join(tmp, variable + "-store-" + store.replace(".", ""))
  const resolved = root + "-resolved"
  await mkdir(root, { recursive: true })
  await mkdir(resolved, { recursive: true })
  await writeFile(join(resolved, leaf), "synthetic non-secret linked-store fixture\n")
  await writeFile(join(root, "ordinary.txt"), "ordinary sibling fixture\n")
  await symlink(resolved, join(root, store))
  process.env[variable] = root
  try {
    await check(false, { path: join(resolved, leaf) })
    await check(false, { path: join(root, store, leaf) })
    if (variable !== "HOME") await check(true, { path: join(root, "ordinary.txt") })
  } finally { process.env[variable] = original }
}
const originalState = process.env.XDG_STATE_HOME
process.env.XDG_STATE_HOME = join(tmp, "relocated-state")
await mkdir(process.env.XDG_STATE_HOME)
await writeFile(join(process.env.XDG_STATE_HOME, "session.json"), "synthetic non-secret state fixture\n")
try { await check(false, { path: join(process.env.XDG_STATE_HOME, "session.json") }) }
finally {
  if (originalState === undefined) delete process.env.XDG_STATE_HOME
  else process.env.XDG_STATE_HOME = originalState
}

for (const tool of ["bash", "edit", "write", "apply_patch", "grep", "custom_read"]) await check(false, { tool })
await check(false, { noCall: true })
await check(false, { noConfig: true })
await check(false, { path: "/unapproved-location/ordinary.txt" })
await check(false, { path: join(home, "Documents/ordinary.txt") })
for (const permission of ["read", "glob", "edit", "bash"]) await check(false, { request: (r) => { r.permission = permission } })
for (const field of ["id", "sessionID", "tool", "metadata", "patterns", "always"]) await check(false, { request: (r) => { delete r[field] } })
for (const mutate of [
  (r) => { r.tool.callID = "other_call" }, (r) => { r.tool.messageID = "other_message" },
  (r) => { r.sessionID = "other_session" }, (r) => { r.patterns = [join(home, ".local/share/*")]; r.always = r.patterns },
  (r) => { r.patterns.push("/elsewhere/*") }, (r) => { r.always = ["*"] },
  (r) => { r.metadata.command = "synthetic command" }, (r) => { r.metadata.filepath = dirname(file) },
]) await check(false, { request: mutate })
for (const action of ["ask", "deny"]) {
  for (const permission of ["external_directory", "external_*", "*"]) {
    await check(false, { config: (c) => { c.permission[permission] = action } })
    await check(false, { config: (c) => { c.agent.build = { permission: { [permission]: action } } } })
    await check(false, { session: [{ permission, pattern: "*", action }] })
  }
  await check(false, { config: (c) => { c.permission.external_directory[dirname(file) + "/*"] = action } })
  await check(false, { permissions: [...native(base), { permission: "read", pattern: relative(directory, file), action }] })
  await check(false, { tool: "glob", args: { pattern: "**/*.toml", path: dirname(file) }, isDirectory: true,
    permissions: [...native(base), { permission: "glob", pattern: "**/*.toml", action }] })
}
const compose = async (config) => { await (await AuditorPermissions()).config(config) }
await check(true, { actor: "auditor", prepare: compose })
await check(true, { actor: "auditor", prepare: compose, tool: "glob", args: { pattern: "**/*.toml", path: dirname(file) }, isDirectory: true })
await check(false, { actor: "auditor", prepare: compose, config: (c) => { c.agent.auditor.permission.external_directory = "ask" } })
await check(false, { actor: "auditor", prepare: compose, before: (t) => { t.config.agent.auditor.permission.external_directory[dirname(file) + "/*"] = "ask" } })
await check(false, { actor: "auditor", prepare: compose, before: (t) => {
  t.config.agent.auditor.permission = structuredClone(t.config.agent.auditor.permission)
} })
await check(false, { actor: "auditor", prepare: compose, before: (t) => {
  const p = t.config.agent.auditor.permission
  p.external_directory = structuredClone(p.external_directory)
} })
await check(false, { permissions: "unsupported old SDK shape" })
for (const failure of ["session", "message", "agents"]) await check(false, { failure })
for (const mutate of [
  (m) => { m.info.agent = "unknown" }, (m) => { m.info.role = "user" }, (m) => { m.info.sessionID = "other_session" },
  (m) => { m.parts[0].tool = "write" }, (m) => { m.parts[0].state.status = "completed" },
  (m) => { m.parts[0].state.input.filePath = "/other/path" },
]) await check(false, { message: mutate })
await check(false, { before: (t) => t.hooks["tool.execute.after"](t.input) })
await check(false, { before: (t) => t.hooks.dispose() })
await check(false, { before: (t) => t.hooks["tool.execute.before"](t.input, { args: t.args }) })
await check(false, { before: async (t) => {
  await assert.rejects(t.hooks["tool.execute.before"](t.input, { args: { filePath: protectedAlias } }), /protected/)
  await t.hooks["tool.execute.after"](t.input)
} })
await check(false, { before: async (t) => {
  await t.hooks.event({ event: { type: "message.part.updated", properties: {
    part: { type: "tool", sessionID: t.input.sessionID, callID: t.input.callID, state: { status: "error" } },
  } } })
} })
const raced = await fixture()
await Promise.all([raced.event(), raced.event(), raced.event()])
assert.equal(raced.replies.length, 1, "concurrent duplicate events")
await raced.hooks.dispose()
count++
for (const cleanup of ["dispose", "tool.execute.after"]) {
  let finish
  const waiting = new Promise((done) => { finish = done })
  const test = await fixture({ replyWait: () => waiting })
  const pending = test.event()
  let deadline
  try {
    await Promise.race([test.replySubmitted, new Promise((_, reject) => {
      deadline = setTimeout(() => reject(new Error("fixture reply was not submitted")), 5_000)
    })])
    await test.hooks[cleanup](test.input)
    finish()
    await pending
    assert.equal(test.replies.length, 1, `submitted once-reply must finish through ${cleanup}`)
  } finally {
    clearTimeout(deadline)
    finish()
    await test.hooks.dispose()
  }
  count++
}
const concurrent = await fixture({ requestIDs: ["per_fixture", "per_second"], message: (m) => {
  m.parts.push({ ...structuredClone(m.parts[0]), callID: "call_second" })
} })
await concurrent.hooks["tool.execute.before"]({ ...concurrent.input, callID: "call_second" }, { args: concurrent.args })
const secondRequest = structuredClone(concurrent.request)
secondRequest.id = "per_second"
secondRequest.tool.callID = "call_second"
await Promise.all([concurrent.event(), concurrent.hooks.event({ event: { type: "permission.asked", properties: secondRequest } })])
assert.deepEqual(new Set(concurrent.replies.map((r) => r.path.permissionID)), new Set(["per_fixture", "per_second"]))
await concurrent.hooks.dispose()
count++
let release
const waited = new Promise((done) => { release = done })
const cancelled = await fixture({ wait: () => waited })
const pending = cancelled.event()
await new Promise((done) => setTimeout(done, 20))
await cancelled.hooks.dispose()
release()
await pending
assert.equal(cancelled.replies.length, 0, "disposal during policy lookup")
count++
for (const cancellation of ["permission.replied", "session.deleted", "message.part.updated", "capacity", "timeout"]) {
  let finish
  const waiting = new Promise((done) => { finish = done })
  const test = await fixture({ wait: () => waiting })
  const originalTimeout = globalThis.setTimeout
  if (cancellation === "timeout") globalThis.setTimeout = (fn, ms, ...args) => originalTimeout(fn, ms === 5_000 ? 5 : ms, ...args)
  const pending = test.event()
  await new Promise((done) => originalTimeout(done, 20))
  globalThis.setTimeout = originalTimeout
  if (cancellation === "capacity") {
    for (let i = 0; i < 256; i++) await test.hooks["tool.execute.before"]({ ...test.input, callID: `call_${i}` }, { args: test.args })
  } else if (cancellation !== "timeout") {
    const properties = cancellation === "permission.replied" ? { requestID: test.request.id } :
      cancellation === "session.deleted" ? { info: { id: test.input.sessionID } } :
      { part: { type: "tool", sessionID: test.input.sessionID, callID: test.input.callID, state: { status: "error" } } }
    await test.hooks.event({ event: { type: cancellation, properties } })
  }
  finish()
  await pending
  assert.equal(test.replies.length, 0, cancellation)
  await test.hooks.dispose()
  count++
}
const expired = await fixture()
const clock = Date.now
Date.now = () => clock() + 61_000
try { await expired.event() } finally { Date.now = clock }
assert.equal(expired.replies.length, 0, "stale calls expire")
await expired.hooks.dispose()
count++
console.log(`ok: read-only external approval adapter (${count} acceptance/refusal/lifecycle cases)`)
JS
