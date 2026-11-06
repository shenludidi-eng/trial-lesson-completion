#!/usr/bin/env node
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";
import vm from "node:vm";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(resolve(root, "index.html"), "utf8");
const sourceStart = html.indexOf("function utcDateOffset(dateText,days)");
const sourceEnd = html.indexOf("const PRESETS = buildPresetOptions", sourceStart);
assert.notEqual(sourceStart, -1, "missing UTC preset helpers");
assert.notEqual(sourceEnd, -1, "missing dynamic PRESETS declaration");

const context = {};
vm.createContext(context);
vm.runInContext(
  `${html.slice(sourceStart, sourceEnd)}\nthis.buildPresetOptions = buildPresetOptions;`,
  context,
);

const cases = [
  {
    cutoff: "2026-11-05 11:14:43",
    last7: ["2026-10-29 00:00:00", "2026-11-04 23:59:59"],
    previous: ["2026-10-26 00:00:00", "2026-11-01 23:59:59"],
  },
  {
    cutoff: "2026-11-02 02:13:16",
    last7: ["2026-10-26 00:00:00", "2026-11-01 23:59:59"],
    previous: ["2026-10-26 00:00:00", "2026-11-01 23:59:59"],
  },
  {
    cutoff: "2026-11-06 08:14:50",
    last7: ["2026-10-30 00:00:00", "2026-11-05 23:59:59"],
    previous: ["2026-10-26 00:00:00", "2026-11-01 23:59:59"],
  },
  {
    cutoff: "2027-01-01 00:05:00",
    last7: ["2026-12-25 00:00:00", "2026-12-31 23:59:59"],
    previous: ["2026-12-21 00:00:00", "2026-12-27 23:59:59"],
  },
];

for(const testCase of cases){
  const options = context.buildPresetOptions("2026-08-01 00:00:00", testCase.cutoff);
  const byValue = Object.fromEntries(options.map(option=>[option.value,option]));
  assert.deepEqual(
    [byValue.last7full.start, byValue.last7full.end],
    testCase.last7,
    `last7full mismatch for ${testCase.cutoff}`,
  );
  assert.deepEqual(
    [byValue.prevWeek.start, byValue.prevWeek.end],
    testCase.previous,
    `prevWeek mismatch for ${testCase.cutoff}`,
  );
}

console.log(`preset windows OK (${cases.length} cutoff scenarios)`);
