import { HttpError } from "./errors";
import { durationSeconds } from "./expiration";

const MAX_UNIX_SECONDS = 253_402_300_799;
const ISO_DATE_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

export function resolveShowAt(createdAt: number, showAt: unknown, showIn?: unknown): number | null {
  if (showAt !== undefined && showAt !== null && showIn !== undefined) {
    throw new HttpError(400, "invalid_schedule", "Use show_at or show_in, but not both.");
  }

  if (showIn !== undefined) {
    const seconds = durationSeconds(showIn, "show_in", false);
    if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) {
      throw new HttpError(400, "invalid_schedule", "show_in must be a positive duration.");
    }
    const timestamp = createdAt + Math.ceil(seconds);
    if (!Number.isSafeInteger(timestamp) || timestamp > MAX_UNIX_SECONDS) {
      throw new HttpError(400, "invalid_schedule", "show_in is outside the supported range.");
    }
    return timestamp;
  }

  if (showAt === undefined || showAt === null) return null;
  if (typeof showAt !== "string" || !ISO_DATE_TIME.test(showAt)) {
    throw new HttpError(
      400,
      "invalid_schedule",
      "show_at must use an ISO 8601 date and time with a time zone.",
    );
  }

  const parsed = Date.parse(showAt);
  if (!Number.isFinite(parsed)) {
    throw new HttpError(
      400,
      "invalid_schedule",
      "show_at must use an ISO 8601 date and time with a time zone.",
    );
  }

  const timestamp = Math.floor(parsed / 1000);
  if (timestamp <= createdAt) {
    throw new HttpError(400, "invalid_schedule", "show_at must be in the future.");
  }
  if (timestamp > MAX_UNIX_SECONDS) {
    throw new HttpError(400, "invalid_schedule", "show_at is outside the supported range.");
  }
  return timestamp;
}
