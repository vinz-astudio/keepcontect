/**
 * What version the desktop installer behind `exeUrl` will actually install.
 *
 * The desktop update loop was structural, not a slip. `version.json` carries one
 * `version` field for every platform, and the Android release script bumps it
 * without touching `exeUrl`, because it does not build a desktop installer. So
 * after each Android release the desktop app read "0.7.3 is available", fetched
 * the installer still named 0.7.2, installed it, and came back reporting 0.7.2 —
 * which it then compared against 0.7.3 and offered the update again. The user
 * sat on 0.7.1 through several of these cycles.
 *
 * Trusting the version string was the mistake. The only fact that cannot drift
 * from what the installer does is the installer's own URL, so the offered
 * desktop version is read out of it. If the URL carries no version — the old
 * unversioned `/desktop/KeepContact-Setup.exe` path, which served a stale build
 * for months — there is no honest claim to make and the answer is null, which
 * the caller must treat as "no desktop update to offer" rather than as "up to
 * date".
 */
export function desktopOfferedVersion(exeUrl: string | undefined | null): string | null {
  if (!exeUrl) return null
  // Matches both the tag segment (/download/v0.7.3/) and the file name
  // (KeepContact-0.7.3-Setup.exe). They agree in a correct release; when they
  // disagree the file name wins, because that is the artifact that runs.
  const fromFile = /KeepContact-(\d+\.\d+\.\d+)-Setup\.exe/i.exec(exeUrl)
  if (fromFile) return fromFile[1]
  const fromTag = /\/download\/v(\d+\.\d+\.\d+)\//i.exec(exeUrl)
  if (fromTag) return fromTag[1]
  return null
}

/**
 * True when the installer at `exeUrl` is genuinely newer than what is running.
 *
 * `isNewer` is injected rather than imported so this stays a pure comparison
 * the release gate can test without pulling in the update UI.
 */
export function desktopHasRealUpdate(
  currentVersion: string,
  exeUrl: string | undefined | null,
  isNewer: (candidate: string, current: string) => boolean,
): boolean {
  const offered = desktopOfferedVersion(exeUrl)
  if (offered === null) return false
  return isNewer(offered, currentVersion)
}
