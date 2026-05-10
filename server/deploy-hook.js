#!/usr/bin/env node
// Deploy webhook — listens for CI/CD triggers and updates the game
// Runs as a separate service on the server

const http = require("http");
const { execSync } = require("child_process");

const PORT = process.env.HOOK_PORT || 9098;
const SECRET = process.env.DEPLOY_SECRET || "";
const DEPLOY_PATH = process.env.DEPLOY_PATH || "/home/curlyphries/paintball";

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405);
    res.end("Method not allowed");
    return;
  }

  // Verify auth
  const auth = req.headers.authorization || "";
  if (SECRET && auth !== `Bearer ${SECRET}`) {
    res.writeHead(403);
    res.end("Forbidden");
    console.log(`[Deploy] Rejected: bad auth from ${req.socket.remoteAddress}`);
    return;
  }

  let body = "";
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", () => {
    console.log(`[Deploy] Triggered at ${new Date().toISOString()}`);

    try {
      // Pull latest code
      execSync(`cd ${DEPLOY_PATH} && git pull origin main`, { stdio: "inherit" });

      // Update relay server deps
      execSync(`cd ${DEPLOY_PATH}/server && npm ci --production`, { stdio: "inherit" });

      // Download latest HTML5 export artifact from GitHub
      // Uses gh CLI to grab the latest artifact
      execSync(
        `cd ${DEPLOY_PATH} && gh run download --repo curlyphries/paintball --name paintball-web --dir export/web/ 2>/dev/null || echo "Artifact download skipped (may need manual export)"`,
        { stdio: "inherit" }
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
