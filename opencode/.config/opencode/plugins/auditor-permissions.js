// Intersect the managed auditor with the final merged parent policy, never a
// copy of stock grants. OpenCode b578b726 appends agent rules after the parent.
// The reserved agent-only ** deny is a bootstrap guard; ordinary * and named
// agent rules remain caps. Empty stock slots keep those caps before the guard
// when this plugin is absent. Later hostile plugins can still redefine config.
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"

const rank = { allow: 0, ask: 1, deny: 2 }
const stricter = (left, right) => rank[left] >= rank[right] ? left : right
const put = (rules, key, value) => { rules.delete(key); rules.set(key, value) }

function matches(tool, pattern) {
  let expression = pattern.replaceAll("\\", "/").replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replaceAll("*", ".*").replaceAll("?", ".")
  if (expression.endsWith(" .*")) expression = expression.slice(0, -3) + "( .*)?"
  return new RegExp("^" + expression + "$", process.platform === "win32" ? "si" : "s").test(tool)
}

function flatten(permission, tool, fallback, inherited = []) {
  const rules = new Map([["*", fallback], ...inherited])
  const config = typeof permission === "string" ? { "*": permission } : permission
  if (!config || typeof config !== "object" || Array.isArray(config)) throw new Error("invalid policy")
  for (const [name, value] of Object.entries(config)) {
    if (!matches(tool, name)) continue
    const patterns = typeof value === "string" ? { "*": value } : value
    if (!patterns || typeof patterns !== "object" || Array.isArray(patterns)) throw new Error("invalid rules")
    for (let [pattern, decision] of Object.entries(patterns)) {
      // Re-emission must not change numeric property ordering or turn a
      // backslash spelling into a newly expanded home path in fromConfig.
      if (!Object.hasOwn(rank, decision) || /\\|^\d+$/.test(pattern)) throw new Error("unsupported rule")
      if (pattern === "~" || pattern.startsWith("~/")) pattern = homedir() + pattern.slice(1)
      else if (pattern.startsWith("$HOME")) pattern = homedir() + pattern.slice(5)
      if (/^\*+$/.test(pattern)) { rules.clear(); pattern = "*" }
      put(rules, pattern, decision)
    }
  }
  return rules
}

function intersect(parent, cap) {
  const floor = cap.get("*")
  const constrained = [...cap].slice(1)
  while (constrained[0]?.[1] === floor) constrained.shift()
  cap = new Map([["*", floor], ...constrained])
  const parentConstraints = [...parent].slice(1)
  if (parentConstraints.every(([, value]) => value === "deny")) {
    const result = new Map([...cap].map(([key, value]) => [key, stricter(parent.get("*"), value)]))
    for (const [key, value] of parentConstraints) put(result, key, value)
    return result
  }
  const result = new Map([...parent].map(([key, value]) => [key, stricter(value, floor)]))
  if (constrained.every(([, value]) => value === "deny")) {
    for (const [key, value] of constrained) put(result, key, value)
    return result
  }
  const denyTail = (rules) => {
    let denied = false
    for (const value of rules.values()) {
      if (value === "deny") denied = true
      else if (denied) return false
    }
    return true
  }
  if (floor !== "deny" && constrained.every(([, value]) => value !== "allow") && denyTail(parent) && denyTail(cap)) {
    for (const [key, value] of constrained) put(result, key, value)
    // An ask cap must not reopen a parent's deny. This replay is exact only
    // when neither policy has a later exception to its deny tail.
    for (const [key, value] of parent) if (value === "deny") put(result, key, value)
    return result
  }
  throw new Error("unrepresentable intersection")
}

export const AuditorPermissions = async () => {
  let configured
  return {
    config: async (cfg) => {
      const auditor = cfg.agent?.auditor
      if (!auditor || auditor.disable || auditor === configured) return
      const original = auditor.permission
      auditor.permission = { "**": "deny" }
      try {
        let caps
        if (typeof original === "string") caps = { "*": original }
        else {
          if (!original || original["**"] !== "deny") throw new Error("missing bootstrap guard")
          caps = Object.fromEntries(Object.entries(original).filter(([key]) => key !== "**"))
        }
        const data = process.env.XDG_DATA_HOME || join(homedir(), ".local/share")
        if (!isAbsolute(data) || /[\\*?\x00-\x1f\x7f]/.test(data)) throw new Error("unsupported data path")
        const truncation = join(data, "opencode/tool-output/*")
        const next = { "**": "deny" }
        for (const tool of ["read", "glob", "external_directory"]) {
          let rules
          try {
            // Native external fallback is ask. A present external map can
            // omit that redundant leaf so explicit project asks stay visible
            // to the read adapter. A wholly missing policy remains denied.
            const fallback = tool === "glob" ? "allow" :
              tool === "external_directory" && cfg.permission?.external_directory ? "ask" : "deny"
            // Native agent defaults include this location before user rules.
            // Seed it before flattening so an explicit catch-all or narrower
            // rule can override it, even when the redundant * ask is omitted.
            const inherited = tool === "external_directory" && cfg.permission?.external_directory ? [[truncation, "allow"]] : []
            rules = intersect(flatten(cfg.permission ?? {}, tool, fallback, inherited), flatten(caps, tool, "allow"))
          } catch {
            rules = new Map([["*", "deny"]])
            console.warn(`auditor-permissions: ${tool} restricted to deny; unsupported policy intersection`)
          }
          if (tool === "read") put(rules, "mcp:*", "deny")
          if (tool === "external_directory") {
            // agent.ts otherwise appends a tool-output allow AFTER our policy.
            // Keep its exact deny sentinel before a complete derived policy;
            // a following * rule restores the parent's actual decision.
            let alternate = truncation + "*"
            while (rules.has(alternate)) alternate += "*"
            next[tool] = Object.fromEntries([[truncation, "deny"], ...[...rules].map(([key, value]) => [key === truncation ? alternate : key, value])])
          } else next[tool] = Object.fromEntries(rules)
        }
        // Non-enumerable runtime provenance for the read-only adapter. It may
        // distinguish inherited defaults from explicit caps only while this
        // exact derived map is intact; it grants no additional capability.
        Object.defineProperty(auditor, Symbol.for("eyragents.auditor.original-caps"), {
          value: Object.freeze({ caps: JSON.stringify(caps), derived: JSON.stringify(next),
            map: next, external: next.external_directory }), configurable: true,
        })
        auditor.permission = next
        configured = auditor
      } catch {
        throw new Error("auditor-permissions: derivation failed; auditor remains denied")
      }
    },
  }
}
