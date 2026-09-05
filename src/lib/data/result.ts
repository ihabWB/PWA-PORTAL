/**
 * Data-access result. A query that failed must never be rendered as an empty result:
 * "no readings" and "the query broke" mean opposite things to an operator, and confusing
 * them is exactly how a system loses trust.
 */
export type DataResult<T> =
  { ok: true; data: T } | { ok: false; errorKey: string; detail?: string };

export function ok<T>(data: T): DataResult<T> {
  return { ok: true, data };
}

export function fail<T>(errorKey: string, detail?: string): DataResult<T> {
  return { ok: false, errorKey, detail };
}

/** A missing function or column means a migration has not been applied on this project. */
export function classifyPostgrestError(code: string | undefined): string {
  switch (code) {
    case "PGRST202": // function not found in the schema cache
    case "42883": // undefined_function
    case "42703": // undefined_column
      return "errors.migrationMissing";
    case "42501":
      return "errors.notPermitted";
    default:
      return "errors.queryFailed";
  }
}
