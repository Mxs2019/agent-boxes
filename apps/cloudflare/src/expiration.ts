import { HttpError } from "./errors";

const SECOND = 1;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;
const MONTH = 30 * DAY;
const YEAR = 365 * DAY;
const MAX_UNIX_SECONDS = 253_402_300_799;

const UNIT_SECONDS: Record<string, number> = {
  ms: 0.001,
  millisecond: 0.001,
  milliseconds: 0.001,
  s: SECOND,
  sec: SECOND,
  secs: SECOND,
  second: SECOND,
  seconds: SECOND,
  m: MINUTE,
  min: MINUTE,
  mins: MINUTE,
  minute: MINUTE,
  minutes: MINUTE,
  h: HOUR,
  hr: HOUR,
  hrs: HOUR,
  hour: HOUR,
  hours: HOUR,
  d: DAY,
  day: DAY,
  days: DAY,
  w: WEEK,
  week: WEEK,
  weeks: WEEK,
  mo: MONTH,
  month: MONTH,
  months: MONTH,
  y: YEAR,
  yr: YEAR,
  yrs: YEAR,
  year: YEAR,
  years: YEAR,
};

const DURATION_PART =
  /(\d+(?:\.\d+)?)\s*(milliseconds?|months?|minutes?|seconds?|weeks?|hours?|days?|years?|secs?|mins?|hrs?|yrs?|sec|ms|min|mo|hr|yr|s|m|h|d|w|y)/gi;

function invalidDuration(field: "expires_in" | "show_in", allowNever: boolean): never {
  const suffix = allowNever ? ", an ISO 8601 duration, or never" : " or an ISO 8601 duration";
  throw new HttpError(
    400,
    field === "expires_in" ? "invalid_expiration" : "invalid_schedule",
    `${field} must be a positive duration${suffix}.`,
  );
}

function parseISODuration(value: string): number | null {
  const match = value.match(
    /^P(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i,
  );
  if (!match) return null;
  const units = [YEAR, MONTH, WEEK, DAY, HOUR, MINUTE, SECOND];
  return match.slice(1).reduce((total, part, index) => total + Number(part ?? 0) * units[index], 0);
}

function parseWrittenDuration(
  value: string,
  field: "expires_in" | "show_in",
  allowNever: boolean,
): number {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/,/g, " ")
    .replace(/\band\b/g, " ");
  if (/^\d+(?:\.\d+)?$/.test(normalized)) return Number(normalized);

  let seconds = 0;
  let consumedThrough = 0;
  DURATION_PART.lastIndex = 0;
  for (const match of normalized.matchAll(DURATION_PART)) {
    const gap = normalized.slice(consumedThrough, match.index);
    if (gap.trim()) invalidDuration(field, allowNever);
    seconds += Number(match[1]) * UNIT_SECONDS[match[2].toLowerCase()];
    consumedThrough = (match.index ?? 0) + match[0].length;
  }
  if (normalized.slice(consumedThrough).trim()) invalidDuration(field, allowNever);
  return seconds;
}

export function durationSeconds(
  value: unknown,
  field: "expires_in" | "show_in" = "expires_in",
  allowNever = true,
): number | null {
  if (typeof value === "number") {
    if (!Number.isFinite(value)) invalidDuration(field, allowNever);
    return value;
  }

  if (typeof value !== "string") invalidDuration(field, allowNever);

  const normalized = value.trim();
  if (normalized.toLowerCase() === "never") {
    if (allowNever) return null;
    invalidDuration(field, allowNever);
  }
  if (!normalized) invalidDuration(field, allowNever);
  return parseISODuration(normalized) ?? parseWrittenDuration(normalized, field, allowNever);
}

export function resolveExpiration(
  startsAt: number,
  expiresIn: unknown,
  expiresAt: unknown,
): number | null {
  if (expiresIn !== undefined && expiresAt !== undefined) {
    throw new HttpError(400, "invalid_expiration", "Use expires_in or expires_at, but not both.");
  }

  if (expiresAt !== undefined) {
    if (
      typeof expiresAt !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(expiresAt)
    ) {
      throw new HttpError(
        400,
        "invalid_expiration",
        "expires_at must use an ISO 8601 date and time with a time zone.",
      );
    }
    const parsed = Date.parse(expiresAt);
    if (!Number.isFinite(parsed)) {
      throw new HttpError(
        400,
        "invalid_expiration",
        "expires_at must use an ISO 8601 date and time with a time zone.",
      );
    }
    const timestamp = Math.floor(parsed / 1000);
    if (timestamp <= startsAt) {
      throw new HttpError(
        400,
        "invalid_expiration",
        "expires_at must be after the card becomes visible.",
      );
    }
    if (timestamp > MAX_UNIX_SECONDS) {
      throw new HttpError(400, "invalid_expiration", "expires_at is outside the supported range.");
    }
    return timestamp;
  }

  const seconds = durationSeconds(expiresIn === undefined ? "24h" : expiresIn);
  if (seconds === null) return null;
  if (!Number.isFinite(seconds) || seconds <= 0) invalidDuration("expires_in", true);

  const timestamp = startsAt + Math.ceil(seconds);
  if (!Number.isSafeInteger(timestamp) || timestamp > MAX_UNIX_SECONDS) {
    invalidDuration("expires_in", true);
  }
  return timestamp;
}
