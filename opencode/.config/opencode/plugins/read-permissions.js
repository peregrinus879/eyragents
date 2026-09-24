// Adapt only native Read/Glob external-directory fallback asks, never location
// grants or shell/edit decisions. OpenCode 1.18.31 legacy plugin/SDK contract.
// Selected source rechecked 2026-09-15; docs/access.md owns evidence and limits.
// The managed config omits the redundant external '*' ask so an explicit
// project/agent restatement remains distinguishable and is never auto-approved.
// Trusted native tools/plugins are a prerequisite, not an isolation guarantee.
import { realpath, stat } from "node:fs/promises"
import { homedir } from "node:os"
import { dirname, isAbsolute, join, relative, resolve } from "node:path"
import { bounded, inside, safePath, protectedPath, protectedLayout, protectedTarget, resolveKnown, readMountLayout, classifiedMount } from "../lib/safety-paths.mjs"

const LIMIT = 256
const LIFETIME = 60_000
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value)
const id = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,200}$/.test(value)
const argumentKey = (value) => JSON.stringify(value, Object.keys(value).sort())
const AUDITOR_CAPS = Symbol.for("eyragents.auditor.original-caps")

function matches(subject, pattern) {
  if (pattern === "~" || pattern.startsWith("~/")) pattern = homedir() + pattern.slice(1)
  else if (pattern.startsWith("$HOME")) pattern = homedir() + pattern.slice(5)
  let expression = pattern.replaceAll("\\", "/").replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replaceAll("*", ".*").replaceAll("?", ".")
  if (expression.endsWith(" .*")) expression = expression.slice(0, -3) + "( .*)?"
  return new RegExp("^" + expression + "$", "s").test(subject.replaceAll("\\", "/"))
}

function rules(config) {
  if (config === undefined) return []
  if (typeof config === "string") config = { "*": config }
  if (!object(config)) throw new Error("unsupported policy")
  return Object.entries(config).flatMap(([permission, value]) => {
    if (typeof value === "string") value = { "*": value }
    if (!object(value)) throw new Error("unsupported policy")
    return Object.entries(value).map(([pattern, action]) => ({ permission, pattern, action }))
  })
}

function evaluate(permissions, permission, subject) {
  if (!Array.isArray(permissions) || permissions.some((rule) => !object(rule) ||
      typeof rule.permission !== "string" || typeof rule.pattern !== "string" ||
      !["allow", "ask", "deny"].includes(rule.action))) throw new Error("unsupported rules")
  return permissions.findLast((rule) => matches(permission, rule.permission) && matches(subject, rule.pattern))
}

function historyOrStore(path) {
  // These are additional no-adaptation cases, not replacements for native
  // credential denies. In particular, source files such as auth.py stay usable.
  return /\/(?:\.ssh|\.aws|\.gnupg|\.kube|\.mozilla|\.password-store|secrets)(?:\/|$)/i.test(path) ||
    /\/(?:\.env(?:\..*)?|\.envrc|\.netrc|\.npmrc|\.pypirc|auth\.json|credentials(?:\..*)?|\.credentials\.json|id_(?:rsa|dsa|ecdsa|ed25519)|\.bash_history|\.zsh_history)$/i.test(path) ||
    /\.(?:key|pem|p12|pfx)$/i.test(path) ||
    /\/(?:\.config\/(?:BraveSoftware|chromium|gh)|\.local\/share\/keyrings|\.docker)(?:\/|$)/i.test(path) ||
    /\/(?:shadow|gshadow|master\.passwd|\.claude\.json)$/i.test(path) ||
    /\/(?:\.claude\/(?:projects|sessions|session-env|tasks|debug|history\.jsonl)|\.codex\/(?:config\.toml|sessions|archived_sessions|history\.jsonl)|\.local\/share\/opencode)(?:\/|$)/i.test(path) ||
    /^\/(?:var\/)?tmp\/(?:claude-[^/]+|codex[^/]*)(?:\/|$)/.test(path)
}

export const ReadPermissions = async ({ client, directory, worktree }) => {
  const home = homedir()
  const layout = async (origins) => {
    origins ??= await bounded(protectedLayout(home))
    return { ...origins, mounts: await bounded(readMountLayout(origins.homes)) }
  }
  // Bind topology relevant to this call. A desktop overmount elsewhere must
  // not cancel a checked read; changes on its path/search subtree still do.
  const snapshot = (origins, paths, recursive) => JSON.stringify({ ...origins,
    mounts: origins.mounts.filter((mount) => paths.some((path) => inside(mount.point, path) || recursive && inside(path, mount.point))),
  })
  const ordinary = (path, layout, legacy = false, recursive = false) => {
    if (!safePath(path) || path === "/" || historyOrStore(path) || protectedTarget(path, layout) ||
        layout.stores.some((root) => inside(root, path)) || !classifiedMount(path, layout.mounts, recursive)) return false
    const excluded = ["/root", "/proc", "/dev", "/run", "/mnt", "/media"]
    if (excluded.some((root) => inside(root, path))) return false
    const own = layout.homes.find((root) => inside(root, path))
    if (own) {
      if (!/^\.[^/.][^/]*(?:\/|$)/.test(relative(own, path)) && !inside(join(own, "Projects"), path)) return false
    } else if (inside("/home", path)) return false
    if (recursive && [...layout.homes, ...excluded, "/home", ...layout.stores].some((root) => inside(path, root))) return false
    if (!legacy) return true
    return inside(home, path) && /^\.[^/.][^/]*(?:\/|$)/.test(relative(home, path)) ||
      layout.roots.some((root) => (!inside(home, path) || inside(home, root)) && inside(root, path))
  }
  const calls = new Map()
  let config
  let disposed = false
  const key = (session, call) => JSON.stringify([session, call])
  const remove = (key) => {
    calls.get(key)?.controller?.abort()
    calls.delete(key)
  }
  const prune = (reserve = false) => {
    for (const [key, value] of calls) if (value.expires <= Date.now()) remove(key)
    while (calls.size > LIMIT - Number(reserve)) remove(calls.keys().next().value)
  }
  const data = (result) => {
    if (!result || result.error || result.data === undefined) throw new Error("unavailable policy")
    return result.data
  }
  const agentRules = (name) => {
    const agent = config.agent?.[name]
    const provenance = agent?.[AUDITOR_CAPS]
    // The auditor emits inherited fallback rules. Use its original caps only
    // while the exact derived map is intact; later changes stay explicit.
    if (name === "auditor" && provenance?.map === agent.permission &&
        provenance?.external === agent.permission?.external_directory &&
        provenance?.derived === JSON.stringify(agent.permission)) return rules(JSON.parse(provenance.caps))
    return rules(agent?.permission)
  }
  const restricted = (policy, pattern) => ["ask", "deny"].includes(evaluate(policy, "external_directory", pattern)?.action)

  async function approve(request) {
    if (disposed || !config || request?.permission !== "external_directory" ||
        !id(request.id) || !id(request.sessionID) || !id(request.tool?.callID) || !id(request.tool?.messageID)) return
    prune()
    const callKey = key(request.sessionID, request.tool.callID)
    const call = calls.get(callKey)
    if (!call || call.used) return
    call.used = true // Claim once before the first await; malformed events fail closed.
    if (!object(request.metadata) || Object.keys(request.metadata).sort().join(",") !== "filepath,parentDir" ||
        request.metadata.filepath !== call.path || !Array.isArray(request.patterns) || request.patterns.length !== 1 ||
        !Array.isArray(request.always) || request.always.length !== 1 || request.always[0] !== request.patterns[0]) return
    const controller = new AbortController()
    call.controller = controller
    call.request = request.id
    const timeout = setTimeout(() => controller.abort(), 5_000)
    const current = () => !disposed && !controller.signal.aborted && calls.get(callKey) === call && call.expires > Date.now()
    try {
      const origins = await layout()
      const canonical = await realpath(call.path)
      const info = await stat(call.path)
      if (!current() || canonical !== call.canonical || snapshot(origins, [call.path, canonical], call.tool === "glob") !== call.layout ||
          !ordinary(call.path, origins, false, call.tool === "glob") || !ordinary(canonical, origins, false, call.tool === "glob") || (!info.isFile() && !info.isDirectory()) ||
          (call.tool === "glob" && !info.isDirectory())) return
      const parent = info.isDirectory() ? call.path : dirname(call.path)
      const pattern = join(parent, "*")
      if (request.metadata.parentDir !== parent || request.patterns[0] !== pattern) return
      // Any matching persisted/global/project external rule is intentional.
      // Only the native fallback, absent from merged config, is adaptable.
      if (restricted(rules(config.permission), pattern)) return
      const options = { query: { directory }, signal: controller.signal, throwOnError: true }
      const [session, message, agents] = await Promise.all([
        client.session.get({ ...options, path: { id: request.sessionID } }).then(data),
        client.session.message({ ...options, path: { id: request.sessionID, messageID: request.tool.messageID } }).then(data),
        client.app.agents(options).then(data),
      ])
      if (!current() || session.id !== request.sessionID || message.info?.id !== request.tool.messageID ||
          message.info?.sessionID !== request.sessionID || message.info?.role !== "assistant" ||
          !Array.isArray(agents) || !Array.isArray(message.parts)) return
      const part = message.parts.find((part) => part.type === "tool" && part.callID === request.tool.callID)
      if (!part || part.tool !== call.tool || part.state?.status !== "running" ||
          !object(part.state.input) || argumentKey(part.state.input) !== call.input) return
      const agent = agents.find((agent) => agent.name === message.info.agent)
      if (!agent || !Array.isArray(agent.permission)) return
      // The approved expansion is primary convenience, not reviewer widening.
      if (agent.name === "auditor" && [call.path, canonical].some((path) => !ordinary(path, origins, true, call.tool === "glob"))) return
      const sessionRules = session.permission ?? []
      const patterns = [pattern, join(info.isDirectory() ? canonical : dirname(canonical), "*")]
      const explicitRestriction = () => patterns.some((subject) =>
        restricted(rules(config.permission), subject) || restricted(agentRules(agent.name), subject) ||
        restricted(sessionRules, subject))
      if (explicitRestriction()) return
      const permissions = [...agent.permission, ...sessionRules]
      const external = evaluate(permissions, "external_directory", pattern)
      if (external?.action !== "ask" || external.pattern !== "*") return
      for (const target of [call.path, canonical]) {
        const subject = relative(worktree, target)
        const location = evaluate(permissions, "external_directory", join(info.isDirectory() ? target : dirname(target), "*"))
        if (evaluate(permissions, "read", subject)?.action !== "allow" || location?.action === "deny" ||
            (location?.action === "ask" && location.pattern !== "*")) return
      }
      if (call.tool === "glob" && evaluate(permissions, "glob", call.pattern)?.action !== "allow") return
      // Recheck mutable inputs after policy I/O. This is not a filesystem or
      // policy transaction; unknown changes keep the ordinary native prompt.
      if (snapshot(await layout(), [call.path, canonical], call.tool === "glob") !== call.layout || await realpath(call.path) !== canonical ||
          !current() || explicitRestriction()) return
      // Reply is a completion phase, not a cancellable policy lookup. Native
      // Permission.reply publishes Replied before resolving the waiting tool;
      // aborting this RPC from our Replied cleanup can strand that deferred.
      // Bound our wait, but let the exact once-reply finish after submission.
      clearTimeout(timeout)
      call.controller = undefined
      await bounded(client.postSessionIdPermissionsPermissionId({
        query: { directory },
        throwOnError: true,
        path: { id: request.sessionID, permissionID: request.id },
        body: { response: "once" },
      }))
    } catch {
      // No retry, reject fallback, source text, API response or credential dump.
      // A failed/late lookup or a human winning the race leaves native behavior.
    } finally {
      clearTimeout(timeout)
    }
  }

  return {
    config: async (cfg) => {
      config = undefined
      if (process.platform !== "linux" || !safePath(directory) || !safePath(worktree) ||
          !safePath(home) || home === "/" || await realpath(directory) !== directory ||
          await realpath(worktree) !== worktree || !object(cfg.permission)) return
      config = cfg
    },
    "tool.execute.before": async (input, output) => {
      if (disposed || !config || !["read", "glob"].includes(input.tool) ||
          !id(input.sessionID) || !id(input.callID) || !object(output.args)) return
      const callKey = key(input.sessionID, input.callID)
      const value = input.tool === "read" ? output.args.filePath : output.args.path ?? directory
      if (typeof value !== "string" || !value || (input.tool === "glob" && typeof output.args.pattern !== "string")) return
      const path = isAbsolute(value) ? value : resolve(directory, value)
      // Hard material veto also runs when native workspace/location rules would
      // not ask. Old no-adaptation categories keep their native handling.
      const refuse = () => { throw new Error("read-permissions: protected or unverifiable native file target") }
      if (protectedPath(path)) refuse()
      let canonical
      try { canonical = await bounded(realpath(path)) } catch (error) {
        if (error.code === "ENOENT") {
          // Keep native not-found handling only for an ordinary missing path,
          // not a dangling/looping link or inaccessible requested ancestor.
          await bounded(resolveKnown(path)).catch(refuse)
          return
        }
        refuse()
      }
      if (protectedPath(canonical)) refuse()
      let origins
      try { origins = await bounded(protectedLayout(home)) } catch { return }
      if (protectedTarget(path, origins) || protectedTarget(canonical, origins)) refuse()
      prune()
      if (calls.has(callKey)) { calls.get(callKey).used = true; calls.get(callKey).controller?.abort(); return }
      try { origins = await layout(origins) } catch { return }
      if (disposed || !config || !ordinary(path, origins, false, input.tool === "glob")) return
      if (calls.has(callKey)) { calls.get(callKey).used = true; calls.get(callKey).controller?.abort(); return }
      prune(true)
      calls.set(callKey, { tool: input.tool, path, canonical, pattern: output.args.pattern,
        input: argumentKey(output.args), layout: snapshot(origins, [path, canonical], input.tool === "glob"), expires: Date.now() + LIFETIME, used: false })
    },
    "tool.execute.after": async (input) => { remove(key(input.sessionID, input.callID)) },
    event: async ({ event }) => {
      // Legacy event hooks are fire-and-forget. Catch even shape/lookup errors.
      try {
        const value = event.properties
        if (event.type === "permission.asked") await approve(value)
        if (event.type === "permission.replied") {
          for (const [key, call] of calls) if (call.request === value.requestID) remove(key)
        }
        if (event.type === "message.part.updated" && value.part?.type === "tool" &&
            ["completed", "error"].includes(value.part.state?.status)) remove(key(value.part.sessionID, value.part.callID))
        if (event.type === "session.deleted") {
          for (const [callKey] of calls) if (JSON.parse(callKey)[0] === value.info?.id) remove(callKey)
        }
      } catch { /* Preserve native prompting on unsupported events. */ }
    },
    dispose: async () => {
      disposed = true
      for (const [key] of calls) remove(key)
    },
  }
}
