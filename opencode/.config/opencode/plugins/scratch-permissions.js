// Checked native edits for owned execution scratch and persistent project work.
// Source contract: OpenCode 1.18.31, config/permission and native file tools.
// Selected source rechecked 2026-09-15; docs/access.md owns evidence and limits.
// Preflight rejects existing link escapes; it cannot prevent a subsequent
// filesystem race or identify which session owns a child of the managed root.
// Merged config has no provenance for a project restating a default unchanged.
import { lstat, realpath } from "node:fs/promises"
import { homedir, tmpdir } from "node:os"
import { isAbsolute, join, normalize, relative } from "node:path"
import { bounded, inside, safePath, protectedPath, protectedLayout, protectedTarget, resolveKnown, readMountLayout, classifiedMount } from "../lib/safety-paths.mjs"

const SCRATCH_ROOT = "/tmp/opencode"

function matches(subject, pattern) {
  if (pattern === "~" || pattern.startsWith("~/")) pattern = homedir() + pattern.slice(1)
  else if (pattern.startsWith("$HOME")) pattern = homedir() + pattern.slice(5)
  let expression = pattern.replaceAll("\\", "/").replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replaceAll("*", ".*").replaceAll("?", ".")
  if (expression.endsWith(" .*")) expression = expression.slice(0, -3) + "( .*)?"
  return new RegExp("^" + expression + "$", "s").test(subject.replaceAll("\\", "/"))
}

function action(permissions, tool, subject) {
  let result = "ask"
  for (const [name, value] of Object.entries(permissions)) {
    if (!matches(tool, name)) continue
    for (const [pattern, decision] of Object.entries(typeof value === "string" ? { "*": value } : value)) {
      if (matches(subject, pattern)) result = decision
    }
  }
  return result
}

export const ScratchPermissions = async ({ directory, worktree }) => {
  let guard
  let config
  const home = homedir()
  const refuse = () => { throw new Error("scratch-permissions: protected, unsafe or ambiguous native file target") }

  const subjects = (input, args) => {
    let paths = []
    let move = false
    if (input.tool === "apply_patch") {
      if (typeof args?.patchText !== "string") return { paths, move }
      // Over-approximate native headers, including heredoc/CRLF wrappers.
      for (const line of args.patchText.trim().split("\n")) {
        const header = /^\*\*\* (Add File|Update File|Delete File|Move to):(.*)$/s.exec(line.replace(/\r$/, ""))
        if (!header) continue
        move ||= header[1] === "Move to"
        const operand = header[2].trim()
        if (operand) paths.push(isAbsolute(operand) ? normalize(operand) : join(directory, operand))
      }
    } else if (typeof args?.filePath === "string") {
      // Native Edit/Write preserve absolute spellings, including link/.. .
      paths = [isAbsolute(args.filePath) ? args.filePath : join(directory, args.filePath)]
    }
    return { paths, move }
  }

  const protectedWrite = (path) => protectedPath(path) || /(?:^|\/)\.git(?:\/|$)/.test(path)

  return {
    config: async (cfg) => {
      config = cfg
      if (guard || process.platform !== "linux") return
      const rules = cfg.permission?.edit
      if (!rules || typeof rules !== "object" || Array.isArray(rules)) return
      const read = cfg.permission.read
      if (!read || typeof read !== "object" || Array.isArray(read) || read["*"] !== "allow" ||
          Object.entries(read).some(([pattern, decision]) => pattern !== "*" && decision !== "deny")) return
      const entries = Object.entries(rules)
      if (entries[0]?.[0] !== "*" || entries[0]?.[1] !== "allow" ||
          entries[1]?.[0] !== "../*" || entries[1]?.[1] !== "ask") return
      if (![directory, worktree, home].every(safePath) || home === "/" || !inside(worktree, directory)) return

      let origins, mounts
      try {
        origins = await bounded(protectedLayout(home))
        mounts = await bounded(readMountLayout(origins.homes))
        if (await realpath(worktree) !== worktree ||
            await realpath(directory) !== directory) return
      } catch {
        return // Unsupported layout receives no new grant.
      }
      const roots = []
      // Persistent authority is independent of TMPDIR and creates no root,
      // ownership change, disposal entitlement or cleanup operation.
      for (const path of [join(home, "Projects/eyrie/scrape"), ...(join(tmpdir(), "opencode") === SCRATCH_ROOT ? [SCRATCH_ROOT] : [])]) {
        try {
          if (!classifiedMount(path, mounts)) continue
          const metadata = await bounded(lstat(path))
          if (metadata.isDirectory() && metadata.uid === process.getuid() && !(metadata.mode & 0o022) &&
              await bounded(realpath(path)) === path && !protectedTarget(path, origins)) roots.push({ path, metadata })
        } catch { /* A missing/unsafe root cannot acquire an allowance. */ }
      }
      if (!roots.length) return

      const additions = []
      const enclosing = roots.filter((root) => root.path !== worktree && inside(root.path, worktree))
        .sort((a, b) => a.path.length - b.path.length)[0]
      if (enclosing) {
        const depth = relative(enclosing.path, worktree).split("/").length
        additions.push(["../**", "allow"], ["../".repeat(depth + 1) + "*", "ask"])
      }
      // Put the other root's explicit allow after the ancestor boundary ask.
      // All inherited restrictions still follow this bounded union.
      for (const root of roots) {
        if (!inside(worktree, root.path) && !inside(root.path, worktree)) additions.push([relative(worktree, root.path) + "/*", "allow"])
      }
      if (additions.some(([pattern]) => Object.hasOwn(rules, pattern))) return

      const next = Object.fromEntries([...entries.slice(0, 2), ...additions, ...entries.slice(2)])
      const added = { edit: Object.fromEntries(additions) }
      const before = async (paths, move, verifiedLayout) => {
        paths = paths.filter((path) => roots.some((root) => inside(root.path, normalize(path))) ||
          action(added, "edit", relative(worktree, path)) === "allow")
        if (!paths.length) return
        if (!verifiedLayout) refuse()
        if (move) throw new Error("scratch-permissions: use Add File and Delete File instead of Move to so both endpoints receive native permission checks")

        const currentMounts = await readMountLayout(origins.homes).catch(refuse)
        for (const path of paths) {
          const root = roots.filter((root) => inside(root.path, path)).sort((a, b) => b.path.length - a.path.length)[0]
          if (!root || path === root.path || normalize(path) !== path ||
              /[\\\x00-\x1f\x7f]/.test(path)) refuse()
          const current = await lstat(root.path).catch(refuse)
          if (!current.isDirectory() || current.uid !== process.getuid() || current.mode & 0o022 ||
              current.dev !== root.metadata.dev || current.ino !== root.metadata.ino ||
              await realpath(root.path) !== root.path || !classifiedMount(path, currentMounts)) refuse()
          const subject = relative(worktree, path)
          const parent = path.slice(0, path.lastIndexOf("/"))
          if (action(cfg.permission, "read", subject) === "deny" || action(cfg.permission, "edit", subject) === "deny" ||
              action(cfg.permission, "external_directory", parent + "/*") === "deny") refuse()

          const parts = relative(root.path, path).split("/")
          let existing = root.path
          for (let index = 0; index < parts.length; index++) {
            const target = join(existing, parts[index])
            let metadata
            try { metadata = await lstat(target) } catch (error) {
              if (error.code === "ENOENT") break
              refuse()
            }
            if (metadata.isSymbolicLink() || metadata.uid !== process.getuid() || metadata.mode & 0o022 ||
                (index < parts.length - 1 ? !metadata.isDirectory() : !metadata.isFile() || metadata.nlink !== 1)) refuse()
            existing = target
          }
          if (await realpath(existing).catch(refuse) !== existing) refuse()
        }
      }

      // OpenCode ignores config-hook failures. The deny guard must exist before
      // the only mutation, which preserves the order of all existing rules.
      guard = before
      cfg.permission.edit = next
    },
    "tool.execute.before": async (input, output) => {
      if (!config || !["edit", "write", "apply_patch"].includes(input.tool)) return
      const { paths, move } = subjects(input, output.args)
      // Material checks precede native source reads, including Apply Patch's
      // diff construction before its edit ask and both Move-to endpoints.
      const canonical = []
      for (const path of paths) {
        if (protectedWrite(path)) refuse()
        const target = await bounded(resolveKnown(path)).catch(refuse)
        if (protectedWrite(target)) refuse()
        canonical.push(target)
      }
      const origins = await bounded(protectedLayout(home)).catch(() => undefined)
      if (origins && [...paths, ...canonical].some((path) => protectedTarget(path, origins))) refuse()
      if (guard) {
        await bounded(guard(paths, move, origins)).catch(refuse)
      }
    },
  }
}
