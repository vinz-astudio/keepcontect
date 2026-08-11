export type MigrationOrigin = 'live' | 'as-applied' | 'from-repo'

export interface MigrationEntry {
  origin: MigrationOrigin
  file: string
  path: string
}

export interface HistoricalMigration extends MigrationEntry {
  sql: string
}

export interface FunctionBlock {
  file: string
  name: string
  body: string
}

export declare const LIVE_DIR: string
export declare const ARCHIVE_AS_APPLIED: string
export declare const ARCHIVE_FROM_REPO: string

export declare function findMigrations(
  fragment: string,
  options?: { root?: string },
): MigrationEntry[]

export declare function readHistoricalMigration(
  fragment: string,
  options?: { root?: string; origin?: MigrationOrigin },
): HistoricalMigration

export declare function listLiveMigrations(
  options?: { root?: string },
): Array<{ file: string; path: string }>

export declare function extractLiveFunctionBodies(
  namePattern: RegExp,
  options?: { root?: string },
): FunctionBlock[]
