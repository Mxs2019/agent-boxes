import { describe, expect, it } from "vitest";
import { resolveExpiration } from "../src/expiration";

const CREATED_AT = 1_700_000_000;

describe("expiration", () => {
  it("uses 24 hours by default and supports never", () => {
    expect(resolveExpiration(CREATED_AT, undefined, undefined)).toBe(CREATED_AT + 86_400);
    expect(resolveExpiration(CREATED_AT, "never", undefined)).toBeNull();
  });

  it.each([
    ["45m", 2_700],
    ["2h 30m", 9_000],
    ["1.5 hours", 5_400],
    ["10 days", 864_000],
    ["3w", 1_814_400],
    ["1 month and 2 days", 2_764_800],
    ["P1DT12H", 129_600],
    [90, 90],
    [90.5, 91],
  ])("supports the relative duration %s", (duration, seconds) => {
    expect(resolveExpiration(CREATED_AT, duration, undefined)).toBe(CREATED_AT + seconds);
  });

  it("supports an absolute ISO 8601 timestamp", () => {
    const value = "2030-05-10T12:30:00-04:00";
    expect(resolveExpiration(CREATED_AT, undefined, value)).toBe(
      Math.floor(Date.parse(value) / 1000),
    );
  });

  it.each(["", "soon", "0h", "-2h", "P", 0, -1, null, true, {}])(
    "rejects the duration %s",
    (duration) => {
      expect(() => resolveExpiration(CREATED_AT, duration, undefined)).toThrow(
        "expires_in must be a positive duration",
      );
    },
  );

  it("rejects two expiration inputs", () => {
    expect(() => resolveExpiration(CREATED_AT, "2h", "2030-05-10T12:30:00Z")).toThrow(
      "Use expires_in or expires_at, but not both.",
    );
  });
});
