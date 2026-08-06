import { describe, expect, it } from "vitest";
import { resolveShowAt } from "../src/scheduling";

const CREATED_AT = 1_700_000_000;

describe("scheduling", () => {
  it("keeps an omitted schedule immediate", () => {
    expect(resolveShowAt(CREATED_AT, undefined)).toBeNull();
  });

  it("accepts a future ISO 8601 date and time", () => {
    const value = "2030-05-10T12:30:00-04:00";
    expect(resolveShowAt(CREATED_AT, value)).toBe(Math.floor(Date.parse(value) / 1000));
  });

  it.each([
    ["2d", 172_800],
    ["2h 30m", 9_000],
    ["P1DT12H", 129_600],
    [90, 90],
  ])("accepts the relative schedule %s", (duration, seconds) => {
    expect(resolveShowAt(CREATED_AT, undefined, duration)).toBe(CREATED_AT + seconds);
  });

  it("rejects two schedule inputs", () => {
    expect(() => resolveShowAt(CREATED_AT, "2030-05-10T12:30:00-04:00", "2d")).toThrow(
      "Use show_at or show_in, but not both.",
    );
  });

  it.each(["", "soon", "never", "0h", -1])("rejects the relative schedule %s", (duration) => {
    expect(() => resolveShowAt(CREATED_AT, undefined, duration)).toThrow(
      "show_in must be a positive duration",
    );
  });

  it.each(["Thursday", "2030-05-10", "2030-05-10T12:30:00", 42, true])(
    "rejects the invalid schedule %s",
    (value) => {
      expect(() => resolveShowAt(CREATED_AT, value)).toThrow(
        "show_at must use an ISO 8601 date and time with a time zone",
      );
    },
  );

  it("rejects a schedule that is not in the future", () => {
    expect(() => resolveShowAt(CREATED_AT, "2020-01-01T00:00:00Z")).toThrow(
      "show_at must be in the future",
    );
  });
});
