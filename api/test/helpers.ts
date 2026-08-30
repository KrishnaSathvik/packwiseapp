import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

import type { HttpRequest, HttpResponse } from "../src/pipeline.ts";
import type { TripContextDTO } from "../src/types.ts";

export const SHARED_DIR = fileURLToPath(new URL("../../shared/", import.meta.url));

export type Captured = {
  status: number;
  body: unknown;
  headers: Record<string, string | number>;
};

export function capture(): { response: HttpResponse; captured: Captured } {
  const captured: Captured = { status: 0, body: undefined, headers: {} };
  const response: HttpResponse = {
    status(code) {
      captured.status = code;
      return response;
    },
    json(body) {
      captured.body = body;
      return body;
    },
    setHeader(name, value) {
      captured.headers[name] = value;
      return value;
    },
  };
  return { response, captured };
}

export function post(body: unknown, headers: Record<string, string> = {}): HttpRequest {
  return { method: "POST", headers, body };
}

export const SAFETY_IDENTIFIER = "eval-fixture-identifier";

export function tripContext(overrides: Partial<TripContextDTO> = {}): TripContextDTO {
  return {
    destination: { displayName: "Chicago", countryCode: "US" },
    startDate: "2026-09-01",
    endDate: "2026-09-05",
    durationDays: 5,
    tripType: "cityBreak",
    activities: ["sightseeing", "walking"],
    contextChips: [],
    bagType: "carryOn",
    packingStyle: "balanced",
    travelerCount: 1,
    ...overrides,
  };
}

export type TripEvalFixture = {
  id: string;
  destinationFixture: string;
  days: number;
  tripType: string;
  activities: string[];
  bag: string;
  style: string;
  chips?: string[];
  travelerCount?: number;
  party?: { travelers: unknown[] };
  note?: string;
  mustInfer?: string[];
  mustNotInfer?: string[];
  allowedSuggestions?: string[];
  mustInclude?: string[];
};

export function tripEvalFixtures(): TripEvalFixture[] {
  const dir = join(SHARED_DIR, "fixtures", "trips");
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .sort()
    .map((name) => JSON.parse(readFileSync(join(dir, name), "utf8")) as TripEvalFixture);
}

export function destinationFor(displayName: string): { displayName: string; countryCode: string } {
  const file = join(SHARED_DIR, "fixtures", "test-destinations.json");
  const parsed = JSON.parse(readFileSync(file, "utf8")) as {
    destinations: { displayName: string; countryCode: string }[];
  };
  const match = parsed.destinations.find((row) => row.displayName === displayName);
  if (!match) throw new Error(`unknown destination fixture ${displayName}`);
  return { displayName: match.displayName, countryCode: match.countryCode };
}

export function contextFromFixture(fixture: TripEvalFixture): TripContextDTO {
  return {
    destination: destinationFor(fixture.destinationFixture),
    startDate: "2026-09-01",
    endDate: "2026-09-05",
    durationDays: fixture.days,
    tripType: fixture.tripType,
    activities: fixture.activities,
    contextChips: fixture.chips ?? [],
    bagType: fixture.bag,
    packingStyle: fixture.style,
    travelerCount: fixture.party?.travelers.length ?? fixture.travelerCount ?? 1,
  };
}
