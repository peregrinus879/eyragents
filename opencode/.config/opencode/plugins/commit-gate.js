// commit-gate plugin: run the installed copy of the same commit-gate hook
// Claude Code runs before every bash tool call, so no tool creates a
// commit except through commit-apply. There is no prefilter: the gate alone
// decides what counts, so quoting tricks on the word git cannot skip it. A
// denial throws, which OpenCode reports and does not execute; a missing gate
// also throws, so it fails closed.
import { spawnSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

export const CommitGate = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return
    const command = output.args?.command
    if (typeof command !== "string") return
    const payload = JSON.stringify({
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      tool_input: { command },
      cwd: output.args?.workdir ?? directory,
    })
    const gate = join(homedir(), ".agents/hooks/commit-gate")
    const result = spawnSync(gate, [], { input: payload, encoding: "utf8" })
    if (result.error) throw new Error(`commit-gate could not run: ${result.error.message}`)
    if (result.status !== 0) throw new Error((result.stderr || "").trim() || "commit-gate denied the command")
  },
})
