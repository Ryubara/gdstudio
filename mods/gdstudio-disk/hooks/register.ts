import type { Register } from 'claude-code'

// The GDStudio disk guard in the status line (docs/hooks.md#disk). The kit's hooks run `gds disk guard` in the
// background, at most every five minutes while any agent works, and it writes <workspace>/cache/disk-guard.json; this
// mod shows that file's line, and a toast once when the disk falls under the hard limit (no new agent or worktree
// starts then). It reads one small file a minute and runs nothing.

const MARKER = '.gdstudio-workspace'
const STATUS = 'cache/disk-guard.json'
const EVERY_MS = 60_000

type Status = { line?: string; level?: string; checked?: string; free_gb?: number; hard_gb?: number }

/** The folder holding `.gdstudio-workspace`, walking up from `cwd`; undefined outside a workspace. */
export async function findWorkspace(
  exists: (path: string) => Promise<boolean>,
  cwd: string,
): Promise<string | undefined> {
  let folder = cwd.replace(/\\/g, '/').replace(/\/+$/, '')
  for (let i = 0; i < 12 && folder; i++) {
    if (await exists(`${folder}/${MARKER}`)) return folder
    const up = folder.slice(0, folder.lastIndexOf('/'))
    if (up === folder || !up.includes('/')) break
    folder = up
  }
  return undefined
}

/** The status line for a status file's content: its line, marked stale when the last check is over 30 minutes old. */
export function statusText(raw: string, now: number): string | undefined {
  let status: Status
  try {
    status = JSON.parse(raw) as Status
  } catch {
    return undefined
  }
  if (!status.line) return undefined
  const checked = status.checked ? Date.parse(status.checked) : NaN
  const stale = Number.isFinite(checked) && now - checked > 30 * 60_000 ? ' (stale)' : ''
  return `${status.line}${stale}`
}

export const register: Register = on => {
  let lastLevel: string | undefined

  on('session.start', async ($, e, next) => {
    const done = await next(e)
    const root = await findWorkspace(path => $.fs.exists(path), e.cwd)
    if (!root) return done
    const refresh = async () => {
      let raw: string
      try {
        raw = await $.fs.read(`${root}/${STATUS}`)
      } catch {
        return // no guard run yet
      }
      $.ui.status(statusText(raw, Date.now()))
      let level: string | undefined
      try {
        level = (JSON.parse(raw) as Status).level
      } catch {
        level = undefined
      }
      if (level === 'hard' && lastLevel !== 'hard') {
        $.ui.toast('GDStudio disk under the hard limit: no new agent or worktree starts (docs/hooks.md#disk)')
      }
      lastLevel = level
    }
    await refresh()
    $.clock.every(EVERY_MS, () => void refresh())
    return done
  })
}
