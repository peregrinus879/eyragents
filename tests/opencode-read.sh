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
import { mkdir, readFile, symlink, writeFile } from "node:fs/promises"
import { dirname, join, relative } from "node:path"
import { pathToFileURL } from "node:url"

const [repo, tmp] = process.argv.slice(2)
const home = process.env.HOME
const directory = join(tmp, "work")
const source = await readFile(join(repo, "opencode/.config/opencode/plugins/read-permissions.js"), "utf8")
await writeFile(join(tmp, "read.mjs"), source)
const { ReadPermissions } = await import(pathToFileURL(join(tmp, "read.mjs")))
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
  if (!change.noCall) await hooks["tool.execute.before"](input, { args })
  const event = () => hooks.event({ event: { type: "permission.asked", properties: request } })
  return { hooks, event, input, args, request, replies, lookups, config, replySubmitted }
}
async function check(accepted, change = {}) {
  const test = await fixture(change)
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
                    ".local/share/mise/installs/pipx-hermes-agent/9.9/hermes-agent/lib/python3.13/site-packages/agent/auth.py",
                    ".local/share/nvim/lazy/plugin/lua/config.lua"]) {
  const path = join(home, name)
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, "ordinary fixture\n")
  await check(true, { path })
}
for (const name of [".env", ".npmrc", "auth.json", "private.key", ".ssh/config", ".claude/projects/session.jsonl",
                    ".codex/sessions/history.jsonl", ".codex/config.toml", ".hermes/config.yaml",
                    ".hermes/logs/latest.log", ".local/share/opencode/history", ".config/BraveSoftware/Profile/config"]) {
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
