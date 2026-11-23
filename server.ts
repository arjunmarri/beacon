import { ZipArchive } from 'archiver';
import express from 'express';
import type { Request, Response } from 'express';
import fs from 'node:fs';
import path from 'node:path';

const PORT = Number(process.env.PORT || 3000);
const ROOT_DIR = process.cwd();
const INDEX_HTML_PATH = path.join(ROOT_DIR, 'index.html');
const SWIFT_APP_DIR = path.join(ROOT_DIR, 'swift-app', 'BeaconMac');
const DOCS_DIR = path.join(ROOT_DIR, 'docs');

const ROOT_FILES = ['README.md', 'LICENSE'];

const app = express();

app.get('/api/download-swift', async (_req: Request, res: Response) => {
  if (!fs.existsSync(SWIFT_APP_DIR)) {
    res.status(404).json({ error: 'Swift Xcode project directory not found.' });
    return;
  }

  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', 'attachment; filename="BeaconMac-Swift-Xcode-Project.zip"');

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

  walkIntoZip(SWIFT_APP_DIR, 'BeaconMac');

  if (fs.existsSync(DOCS_DIR)) {
    walkIntoZip(DOCS_DIR, 'BeaconMac/docs');
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
  console.log(`BeaconMac preview server listening on http://0.0.0.0:${PORT}`);
});
