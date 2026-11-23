import { ZipArchive } from 'archiver';
import express from 'express';
import type { Request, Response } from 'express';
import fs from 'node:fs';
import path from 'node:path';

interface ReleaseEntry {
  version: string;
  build: number;
  date: string;
  minMacOS: string;
  architecture: string;
  dmgFilename: string;
  githubDownloadUrl: string;
  sha256: string | null;
  sizeBytes: number | null;
  notes: string[];
}

interface ReleasesManifest {
  latest: string;
  githubRepo: string;
  releases: ReleaseEntry[];
}

interface GitHubReleaseAsset {
  name: string;
  size: number;
  browser_download_url: string;
}

interface GitHubReleaseRecord {
  tag_name: string;
  published_at?: string;
  html_url?: string;
  assets?: GitHubReleaseAsset[];
}

const PORT = Number(process.env.PORT || 3000);
const ROOT_DIR = process.cwd();
const INDEX_HTML_PATH = path.join(ROOT_DIR, 'index.html');
const SWIFT_APP_DIR = path.join(ROOT_DIR, 'swift-app', 'BeaconMac');
const DOCS_DIR = path.join(ROOT_DIR, 'docs');
const RELEASES_DIR = path.join(ROOT_DIR, 'releases');
const RELEASES_MANIFEST_PATH = path.join(RELEASES_DIR, 'releases.json');
const VERSION_FILE_PATH = path.join(ROOT_DIR, 'version.json');
const WORKFLOWS_DIR = path.join(ROOT_DIR, '.github');

const ROOT_FILES = ['README.md', 'LICENSE', 'CHANGELOG.md', 'version.json'];
const SEMVER_RE = /^\d+\.\d+\.\d+$/;

let ghCache: { fetchedAt: number; assetsByVersion: Map<string, { url: string; size: number; name: string }> } = {
  fetchedAt: 0,
  assetsByVersion: new Map(),
};

function loadManifest(): ReleasesManifest {
  try {
    if (fs.existsSync(RELEASES_MANIFEST_PATH)) {
      return JSON.parse(fs.readFileSync(RELEASES_MANIFEST_PATH, 'utf8')) as ReleasesManifest;
    }
  } catch {
    // fall through to version.json fallback
  }

  let version = '1.0.0';
  let build = 1;
  let githubRepo = 'arjunmarri/beacon';
  if (fs.existsSync(VERSION_FILE_PATH)) {
    try {
      const v = JSON.parse(fs.readFileSync(VERSION_FILE_PATH, 'utf8'));
      version = String(v.version || version);
      build = Number(v.build || build);
      githubRepo = String(v.githubRepo || githubRepo);
    } catch {
      // ignore
    }
  }

  const dmgFilename = `BeaconMac-${version}-universal.dmg`;
  return {
    latest: version,
    githubRepo,
    releases: [
      {
        version,
        build,
        date: new Date().toISOString().slice(0, 10),
        minMacOS: '14.0',
        architecture: 'Universal (Apple Silicon + Intel)',
        dmgFilename,
        githubDownloadUrl: `https://github.com/${githubRepo}/releases/download/v${version}/${dmgFilename}`,
        sha256: null,
        sizeBytes: null,
        notes: [],
      },
    ],
  };
}

function getLocalDmgPath(dmgFilename: string): string | null {
  const safeName = path.basename(dmgFilename);
  if (!safeName.endsWith('.dmg')) return null;
  const candidate = path.join(RELEASES_DIR, safeName);
  if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
    return candidate;
  }
  return null;
}

function readLocalSha256(dmgPath: string): string | null {
  const shaFile = `${dmgPath}.sha256`;
  if (!fs.existsSync(shaFile)) return null;
  try {
    const raw = fs.readFileSync(shaFile, 'utf8').trim();
    return raw.split(/\s+/)[0] || null;
  } catch {
    return null;
  }
}

async function fetchGitHubDmgAssets(githubRepo: string): Promise<Map<string, { url: string; size: number; name: string }>> {
  const now = Date.now();
  if (now - ghCache.fetchedAt < 60_000) {
    return ghCache.assetsByVersion;
  }

  const nextMap = new Map<string, { url: string; size: number; name: string }>();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2500);

  try {
    const res = await fetch(`https://api.github.com/repos/${githubRepo}/releases?per_page=15`, {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'BeaconMac-Release-Portal/1.0',
      },
      signal: controller.signal,
    });
    if (res.ok) {
      const list = (await res.json()) as GitHubReleaseRecord[];
      for (const rel of list) {
        const ver = String(rel.tag_name || '').replace(/^v/, '');
        const dmgAsset = (rel.assets || []).find((a) => a.name.toLowerCase().endsWith('.dmg'));
        if (ver && dmgAsset) {
          nextMap.set(ver, {
            url: dmgAsset.browser_download_url,
            size: dmgAsset.size,
            name: dmgAsset.name,
          });
        }
      }
    }
  } catch {
    // GitHub unreachable or no releases published yet
  } finally {
    clearTimeout(timeout);
  }

  ghCache = { fetchedAt: now, assetsByVersion: nextMap };
  return nextMap;
}

const app = express();
const ASSETS_IMAGES_DIR = path.join(ROOT_DIR, 'src', 'assets', 'images');

if (fs.existsSync(ASSETS_IMAGES_DIR)) {
  app.use(
    '/src/assets/images',
    express.static(ASSETS_IMAGES_DIR, {
      maxAge: '7d',
      immutable: true,
    })
  );
}

app.get('/api/releases', async (_req: Request, res: Response) => {
  const manifest = loadManifest();
  const ghAssets = await fetchGitHubDmgAssets(manifest.githubRepo);

  const enriched = manifest.releases.map((rel) => {
    const localPath = getLocalDmgPath(rel.dmgFilename);
    const ghAsset = ghAssets.get(rel.version);
    const localSize = localPath ? fs.statSync(localPath).size : null;
    const localSha = localPath ? readLocalSha256(localPath) : null;
    const dmgAvailable = Boolean(localPath || ghAsset);

    return {
      ...rel,
      dmgAvailable,
      source: localPath ? 'local' : ghAsset ? 'github' : 'pending_macos_build',
      downloadUrl: `/download/dmg/${rel.version}`,
      sizeBytes: localSize ?? ghAsset?.size ?? rel.sizeBytes,
      sha256: localSha ?? rel.sha256,
    };
  });

  // Also include any GitHub-published DMG versions not yet listed in releases.json
  for (const [ver, asset] of ghAssets.entries()) {
    if (!enriched.some((r) => r.version === ver)) {
      enriched.unshift({
        version: ver,
        build: 0,
        date: '',
        minMacOS: '14.0',
        architecture: 'Universal (Apple Silicon + Intel)',
        dmgFilename: asset.name,
        githubDownloadUrl: asset.url,
        sha256: null,
        sizeBytes: asset.size,
        notes: [],
        dmgAvailable: true,
        source: 'github',
        downloadUrl: `/download/dmg/${ver}`,
      });
    }
  }

  const latestRelease = enriched.find((r) => r.version === manifest.latest) ?? enriched[0] ?? null;

  res.json({
    appName: 'BeaconMac',
    latest: latestRelease?.version ?? manifest.latest,
    githubRepo: manifest.githubRepo,
    dmgReady: Boolean(latestRelease?.dmgAvailable),
    latestDownloadUrl: latestRelease ? `/download/dmg/${latestRelease.version}` : '/download/dmg',
    releases: enriched,
  });
});

async function handleDmgDownload(req: Request, res: Response) {
  const manifest = loadManifest();
  const requestedVersion = req.params.version ? String(req.params.version) : manifest.latest;

  if (!SEMVER_RE.test(requestedVersion)) {
    res.status(400).json({ error: 'Invalid version format. Expected MAJOR.MINOR.PATCH (e.g. 1.0.0).' });
    return;
  }

  const entry = manifest.releases.find((r) => r.version === requestedVersion);
  const dmgFilename = entry?.dmgFilename || `BeaconMac-${requestedVersion}-universal.dmg`;

  // 1. Direct local DMG file in /releases/
  const localPath = getLocalDmgPath(dmgFilename);
  if (localPath) {
    res.setHeader('Content-Type', 'application/x-apple-diskimage');
    res.setHeader('Content-Disposition', `attachment; filename="${path.basename(localPath)}"`);
    res.sendFile(localPath);
    return;
  }

  // 2. Direct redirect to published GitHub Release DMG asset
  const ghAssets = await fetchGitHubDmgAssets(manifest.githubRepo);
  const ghAsset = ghAssets.get(requestedVersion);
  if (ghAsset) {
    res.redirect(302, ghAsset.url);
    return;
  }

  // 3. Honest response if no macOS binary DMG has been compiled/published for this version yet
  res.status(404).json({
    error: `BeaconMac v${requestedVersion} DMG has not been compiled on macOS yet.`,
    version: requestedVersion,
    expectedFilename: dmgFilename,
    howToBuildOnMac: './swift-app/BeaconMac/Scripts/build-dmg.sh',
    howToAutoReleaseViaGitHubActions: `git tag v${requestedVersion} && git push origin v${requestedVersion}`,
    githubReleasesPage: `https://github.com/${manifest.githubRepo}/releases`,
    sourceZipUrl: '/api/download-swift',
  });
}

app.get('/download/dmg', handleDmgDownload);
app.get('/download/dmg/:version', handleDmgDownload);

app.get('/api/download-swift', async (_req: Request, res: Response) => {
  if (!fs.existsSync(SWIFT_APP_DIR)) {
    res.status(404).json({ error: 'Swift Xcode project directory not found.' });
    return;
  }

  const manifest = loadManifest();
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader(
    'Content-Disposition',
    `attachment; filename="BeaconMac-${manifest.latest}-Swift-Source.zip"`
  );

  const archive = new ZipArchive({ zlib: { level: 9 } });
  archive.on('error', () => {
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to package Swift Xcode project.' });
    }
  });

  archive.pipe(res);

  const walkIntoZip = (dir: string, zipPrefix: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const absPath = path.join(dir, entry.name);
      const zipPath = `${zipPrefix}/${entry.name}`;
      if (entry.isDirectory()) {
        walkIntoZip(absPath, zipPath);
      } else {
        archive.file(absPath, {
          name: zipPath,
          mode: entry.name.endsWith('.sh') ? 0o755 : 0o644,
        });
      }
    }
  };

  walkIntoZip(SWIFT_APP_DIR, 'BeaconMac/swift-app/BeaconMac');

  if (fs.existsSync(DOCS_DIR)) {
    walkIntoZip(DOCS_DIR, 'BeaconMac/docs');
  }

  if (fs.existsSync(RELEASES_MANIFEST_PATH)) {
    archive.file(RELEASES_MANIFEST_PATH, { name: 'BeaconMac/releases/releases.json', mode: 0o644 });
  }

  if (fs.existsSync(WORKFLOWS_DIR)) {
    walkIntoZip(WORKFLOWS_DIR, 'BeaconMac/.github');
  }

  for (const filename of ROOT_FILES) {
    const absPath = path.join(ROOT_DIR, filename);
    if (fs.existsSync(absPath)) {
      archive.file(absPath, { name: `BeaconMac/${filename}`, mode: 0o644 });
    }
  }

  await archive.finalize();
});

app.get('*', (_req: Request, res: Response) => {
  res.sendFile(INDEX_HTML_PATH);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`BeaconMac release portal listening on http://0.0.0.0:${PORT}`);
});
