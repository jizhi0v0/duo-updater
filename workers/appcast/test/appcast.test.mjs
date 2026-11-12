import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test, { after, before } from "node:test";
import ts from "typescript";

// Load the handler with the pinned compiler so the test works on Node 22.0.
const source = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { default: worker } = await import(`data:text/javascript,${encodeURIComponent(outputText)}`);

const feed = `<rss><channel>
  <item><sparkle:shortVersionString>0.5.23</sparkle:shortVersionString></item>
  <item><sparkle:shortVersionString>0.5.24-beta.7</sparkle:shortVersionString></item>
</channel></rss>`;

const upstreamFetch = globalThis.fetch;
before(() => {
  globalThis.fetch = async () => new Response(feed);
});
after(() => {
  globalThis.fetch = upstreamFetch;
});

const cases = [
  ["counts a listed stable version", "0.5.23", ["0.5.23"]],
  ["counts a listed beta version", "0.5.24-beta.7", ["0.5.24-beta.7"]],
  ["counts an unlisted beta version as older", "0.5.24-beta.9999", ["older"]],
  ["ignores an invalid beta version", "0.5.24-beta.12345", []],
];

for (const [name, version, expected] of cases) {
  test(name, async () => {
    const recordedVersions = [];
    const backgroundWork = [];
    const env = {
      HASH_KEY: "test-only",
      DB: {
        prepare() {
          return {
            bind(_day, version) {
              return { run: async () => recordedVersions.push(version) };
            },
          };
        },
      },
    };
    const request = new Request("https://example.test/appcast.xml", {
      headers: {
        "user-agent": `DuoUpdater/${version} Sparkle/2.10.1`,
        "cf-connecting-ip": "192.0.2.1",
      },
    });
    const response = await worker.fetch(request, env, {
      waitUntil: (work) => backgroundWork.push(work),
    });
    await Promise.all(backgroundWork);

    assert.equal(response.status, 200);
    assert.equal(await response.text(), feed);
    assert.deepEqual(recordedVersions, expected);
  });
}
