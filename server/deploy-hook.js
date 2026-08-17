#!/usr/bin/env node
// Deploy webhook — listens for CI/CD triggers and updates the game
// Runs as a separate service on the server

const http = require("http");
const crypto = require("crypto");
const { execSync } = require("child_process");

const PORT = process.env.HOOK_PORT || 9098;
const SECRET = process.env.DEPLOY_SECRET || "";
const DEPLOY_PATH = process.env.DEPLOY_PATH || "/home/curlyphries/paintball";

// Fail closed — an unset secret must never mean "no auth required"
if (!SECRET) {
  console.error("[Deploy] FATAL: DEPLOY_SECRET is not set. Refusing to start.");
  process.exit(1);
}

function authOk(header) {
  const expected = Buffer.from(`Bearer ${SECRET}`);
  const provided = Buffer.from(String(header || ""));
  // timingSafeEqual requires equal lengths; length leak is fine here
  if (provided.length !== expected.length) return false;
  return crypto.timingSafeEqual(provided, expected);
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405);
    res.end("Method not allowed");
    return;
  }

  // Verify auth
  if (!authOk(req.headers.authorization)) {
    res.writeHead(403);
    res.end("Forbidden");
    console.log(`[Deploy] Rejected: bad auth from ${req.socket.remoteAddress}`);
    return;
  }

  let body = "";
  let bodySize = 0;
  const MAX_BODY = 4096; // 4KB max
  req.on("data", (chunk) => {
    bodySize += chunk.length;
    if (bodySize > MAX_BODY) {
      res.writeHead(413);
      res.end("Payload too large");
      req.destroy();
      return;
    }
    body += chunk;
  });
  req.on("end", () => {
    console.log(`[Deploy] Triggered at ${new Date().toISOString()}`);

    try {
      // Run every step with cwd set instead of interpolating the path into
      // shell strings (spaces/metacharacters in DEPLOY_PATH stay harmless)
      // Pull latest code
      execSync("git pull origin main", { stdio: "inherit", cwd: DEPLOY_PATH });

      // Update relay server deps
      execSync("npm ci --production", { stdio: "inherit", cwd: `${DEPLOY_PATH}/server` });

      // Download latest HTML5 export artifact from GitHub Actions
      execSync("rm -rf export/web && mkdir -p export/web", { stdio: "inherit", cwd: DEPLOY_PATH });
      execSync(
        "gh run download --repo curlyphries/paintball --name paintball-web --dir export/web/",
        { stdio: "inherit", cwd: DEPLOY_PATH }
      );

      // Restart relay
      execSync("sudo systemctl restart paintball-relay", { stdio: "inherit" });

      console.log("[Deploy] Success!");
      res.writeHead(200);
      res.end("Deployed");
    } catch (err) {
      console.error("[Deploy] Failed:", err.message);
      res.writeHead(500);
      res.end("Deploy failed: " + err.message);
    }
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[Deploy] Webhook listening on http://127.0.0.1:${PORT}`);
});
