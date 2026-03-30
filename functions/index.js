const functions = require("firebase-functions");

function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

exports.uploadProfileImage = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    setCors(res);

    if (req.method === "OPTIONS") {
      return res.status(204).send("");
    }

    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method not allowed" });
    }

    try {
      const github = (functions.config().github || {});
      const owner = github.owner || "";
      const repo = github.repo || "";
      const branch = github.branch || "main";
      const folder = github.folder || "player_profiles";
      const token = github.token || "";

      if (!owner || !repo || !token) {
        return res.status(500).json({
          error: "GitHub config is missing on server",
        });
      }

      const username = String(req.body?.username || "player").trim();
      const contentBase64 = String(req.body?.contentBase64 || "").trim();

      if (!contentBase64) {
        return res.status(400).json({ error: "contentBase64 is required" });
      }

      const safeUsername = username
        ? username.replace(/[^a-zA-Z0-9_-]/g, "_")
        : "player";
      const filename = `${safeUsername}_${Date.now()}.jpg`;
      const repoPath = `${folder}/${filename}`;

      const apiUrl = `https://api.github.com/repos/${owner}/${repo}/contents/${repoPath}`;

      const ghRes = await fetch(apiUrl, {
        method: "PUT",
        headers: {
          "Authorization": `Bearer ${token}`,
          "Accept": "application/vnd.github+json",
          "Content-Type": "application/json",
          "X-GitHub-Api-Version": "2022-11-28",
        },
        body: JSON.stringify({
          message: `upload profile image for ${safeUsername}`,
          branch,
          content: contentBase64,
        }),
      });

      if (!ghRes.ok) {
        const detail = await ghRes.text();
        return res.status(ghRes.status).json({
          error: "GitHub upload failed",
          detail,
        });
      }

      const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${repoPath}`;
      return res.status(200).json({ url });
    } catch (error) {
      return res.status(500).json({
        error: "Unexpected server error",
        detail: String(error),
      });
    }
  });
