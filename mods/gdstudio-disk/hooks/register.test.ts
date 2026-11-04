import { expect, test } from 'claude-code/testing'
import { findWorkspace, statusText } from './register'

const NOW = Date.parse('2026-11-04T12:00:00+00:00')

test('the status line is the guard line, marked stale after half an hour', () => {
  const fresh = JSON.stringify({ line: 'disk 7.7G free HARD<10', checked: '2026-11-04T11:55:00+00:00' })
  expect(statusText(fresh, NOW)).toBe('disk 7.7G free HARD<10')
  const old = JSON.stringify({ line: 'disk 50.0G free', checked: '2026-11-04T10:00:00+00:00' })
  expect(statusText(old, NOW)).toBe('disk 50.0G free (stale)')
  expect(statusText('not json', NOW)).toBe(undefined)
  expect(statusText('{}', NOW)).toBe(undefined)
})

test('the workspace is found above a worktree, and nothing outside one', async () => {
  const marker = 'C:/Repositories/GDStudio/.gdstudio-workspace'
  const exists = async (path: string) => path === marker
  expect(await findWorkspace(exists, 'C:\\Repositories\\GDStudio\\worktrees\\deadnight\\x')).toBe(
    'C:/Repositories/GDStudio',
  )
  expect(await findWorkspace(exists, 'D:/elsewhere/project')).toBe(undefined)
})

test('at session start the status line shows the last guard run', async ($, on) => {
  const shown: (string | undefined)[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  // the engine hands the path on in the platform's own spelling (backslashes on Windows)
  on('fs.exists', (_, e) => ({ value: e.path.replace(/\\/g, '/') === 'C:/ws/.gdstudio-workspace' }))
  on('fs.read', () => ({
    value: JSON.stringify({ line: 'disk 30.0G free low<40', level: 'soft', checked: new Date().toISOString() }),
  }))
  on('ui.status', (_, e) => {
    shown.push(e.text)
    return { value: undefined }
  })
  on('clock.every', () => ({ value: { cancel: () => {} } }))
  await $.session.start({ cwd: 'C:/ws/worktrees/deadnight/x', surface: 'terminal', isInteractive: true })
  expect(shown).toEqual(['disk 30.0G free low<40'])
})
