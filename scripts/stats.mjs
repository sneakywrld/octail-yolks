#!/usr/bin/env node
/**
 * The "Stats" section of README.md (between `<!-- stats:start -->` and `<!-- stats:end -->`) and docs/stats.js (the
 * data of the optional GitHub Pages view, docs/index.html), generated from:
 *
 *   images.json               the tags, families, platforms
 *   images/<tag>/Dockerfile   the base image of each tag (its last FROM) and so its distribution
 *   stats/eggs-usage.json     which Octail eggs use each image, and their real-node test results. Inside the Octail
 *                             monorepo this script regenerates it from ../octail/eggs (through
 *                             octail/scripts/eggs/build-repo.mjs and stats.mjs, so it needs octail's node_modules);
 *                             the published octail-yolks repository has no eggs and reads the committed file.
 *   stats/images.json         optional facts CI writes per image (digest, compressed size, platforms, build date, CVE
 *                             counts). Missing or partial: those columns are left out.
 *
 *   node scripts/stats.mjs            rewrite the section, docs/stats.js (and stats/eggs-usage.json in the monorepo)
 *   node scripts/stats.mjs --check    exit 1 when any of them is out of date (test/run.sh runs it)
 *   --root <dir>                      the yolks folder (default: this script's parent)
 *   --no-eggs                         don't regenerate eggs-usage.json from ../octail/eggs, read the committed file
 *
 * Node only, no dependencies (outside the monorepo).
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const START = "<!-- stats:start -->";
export const END = "<!-- stats:end -->";
export const USAGE_FILE = "stats/eggs-usage.json";
export const CI_FILE = "stats/images.json";
export const PAGE_DATA = "docs/stats.js";
export const SCHEMA = 1;
const DEFAULT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const EGGS_URL = "https://github.com/sneakywrld/octail-eggs";
const RESULTS = ["pass", "fail", "blocked", "untested"];

/** The families, in README order. A tag belongs to the first whose `match` accepts it (installers first). */
export const FAMILIES = [
  { id: "java", title: "Java", match: (i) => /^java_/.test(i.tag) },
  {
    id: "dotnet",
    title: ".NET and Mono",
    match: (i) => /^(dotnet_|mono$)/.test(i.tag),
  },
  { id: "runtimes", title: "Other runtimes", match: () => true },
  {
    id: "steamcmd",
    title: "SteamCMD and game images",
    match: (i) => /^(steamcmd_|source$|rust$)/.test(i.tag),
  },
  {
    id: "wine",
    title: "Wine and Proton",
    match: (i) => /^(wine|proton)/.test(i.tag),
  },
  {
    id: "installers",
    title: "Installers",
    match: (i) => i.kind === "installer" || /^installer_/.test(i.tag),
  },
];
const MATCH_ORDER = [
  "installers",
  "java",
  "dotnet",
  "steamcmd",
  "wine",
  "runtimes",
];

/** The family id of an images.json entry. */
export function familyOf(image) {
  return MATCH_ORDER.find((id) =>
    FAMILIES.find((f) => f.id === id).match(image),
  );
}

/**
 * The image a Dockerfile's final stage starts from: { image, distro }. ARG defaults are substituted, and a stage
 * built on an earlier stage resolves to that stage's base. null when there is no FROM.
 */
export function baseOf(dockerfile) {
  const args = {};
  const stages = new Map();
  let last = null;
  for (const raw of String(dockerfile).split(/\r?\n/)) {
    const line = raw.trim();
    const arg = /^ARG\s+([A-Za-z_][A-Za-z0-9_]*)=("?)([^"\s]*)\2/i.exec(line);
    if (arg && !(arg[1] in args)) args[arg[1]] = arg[3];
    const from = /^FROM\s+(?:--platform=\S+\s+)?(\S+)(?:\s+AS\s+(\S+))?/i.exec(
      line,
    );
    if (!from) continue;
    let image = from[1].replace(
      /\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g,
      (_, k) => args[k] ?? "",
    );
    if (stages.has(image.toLowerCase()))
      image = stages.get(image.toLowerCase());
    if (from[2]) stages.set(from[2].toLowerCase(), image);
    last = image;
  }
  return last ? { image: last, distro: distroOf(last) } : null;
}

const DISTROS = [
  [/steamrt\/sniper/, () => "Steam Runtime 3 (sniper)"],
  [/trixie/, () => "Debian 13"],
  [/bookworm/, () => "Debian 12"],
  [/bullseye/, () => "Debian 11"],
  [/^debian:(\d+)/, (m) => `Debian ${m[1]}`],
  [/noble|^ubuntu:24\.04/, () => "Ubuntu 24.04"],
  [/jammy|^ubuntu:22\.04/, () => "Ubuntu 22.04"],
  [/^ubuntu:(\d+\.\d+)/, (m) => `Ubuntu ${m[1]}`],
  [/^alpine:(\d+\.\d+)/, (m) => `Alpine ${m[1]}`],
  [/alpine/, () => "Alpine"],
];

/** The distribution an upstream base image is built on ("eclipse-temurin:21-jdk-noble" → "Ubuntu 24.04"), or null. */
export function distroOf(image) {
  for (const [re, name] of DISTROS) {
    const m = re.exec(String(image));
    if (m) return name(m);
  }
  return null;
}

const first = (o, keys) =>
  keys
    .map((k) => o?.[k])
    .find((v) => v !== undefined && v !== null && v !== "");

/**
 * CI's per-image facts (stats/images.json) as Map(tag → { digest, size, platforms, built, cves }). Accepts a list of
 * objects with `tag`, `{ images: [...] }` or an object keyed by tag, and the usual field spellings; unknown or missing
 * fields stay null, so a partial file shows what it has.
 */
export function normalizeCi(raw) {
  let list = [];
  if (Array.isArray(raw)) list = raw;
  else if (Array.isArray(raw?.images)) list = raw.images;
  else if (raw && typeof raw === "object") {
    const byTag =
      raw.images && typeof raw.images === "object" ? raw.images : raw;
    list = Object.entries(byTag)
      .filter(
        ([k, v]) =>
          !k.startsWith("$") && v && typeof v === "object" && !Array.isArray(v),
      )
      .map(([tag, v]) => ({ tag, ...v }));
  }
  const out = new Map();
  for (const v of list) {
    if (!v || typeof v !== "object" || typeof v.tag !== "string") continue;
    const size = first(v, [
      "compressed_size",
      "compressed_size_bytes",
      "compressed_bytes",
      "size_bytes",
      "size",
    ]);
    const platforms = first(v, ["platforms", "platform"]);
    const built = first(v, [
      "build_date",
      "built",
      "built_at",
      "created",
      "date",
      "pushed_at",
    ]);
    let cves = first(v, ["cves", "cve_counts", "vulnerabilities", "cve"]);
    if (typeof cves === "number") cves = { total: cves };
    else if (cves && typeof cves === "object") {
      const lower = Object.fromEntries(
        Object.entries(cves).map(([k, n]) => [k.toLowerCase(), n]),
      );
      cves = Object.fromEntries(
        ["critical", "high", "medium", "low", "total"]
          .filter((k) => Number.isFinite(lower[k]))
          .map((k) => [k, lower[k]]),
      );
      if (!Object.keys(cves).length) cves = null;
    } else cves = null;
    out.set(v.tag, {
      digest: typeof v.digest === "string" ? v.digest : null,
      size: typeof size === "number" || typeof size === "string" ? size : null,
      platforms: Array.isArray(platforms)
        ? platforms.map(String)
        : typeof platforms === "string"
          ? platforms.split(/[\s,]+/).filter(Boolean)
          : null,
      built: typeof built === "string" ? built.slice(0, 10) : null,
      base: typeof v.base === "string" ? v.base : null,
      cves,
    });
  }
  return out;
}

/** A size for a table: bytes → "312 MiB" / "1.4 GiB"; a string is shown as it is. */
export function sizeText(size) {
  if (typeof size === "string") return size;
  if (typeof size !== "number" || !Number.isFinite(size)) return "–";
  const mib = size / 1048576;
  return mib >= 1024
    ? `${(mib / 1024).toFixed(1)} GiB`
    : `${Math.round(mib)} MiB`;
}

/** CVE counts for a table: "0 critical, 3 high" (or the total when that's all CI gave). */
export function cveText(cves) {
  if (!cves) return "–";
  if (cves.critical !== undefined || cves.high !== undefined)
    return `${cves.critical ?? 0} critical, ${cves.high ?? 0} high`;
  return cves.total !== undefined ? String(cves.total) : "–";
}

const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

/** Reads the CI facts, or null when the file is missing or unreadable. */
export function readCi(root) {
  const path = join(root, CI_FILE);
  if (!existsSync(path)) return null;
  try {
    const ci = normalizeCi(readJson(path));
    return ci.size ? ci : null;
  } catch {
    return null;
  }
}

/**
 * The egg usage: regenerated from ../octail/eggs when this is the monorepo (and `fromEggs`), else the committed
 * stats/eggs-usage.json, else null. Returns { usage, generated }.
 */
export async function loadUsage(root, { fromEggs = true } = {}) {
  const octail = resolve(root, "..", "octail");
  const buildRepo = join(octail, "scripts", "eggs", "build-repo.mjs");
  if (fromEggs && existsSync(buildRepo) && existsSync(join(octail, "eggs"))) {
    const { eggEntries } = await import(pathToFileURL(buildRepo).href);
    const { yolksUsage } = await import(
      pathToFileURL(join(octail, "scripts", "eggs", "stats.mjs")).href
    );
    return {
      usage: yolksUsage(eggEntries({ src: join(octail, "eggs") })),
      generated: true,
    };
  }
  const path = join(root, USAGE_FILE);
  return { usage: existsSync(path) ? readJson(path) : null, generated: false };
}

/** Everything the README section and the page show (docs/stats.js holds exactly this). */
export function buildStats({ images, dockerfiles, usage, ci }) {
  const eggs = usage?.eggs ?? {};
  const rows = images.images.map((img) => {
    const kind = img.kind === "installer" ? "installer" : "runtime";
    const used = usage?.images?.[img.tag];
    const ids = used ? [...(used[kind] ?? [])] : [...(img.eggs ?? [])];
    const base = baseOf(dockerfiles[img.tag] ?? "");
    const facts = ci?.get(img.tag) ?? null;
    const counts = Object.fromEntries(
      RESULTS.map((r) => [
        r,
        ids.filter((id) => eggs[id]?.result === r).length,
      ]),
    );
    return {
      tag: img.tag,
      kind,
      family: familyOf(img),
      description: img.description ?? "",
      platforms: (facts?.platforms ?? img.platforms ?? []).map((p) =>
        String(p).replace(/^linux\//, ""),
      ),
      base: base?.image ?? null,
      distro: base?.distro ?? null,
      eggs: ids,
      tested: usage ? counts : null,
      ci: facts,
    };
  });
  const families = FAMILIES.map((f) => {
    const members = rows.filter((r) => r.family === f.id);
    return {
      id: f.id,
      title: f.title,
      images: members.map((r) => r.tag),
      eggs: new Set(members.flatMap((r) => r.eggs)).size,
    };
  }).filter((f) => f.images.length);
  const results = Object.values(eggs).map((e) => e.result);
  return {
    schema: SCHEMA,
    registry: images.registry,
    eggs_repo: usage?.eggs_repo ?? EGGS_URL,
    images: rows.length,
    runtime: rows.filter((r) => r.kind === "runtime").length,
    installers: rows.filter((r) => r.kind === "installer").length,
    multi_arch: rows.filter((r) => r.platforms.length > 1).length,
    eggs_total: usage ? Object.keys(eggs).length : null,
    eggs_tested: usage
      ? Object.fromEntries(
          RESULTS.map((r) => [r, results.filter((x) => x === r).length]),
        )
      : null,
    ci: Boolean(ci),
    families,
    rows,
    eggs,
  };
}

const badge = (label, message, color) => {
  const part = (s) =>
    encodeURIComponent(String(s).replace(/-/g, "--").replace(/_/g, "__"));
  return `https://img.shields.io/badge/${part(label)}-${part(message)}-${color}`;
};
const cell = (s) =>
  String(s ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\r?\n/g, " ");

/** The README section, markers included. */
export function readmeSection(stats, { listEggs = 6 } = {}) {
  // Plain ids keep the table readable; the Pages view links every egg to its file in octail-eggs.
  const eggsCell = (ids) =>
    ids.length
      ? `${ids.length}: ${ids.slice(0, listEggs).join(", ")}${ids.length > listEggs ? `, +${ids.length - listEggs} more` : ""}`
      : "–";
  const ciRows = stats.rows.filter((r) => r.ci);
  const showCi = ciRows.length > 0;
  const has = (k) =>
    ciRows.some((r) => r.ci[k] !== null && r.ci[k] !== undefined);
  const ciCols = showCi
    ? [
        has("size") && ["Size", (r) => sizeText(r.ci?.size)],
        has("built") && ["Built", (r) => r.ci?.built ?? "–"],
        has("cves") && ["CVEs", (r) => cveText(r.ci?.cves)],
      ].filter(Boolean)
    : [];
  const t = stats.eggs_tested;
  const badges = [
    ["images", stats.images, "2496ED"],
    ["runtime", stats.runtime, "blue"],
    ["installers", stats.installers, "blue"],
    ["multi-arch", `${stats.multi_arch} of ${stats.images}`, "informational"],
    ...(stats.eggs_total !== null
      ? [["eggs using them", stats.eggs_total, "brightgreen"]]
      : []),
  ].map(([l, m, c]) => `![${l}: ${m}](${badge(l, m, c)})`);
  const head = [
    "Image",
    "Family",
    "Base",
    "Platforms",
    "Eggs",
    ...(t ? ["✅ Passed"] : []),
    ...ciCols.map((c) => c[0]),
  ];
  const fam = (id) => stats.families.find((f) => f.id === id)?.title ?? id;
  const lines = [
    START,
    "<!-- Generated by scripts/stats.mjs from images.json, the Dockerfiles, stats/eggs-usage.json and (when CI wrote",
    "     it) stats/images.json. Run `node scripts/stats.mjs` after changing them; `--check` fails when this is stale. -->",
    "",
    "## Stats",
    "",
    badges.join(" "),
    "",
    `**${stats.images} images**: ${stats.runtime} runtime images and ${stats.installers} installer images, ` +
      `${stats.multi_arch} of them built for amd64 and arm64.` +
      (stats.eggs_total !== null
        ? ` They run the ${stats.eggs_total} eggs of [octail-eggs](${stats.eggs_repo})` +
          (t
            ? `, ${t.pass} of which passed a real run on one of our nodes.`
            : ".")
        : ""),
    `The same numbers as a page: [docs/index.html](docs/index.html) (GitHub Pages, when switched on for \`/docs\`).`,
    "",
    "| Family | Images | Eggs using them |",
    "| --- | --- | ---: |",
    ...stats.families.map(
      (f) =>
        `| ${cell(f.title)} | ${f.images.map((tag) => `[\`${tag}\`](#${tag})`).join(" ")} | ${f.eggs} |`,
    ),
    "",
    `| ${head.join(" | ")} |`,
    `| ${head.map((h) => (h === "Eggs" || h === "Image" || h === "Family" || h === "Base" || h === "Platforms" ? "---" : "---:")).join(" | ")} |`,
    ...stats.rows.map((r) => {
      const cols = [
        `[\`${r.tag}\`](#${r.tag})`,
        fam(r.family),
        r.base ? `${r.distro ?? "?"} (\`${r.base}\`)` : "–",
        r.platforms.join(", ") || "–",
        eggsCell(r.eggs),
        ...(t
          ? [r.eggs.length ? `${r.tested.pass} / ${r.eggs.length}` : "–"]
          : []),
        ...ciCols.map((c) => c[1](r)),
      ];
      return `| ${cols.map(cell).join(" | ")} |`;
    }),
    "",
    "Eggs: the eggs whose server (runtime images) or install script (installers) runs in the image" +
      (t
        ? "; ✅ Passed: how many of them passed their last real-node run."
        : ".") +
      (showCi
        ? " Size, build date and CVE counts come from the last CI build (`stats/images.json`)."
        : ""),
    "",
    END,
  ];
  return lines.join("\n");
}

/** `readme` with its stats section replaced by `section`. Throws when the markers are missing. */
export function withSection(readme, section) {
  const a = readme.indexOf(START);
  const b = readme.indexOf(END);
  if (a < 0 || b < a)
    throw new Error(`README.md has no ${START} … ${END} block`);
  return readme.slice(0, a) + section + readme.slice(b + END.length);
}

/** The page data as a script (a script tag works from file:// and on GitHub Pages alike). */
export function pageScript(stats) {
  return `// Generated by scripts/stats.mjs; do not edit.\nwindow.OCTAIL_YOLKS_STATS = ${JSON.stringify(stats, null, 2)};\n`;
}

/** What the files should contain: { readme, page, usage: string | null } (usage only when regenerated from eggs). */
export async function render(root = DEFAULT_ROOT, { fromEggs = true } = {}) {
  const images = readJson(join(root, "images.json"));
  const dockerfiles = {};
  for (const img of images.images) {
    const path = join(root, img.folder ?? `images/${img.tag}`, "Dockerfile");
    if (existsSync(path)) dockerfiles[img.tag] = readFileSync(path, "utf8");
  }
  const { usage, generated } = await loadUsage(root, { fromEggs });
  const stats = buildStats({ images, dockerfiles, usage, ci: readCi(root) });
  const readme = withSection(
    readFileSync(join(root, "README.md"), "utf8"),
    readmeSection(stats),
  );
  return {
    stats,
    readme,
    page: pageScript(stats),
    usage: generated ? `${JSON.stringify(usage, null, 2)}\n` : null,
  };
}

/** Compares or writes the generated files; returns the list of stale paths (relative to root). */
export async function run(
  root = DEFAULT_ROOT,
  { check = false, fromEggs = true } = {},
) {
  const out = await render(root, { fromEggs });
  const files = [
    ["README.md", out.readme],
    [PAGE_DATA, out.page],
    ...(out.usage !== null ? [[USAGE_FILE, out.usage]] : []),
  ];
  const stale = [];
  for (const [rel, content] of files) {
    const path = join(root, rel);
    const current = existsSync(path)
      ? readFileSync(path, "utf8").replace(/\r\n/g, "\n")
      : null;
    if (current === content) continue;
    stale.push(rel);
    if (!check) {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, content);
    }
  }
  return stale;
}

function parseArgs(argv) {
  const args = { check: false, fromEggs: true, root: DEFAULT_ROOT };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--check") args.check = true;
    else if (argv[i] === "--no-eggs") args.fromEggs = false;
    else if (argv[i] === "--root") args.root = resolve(argv[++i]);
    else throw new Error(`unknown argument ${argv[i]}`);
  }
  return args;
}

const isMain =
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const args = parseArgs(process.argv.slice(2));
    if (!existsSync(join(args.root, "images.json")))
      throw new Error(`${args.root} has no images.json`);
    const stale = await run(args.root, args);
    if (args.check && stale.length) {
      console.error(
        `out of date: ${stale.join(", ")}; run node scripts/stats.mjs`,
      );
      process.exitCode = 1;
    } else
      console.log(
        stale.length ? `updated ${stale.join(", ")}` : "stats up to date",
      );
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}
