#!/usr/bin/env node
/**
 * PowerShell-free implementation of the Windows scripts.
 *
 * install.cmd and trellis-matt-init.cmd try PowerShell first and fall back to
 * this file when PowerShell is blocked (ExecutionPolicy, AppLocker, Constrained
 * Language Mode). It only needs Node, which Trellis already requires, so it
 * also runs on Linux/macOS:
 *
 *   node scripts/win-fallback.mjs install [--trellis-version 0.6.17]
 *                                         [--dsh-home DIR] [--agents-home DIR] [--bin-dir DIR]
 *   node scripts/win-fallback.mjs sync [--check]
 *   node scripts/win-fallback.mjs init [--user NAME] [--source gh:owner/repo]
 *                                      [--template matt] [--force] [--refresh]
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import https from "node:https";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.dirname(HERE);
const IS_WIN = process.platform === "win32";
const TRELLIS_VERSION = "0.6.17";
const MARKER = "Single-source rule (every planning artifact";
const PYTHON_HINT = "Python 3 is required (install Python 3, or turn off the Microsoft Store 'python' alias)";

const MATT_SKILLS = [
  "ask-matt", "codebase-design", "code-review", "diagnosing-bugs",
  "domain-modeling", "grill-me", "grill-with-docs", "grilling",
  "handoff", "implement", "implement-spec", "improve-codebase-architecture",
  "pr", "prototype", "research", "retro", "setup-matt-pocock-skills",
  "tdd", "to-spec", "to-tickets", "triage", "wayfinder", "writing-for-agents",
];

const DSH_VISIBLE = [
  "ask-matt", "grill-me", "grill-with-docs", "handoff", "implement",
  "implement-spec", "improve-codebase-architecture", "retro",
  "to-spec", "to-tickets", "triage", "wayfinder",
];

function binCmdText(binDir, scriptsDir) {
  // %~dp0 keeps the batch file free of non-ASCII absolute paths (e.g. Chinese user names).
  // Different drives cannot be reached through %~dp0; fall back to %USERPROFILE% when
  // scriptsDir lives under the home directory, otherwise the absolute path is the only option.
  const rel = path.relative(binDir, scriptsDir);
  let dir;
  if (!path.isAbsolute(rel)) {
    dir = rel ? "%~dp0" + rel : "%~dp0.";
  } else {
    const relHome = path.relative(os.homedir(), scriptsDir);
    dir = path.isAbsolute(relHome)
      ? rel
      : "%USERPROFILE%" + (relHome ? path.sep + relHome : "");
  }
  const ps1 = dir + path.sep + "trellis-matt-init.ps1";
  const mjs = dir + path.sep + "win-fallback.mjs";
  return [
    "@echo off",
    "setlocal EnableExtensions",
    "rem Try PowerShell first; fall back to Node when PowerShell is blocked",
    "rem (ExecutionPolicy, AppLocker, Constrained Language Mode).",
    "rem Force the Node path with:  set TRELLIS_NO_POWERSHELL=1",
    'if /i "%TRELLIS_NO_POWERSHELL%"=="1" goto :node',
    "where powershell >nul 2>nul",
    "if errorlevel 1 goto :nops",
    `powershell -NoProfile -ExecutionPolicy Bypass -File "${ps1}" %*`,
    "if not errorlevel 1 exit /b 0",
    "echo.",
    "echo [!] PowerShell failed; falling back to Node.",
    "goto :node",
    ":nops",
    "echo [!] PowerShell not found; using Node.",
    ":node",
    "where node >nul 2>nul",
    "if errorlevel 1 (",
    "  echo ERROR: PowerShell is unavailable and Node was not found.",
    "  exit /b 1",
    ")",
    `node "${mjs}" init %*`,
    "exit /b %ERRORLEVEL%",
  ].join("\r\n") + "\r\n";
}

class Fail extends Error {}
const say = (m) => console.log(m);
const warn = (m) => console.error("WARN: " + m);
const die = (m) => { throw new Fail(m); };
const step = (m) => console.log("\n== " + m + " ==");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const mkdirp = (p) => fs.mkdirSync(p, { recursive: true });
const hasCache = (p) => fs.existsSync(p) && fs.statSync(p).size > 0;

function quoteWin(s) {
  s = String(s);
  if (s === "") return '""';
  if (!/[\s"&|<>^()%!]/.test(s)) return s;
  return '"' + s.replace(/"/g, '""') + '"';
}

function run(cmd, args = [], opts = {}) {
  const capture = opts.capture === true;
  const stdio = capture ? ["ignore", "pipe", "pipe"] : "inherit";
  const res = IS_WIN
    ? spawnSync([cmd, ...args].map(quoteWin).join(" "), { shell: true, stdio, encoding: "utf8", cwd: opts.cwd, env: opts.env })
    : spawnSync(cmd, args, { stdio, encoding: "utf8", cwd: opts.cwd, env: opts.env });
  const status = res.status === null || res.status === undefined ? 127 : res.status;
  return { status, stdout: (res.stdout || "").trim(), stderr: (res.stderr || "").trim() };
}

function which(cmd) {
  const r = run(IS_WIN ? "where" : "which", [cmd], { capture: true });
  return r.status === 0 && r.stdout.length > 0;
}

function findPython() {
  for (const [cmd, args] of [["python", []], ["python3", []], ["py", ["-3"]]]) {
    if (!which(cmd)) continue;
    const r = run(cmd, [...args, "-c", "import sys;print(sys.version_info[0])"], { capture: true });
    if (r.status === 0 && r.stdout.trim() === "3") return { cmd, args };
  }
  return null;
}

function parseFlags(argv, valueFlags) {
  const flags = new Map();
  const norm = (s) => s.toLowerCase().replace(/[-_]/g, "");
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("-") && !a.startsWith("/")) continue;
    let key = a.replace(/^[-/]+/, "");
    let val = true;
    let sep = key.indexOf("=");
    if (sep < 0) {
      // PowerShell also accepts -User:alice; only split when the prefix is a known flag.
      const colon = key.indexOf(":");
      if (colon > 0 && valueFlags.has(norm(key.slice(0, colon)))) sep = colon;
    }
    if (sep >= 0) { val = key.slice(sep + 1); key = key.slice(0, sep); }
    key = norm(key);
    if (val === true && valueFlags.has(key)) {
      if (i + 1 >= argv.length) die("--" + key + " needs a value");
      val = argv[++i];
    }
    flags.set(key, val);
  }
  return flags;
}

function timestamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
}

function sameFile(a, b) {
  return fs.readFileSync(a).equals(fs.readFileSync(b));
}

function cmpVersion(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  }
  return 0;
}

function download(url, dest, timeoutMs) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: timeoutMs, headers: { "user-agent": "trellis-matt-init" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        download(new URL(res.headers.location, url).toString(), dest, timeoutMs).then(resolve, reject);
        return;
      }
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error("HTTP " + res.statusCode));
        return;
      }
      const out = fs.createWriteStream(dest);
      res.pipe(out);
      out.on("finish", () => out.close(() => resolve()));
      out.on("error", reject);
    });
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
  });
}

// ---------------------------------------------------------------- sync

function checkSkills(dshHome, agentsHome) {
  let missing = 0;
  let flagged = 0;
  for (const name of MATT_SKILLS) {
    const p = path.join(agentsHome, "skills", name, "SKILL.md");
    if (!fs.existsSync(p)) { warn("Missing " + p); missing++; }
  }
  for (const name of DSH_VISIBLE) {
    const p = path.join(dshHome, "skills", name, "SKILL.md");
    if (!fs.existsSync(p)) {
      warn("Missing " + p);
      missing++;
    } else if (/^disable-model-invocation:\s*true\s*$/m.test(fs.readFileSync(p, "utf8"))) {
      warn(p + " still hides the skill from the model");
      flagged++;
    }
  }
  if (missing === 0 && flagged === 0) {
    say("OK: Matt skills and DSH copies are complete");
    return true;
  }
  return false;
}

function findSkillDir(root, name) {
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    if (path.basename(dir) === name && entries.some((e) => e.isFile() && e.name === "SKILL.md")) return dir;
    for (const e of entries) if (e.isDirectory() && e.name !== ".git") stack.push(path.join(dir, e.name));
  }
  return null;
}

function stripModelInvocationFlag(file) {
  const s = fs.readFileSync(file, "utf8");
  const eol = s.includes("\r\n") ? "\r\n" : "\n";
  const kept = s.split(/\r?\n/).filter((l) => !/^disable-model-invocation:\s*true\s*$/.test(l));
  let out = kept.join(eol);
  if (!out.endsWith(eol)) out += eol;
  fs.writeFileSync(file, out, "utf8");
}

function syncSkills({ check = false, dshHome, agentsHome }) {
  const mattRepo = process.env.MATT_REPO || "https://github.com/mattpocock/skills.git";
  const mattRef = process.env.MATT_REF || "main";
  if (check) return checkSkills(dshHome, agentsHome);
  if (!which("git")) die("git is required");

  mkdirp(path.join(agentsHome, "skills"));
  mkdirp(path.join(dshHome, "skills"));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "matt-skills-"));
  try {
    say("Downloading Matt skills (" + mattRef + ")...");
    const r = run("git", ["clone", "--depth", "1", "--branch", mattRef, mattRepo, tmp], { capture: true });
    if (r.status !== 0) die("git clone failed: " + mattRepo);

    let copied = 0;
    for (const name of MATT_SKILLS) {
      const src = findSkillDir(path.join(tmp, "skills"), name);
      if (!src) { warn("Skill not found upstream: " + name + " (skipped)"); continue; }
      const dst = path.join(agentsHome, "skills", name);
      fs.rmSync(dst, { recursive: true, force: true });
      fs.cpSync(src, dst, { recursive: true });
      copied++;
    }
    say("Installed " + copied + " Matt skills into " + path.join(agentsHome, "skills"));

    for (const name of DSH_VISIBLE) {
      const src = path.join(agentsHome, "skills", name);
      if (!fs.existsSync(path.join(src, "SKILL.md"))) {
        warn(name + " is not installed; cannot create the DSH copy");
        continue;
      }
      const dst = path.join(dshHome, "skills", name);
      fs.rmSync(dst, { recursive: true, force: true });
      fs.cpSync(src, dst, { recursive: true });
      stripModelInvocationFlag(path.join(dst, "SKILL.md"));
    }
    say("Generated " + DSH_VISIBLE.length + " model-visible DSH copies in " + path.join(dshHome, "skills"));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  return checkSkills(dshHome, agentsHome);
}

// ------------------------------------------------------------- install

function cmdInstall(argv) {
  const flags = parseFlags(argv, new Set(["trellisversion", "dshhome", "agentshome", "bindir"]));
  if (flags.has("help") || flags.has("h")) {
    say("Usage: node win-fallback.mjs install [--trellis-version 0.6.17] [--dsh-home DIR] [--agents-home DIR] [--bin-dir DIR]");
    return 0;
  }
  if (!fs.existsSync(path.join(REPO, "dsh", "AGENTS.md"))) {
    die("run install from the repository checkout (node scripts/win-fallback.mjs install), not from the installed copy");
  }
  const trellisVersion = flags.get("trellisversion") || TRELLIS_VERSION;
  const dshHome = flags.get("dshhome") || process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  const agentsHome = flags.get("agentshome") || process.env.AGENTS_HOME || path.join(os.homedir(), ".agents");
  const binDir = flags.get("bindir") || path.join(os.homedir(), ".local", "bin");

  for (const cmd of ["git", "node", "npm"]) if (!which(cmd)) die(cmd + " is required");
  const python = findPython();
  if (!python) die(PYTHON_HINT);

  step("1/7 Trellis CLI");
  const versionRun = run("trellis", ["--version"], { capture: true });
  const current = versionRun.status === 0 ? (versionRun.stdout.match(/(\d+\.\d+\.\d+)/) || [])[1] : null;
  if (current && cmpVersion(current, trellisVersion) >= 0) {
    if (current === trellisVersion) say("OK: trellis " + current);
    else warn("trellis " + current + " is newer than the tested " + trellisVersion + "; continuing");
  } else {
    say((current ? "Upgrading trellis " + current + " -> " : "Installing trellis ") + trellisVersion);
    if (run("npm", ["install", "-g", "@mindfoldhq/trellis@" + trellisVersion]).status !== 0) {
      die("npm global install failed");
    }
  }
  if (!which("trellis")) die("trellis is still not on PATH; add the npm global bin directory to PATH and retry");

  step("2/7 Matt skills");
  if (!syncSkills({ dshHome, agentsHome })) die("Matt skills sync failed");

  step("3/7 Global rules");
  mkdirp(dshHome);
  const srcAgents = path.join(REPO, "dsh", "AGENTS.md");
  const dstAgents = path.join(dshHome, "AGENTS.md");
  if (fs.existsSync(dstAgents) && !sameFile(srcAgents, dstAgents)) {
    const backup = dstAgents + ".bak." + timestamp();
    fs.copyFileSync(dstAgents, backup);
    say("Backed up existing global rules to " + backup);
  }
  fs.copyFileSync(srcAgents, dstAgents);
  say("OK: " + dstAgents);

  step("4/7 Macro and helper scripts");
  const scriptsDir = path.join(dshHome, "scripts");
  mkdirp(scriptsDir);
  for (const f of ["trellis-matt-init.ps1", "sync-matt-skills.ps1", "patch-task-store.py", "win-fallback.mjs"]) {
    fs.copyFileSync(path.join(HERE, f), path.join(scriptsDir, f));
  }
  fs.copyFileSync(path.join(REPO, "workflows", "matt", "workflow.md"), path.join(scriptsDir, "trellis-workflow-matt.md"));
  mkdirp(binDir);
  const binCmd = path.join(binDir, "trellis-matt-init.cmd");
  const cmdText = binCmdText(binDir, scriptsDir);
  if (/[^\x00-\x7F]/.test(cmdText)) warn("generated .cmd contains non-ASCII paths; keep DSH_HOME and the bin dir on the same drive");
  fs.writeFileSync(binCmd, cmdText, "latin1");
  say("OK: " + scriptsDir);
  say("OK: " + binCmd);
  if (!(process.env.PATH || "").split(path.delimiter).includes(binDir)) {
    warn(binDir + " is not on PATH; run the .cmd by full path or add that directory to PATH");
  }

  step("5/7 DSH skill");
  const skillDir = path.join(dshHome, "skills", "trellis-matt-init");
  mkdirp(skillDir);
  fs.copyFileSync(path.join(REPO, "dsh", "skills", "trellis-matt-init", "SKILL.md"), path.join(skillDir, "SKILL.md"));
  say("OK: " + path.join(skillDir, "SKILL.md"));

  step("6/7 Trellis template patch");
  const npmRoot = run("npm", ["root", "-g"], { capture: true });
  const globalRoot = npmRoot.status === 0 ? npmRoot.stdout.split(/\r?\n/).pop().trim() : "";
  const taskStore = globalRoot
    ? path.join(globalRoot, "@mindfoldhq", "trellis", "dist", "templates", "trellis", "scripts", "common", "task_store.py")
    : null;
  if (taskStore && fs.existsSync(taskStore)) {
    if (run(python.cmd, [...python.args, path.join(HERE, "patch-task-store.py"), taskStore]).status !== 0) {
      warn("Template patch failed: " + taskStore);
    }
  } else {
    warn("task_store.py template not found: " + taskStore);
  }

  step("7/7 Verify");
  let fail = false;
  if (!which("trellis")) { warn("trellis is not available"); fail = true; }
  if (!checkSkills(dshHome, agentsHome)) { warn("Matt skills are incomplete"); fail = true; }
  if (!fs.existsSync(dstAgents)) { warn("Missing " + dstAgents); fail = true; }
  if (!fs.existsSync(binCmd)) { warn("Missing " + binCmd); fail = true; }
  if (!fs.existsSync(path.join(skillDir, "SKILL.md"))) { warn("Missing DSH skill"); fail = true; }
  if (!fs.existsSync(path.join(scriptsDir, "trellis-workflow-matt.md"))) { warn("Missing local workflow cache"); fail = true; }
  if (taskStore && fs.existsSync(taskStore)) {
    if (run(python.cmd, [...python.args, path.join(HERE, "patch-task-store.py"), "--check", taskStore], { capture: true }).status !== 0) {
      warn("Trellis template is not patched");
      fail = true;
    }
  }
  if (fail) die("Installation did not fully pass; fix the warnings above");

  say("");
  say("OK: environment installed");
  say("");
  say("Next:");
  say("  1. Initialize a project: cd <project>; trellis-matt-init.cmd -User <your-name>");
  say("  2. Or ask dsh: 'initialize this project with my workflow'");
  say("  3. Default source: gh:fanjinchi/trellisWorkflow (use -Source for a fork)");
  say("  4. Update Matt skills: node " + path.join(scriptsDir, "win-fallback.mjs") + " sync");
  return 0;
}

// ---------------------------------------------------------------- init

function printInitUsage() {
  say("Usage: node win-fallback.mjs init [options]");
  say("");
  say("  -User, --user <name>        developer name for .trellis/.developer (first init only)");
  say("  -Source, --source <gh:o/r>  workflow source (default gh:fanjinchi/trellisWorkflow)");
  say("  -Template, --template <id>  workflow template id (default matt)");
  say("  -Force, --force             switch the workflow of an already initialized project");
  say("  -Refresh, --refresh         ignore the local cache and fetch the latest workflow");
}

async function cmdInit(argv) {
  const flags = parseFlags(argv, new Set(["user", "u", "source", "s", "template", "t"]));
  if (flags.has("help") || flags.has("h")) { printInitUsage(); return 0; }

  const userGiven = flags.has("user") || flags.has("u");
  let user = flags.get("user") || flags.get("u") || process.env.TRELLIS_USER || "";
  const sourceGiven = flags.has("source") || flags.has("s");
  const source = flags.get("source") || flags.get("s") || process.env.TRELLIS_WORKFLOW_SOURCE || "gh:fanjinchi/trellisWorkflow";
  const template = flags.get("template") || flags.get("t") || process.env.TRELLIS_WORKFLOW_TEMPLATE || "matt";
  const force = flags.has("force") || flags.has("f");
  const refresh = flags.has("refresh") || flags.has("r");

  if (!which("trellis")) die("trellis not found; run install.cmd first");
  const python = findPython();
  if (!python) die(PYTHON_HINT);

  if (which("git")) {
    const r = run("git", ["rev-parse", "--show-toplevel"], { capture: true });
    if (r.status === 0 && r.stdout) process.chdir(r.stdout.split(/\r?\n/)[0].trim());
  }
  const projectRoot = process.cwd();

  if (!user && which("git")) {
    const r = run("git", ["config", "user.name"], { capture: true });
    if (r.status === 0) user = r.stdout.split(/\r?\n/)[0].trim();
  }
  if (!user) user = process.env.USERNAME || process.env.USER || "";
  user = user.trim() || "developer";

  if (!fs.existsSync(".git")) warn("Current directory is not a git repository; workflow Phase 3.4 needs commits");

  const devFile = path.join(".trellis", ".developer");
  if (fs.existsSync(devFile)) {
    const line = fs.readFileSync(devFile, "utf8").split(/\r?\n/).find((l) => l.startsWith("name="));
    if (line) {
      const currentDev = line.slice(5).trim();
      if (userGiven && currentDev !== user) {
        warn("Project already has developer '" + currentDev + "'; --user only applies on first init. Delete .trellis\\.developer to change it.");
      }
      user = currentDev;
    }
  }

  let rawBase = "";
  const gh = /^(?:gh|github):(.+)$/.exec(source);
  if (gh) {
    let repo = gh[1];
    let ref = "main";
    const hash = repo.indexOf("#");
    if (hash >= 0) { ref = repo.slice(hash + 1); repo = repo.slice(0, hash); }
    rawBase = "https://raw.githubusercontent.com/" + repo + "/" + ref;
  }

  const dshHome = process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  const localWorkflow = process.env.TRELLIS_WORKFLOW_CACHE || path.join(dshHome, "scripts", "trellis-workflow-matt.md");
  let sourceLabel = source;
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "trellis-matt-"));

  const installWorkflowFile = () => {
    fs.copyFileSync(path.join(tmp, "workflow.md"), path.join(".trellis", "workflow.md"));
    const hashPath = path.join(".trellis", ".template-hashes.json");
    if (fs.existsSync(hashPath)) {
      const data = JSON.parse(fs.readFileSync(hashPath, "utf8"));
      if (data.hashes) delete data.hashes[".trellis/workflow.md"];
      fs.writeFileSync(hashPath, JSON.stringify(data, null, 2) + "\n", "utf8");
    }
  };

  const cacheWorkflow = () => {
    if (sourceGiven || template !== "matt") return;
    const wf = path.join(".trellis", "workflow.md");
    if (!fs.existsSync(wf) || fs.statSync(wf).size === 0) return;
    try {
      mkdirp(path.dirname(localWorkflow));
      fs.copyFileSync(wf, localWorkflow);
    } catch { /* cache is best effort */ }
  };

  const useLocalWorkflow = () => {
    if (template !== "matt" || !hasCache(localWorkflow)) return false;
    fs.copyFileSync(localWorkflow, path.join(tmp, "workflow.md"));
    installWorkflowFile();
    sourceLabel = "local cache";
    say("Using local cached workflow: " + localWorkflow);
    return true;
  };

  const fetchWorkflowFile = async () => {
    if (!rawBase) return false;
    let wfPath = "";
    const index = path.join(tmp, "index.json");
    for (let i = 0; i < 3; i++) {
      try {
        await download(rawBase + "/index.json", index, 30000);
        const data = JSON.parse(fs.readFileSync(index, "utf8"));
        const entry = (data.templates || []).find((t) => t.id === template && t.type === "workflow");
        if (entry && entry.path) wfPath = entry.path;
        break;
      } catch {
        await sleep(2000);
      }
    }
    if (!wfPath) wfPath = "workflows/" + template + "/workflow.md";
    say("Fallback: downloading " + rawBase + "/" + wfPath);
    for (let i = 0; i < 3; i++) {
      try {
        await download(rawBase + "/" + wfPath, path.join(tmp, "workflow.md"), 60000);
        if (fs.statSync(path.join(tmp, "workflow.md")).size > 0) return true;
      } catch {
        await sleep(2000);
      }
    }
    return false;
  };

  const offlineInit = () => {
    say("trellis init (offline, local cache)");
    if (run("trellis", ["init", "--dsh", "--yes", "--user", user]).status !== 0) die("trellis init failed");
    fs.copyFileSync(localWorkflow, path.join(tmp, "workflow.md"));
    installWorkflowFile();
    sourceLabel = "local cache";
  };

  const initProject = async () => {
    if (!refresh && !sourceGiven && template === "matt" && hasCache(localWorkflow)) {
      offlineInit();
      return;
    }
    let ok = false;
    for (let i = 1; i <= 3; i++) {
      say("trellis init (attempt " + i + "/3, marketplace: " + source + ")");
      if (run("trellis", ["init", "--dsh", "--yes", "--user", user, "--workflow", template, "--workflow-source", source]).status === 0) {
        const wf = path.join(".trellis", "workflow.md");
        if (template !== "matt" || (fs.existsSync(wf) && fs.readFileSync(wf, "utf8").includes(MARKER))) {
          ok = true;
          break;
        }
        warn("init succeeded but workflow is not the Matt template");
      }
      warn("attempt " + i + " failed");
      await sleep(2000);
    }
    if (ok) { cacheWorkflow(); return; }

    warn("marketplace failed; falling back to native init + direct download");
    if (run("trellis", ["init", "--dsh", "--yes", "--user", user]).status !== 0) die("trellis init failed");
    if (await fetchWorkflowFile()) { installWorkflowFile(); cacheWorkflow(); return; }
    if (hasCache(localWorkflow)) {
      warn("network unavailable; using local cache");
      fs.copyFileSync(localWorkflow, path.join(tmp, "workflow.md"));
      installWorkflowFile();
      sourceLabel = "local cache";
      return;
    }
    die("Could not download workflow.md and no local cache exists.");
  };

  const switchWorkflow = async () => {
    if (!refresh && !sourceGiven && template === "matt" && hasCache(localWorkflow)) {
      useLocalWorkflow();
      return;
    }
    say("Switching workflow to " + template + " (marketplace: " + source + ")");
    if (run("trellis", ["workflow", "--marketplace", source, "--template", template, "--force"]).status === 0) {
      const wf = path.join(".trellis", "workflow.md");
      if (template !== "matt" || (fs.existsSync(wf) && fs.readFileSync(wf, "utf8").includes(MARKER))) {
        cacheWorkflow();
        return;
      }
      warn("switch succeeded but content is not the Matt template");
    }
    warn("marketplace switch failed; falling back to direct download");
    if (await fetchWorkflowFile()) { installWorkflowFile(); cacheWorkflow(); return; }
    if (hasCache(localWorkflow)) {
      warn("network unavailable; using local cache");
      fs.copyFileSync(localWorkflow, path.join(tmp, "workflow.md"));
      installWorkflowFile();
      sourceLabel = "local cache";
      return;
    }
    die("Could not download workflow.md and no local cache exists.");
  };

  const refreshDshEntry = () => {
    const f = path.join(".dsh", "skills", "trellis-start", "SKILL.md");
    if (!fs.existsSync(f)) return;
    const s = fs.readFileSync(f, "utf8");
    const next = s.replace("| Done coding / quality check | \u0060trellis-check\u0060 |", "| Done coding / quality check | \u0060code-review\u0060 |");
    if (next !== s) fs.writeFileSync(f, next, "utf8");
  };

  const patchTaskStore = () => {
    const target = path.join(".trellis", "scripts", "common", "task_store.py");
    if (!fs.existsSync(target)) return;
    const patch = path.join(HERE, "patch-task-store.py");
    if (!fs.existsSync(patch)) { warn("patch-task-store.py not found; skipping parent pointer patch"); return; }
    const r = run(python.cmd, [...python.args, patch, target], { capture: true });
    if (r.status !== 0) warn("parent pointer patch failed: " + target);
  };

  const verifyWorkflow = (expectMatt) => {
    const wf = path.join(".trellis", "workflow.md");
    if (!fs.existsSync(wf) || fs.statSync(wf).size === 0) die("workflow.md is empty; initialization failed");
    if (expectMatt && template === "matt" && !fs.readFileSync(wf, "utf8").includes(MARKER)) {
      die("workflow.md is not the Matt template (marker missing). Check --source / --template.");
    }
    const r = run(python.cmd, [...python.args, path.join(".trellis", "scripts", "get_context.py"), "--mode", "phase"], { capture: true });
    if (r.status !== 0) die("get_context.py cannot parse workflow.md; the template may be corrupt");
  };

  try {
    say("Project: " + projectRoot);
    say("Developer: " + user + " (first init only; --user sets .trellis\\.developer)");

    let expectMatt = false;
    const wf = path.join(".trellis", "workflow.md");
    if (fs.existsSync(wf) && !force) {
      say("Existing workflow kept (use --force to switch)");
      if (template === "matt" && !fs.readFileSync(wf, "utf8").includes(MARKER)) {
        warn("Current workflow is not the Matt version; use --force to switch");
      }
    } else {
      expectMatt = true;
      if (fs.existsSync(wf)) await switchWorkflow();
      else await initProject();
    }

    refreshDshEntry();
    patchTaskStore();
    verifyWorkflow(expectMatt);

    say("");
    say("OK: initialization complete");
    say("   .trellis/workflow.md -> " + template + " (source: " + sourceLabel + ")");
    say("   .trellis/.developer  -> " + user);
    say("   Next: start dsh in this directory; the global rule loads trellis-start first.");
    return 0;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// ------------------------------------------------------------ dispatch

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  switch (command) {
    case "install":
      return cmdInstall(rest);
    case "sync":
      return syncSkills({
        check: rest.some((a) => /^[-/]*(check|c)$/i.test(a)),
        dshHome: process.env.DSH_HOME || path.join(os.homedir(), ".dsh"),
        agentsHome: process.env.AGENTS_HOME || path.join(os.homedir(), ".agents"),
      }) ? 0 : 1;
    case "init":
      return await cmdInit(rest);
    default:
      say("Usage: node win-fallback.mjs <install|sync|init> [options]");
      say("  install  install the environment (same steps as install.ps1)");
      say("  sync     download Matt skills and refresh the DSH copies");
      say("  init     initialize the current project (same steps as trellis-matt-init.ps1)");
      return command ? 1 : 0;
  }
}

main().then(
  (code) => process.exit(code),
  (err) => {
    if (err instanceof Fail) {
      console.error("ERROR: " + err.message);
      process.exit(1);
    }
    console.error(err && err.stack ? err.stack : String(err));
    process.exit(1);
  },
);
