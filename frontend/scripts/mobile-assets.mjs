#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { access } from 'node:fs/promises';
import { mkdir, copyFile, rm, readdir } from 'node:fs/promises';
import { constants } from 'node:fs';
import { spawn } from 'node:child_process';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, '..');
const publicLogo = resolve(projectRoot, 'public/messie-logo.svg');
const assetsDir = resolve(projectRoot, 'assets');
const assetsLogo = resolve(assetsDir, 'logo.svg');

async function ensureLogoExists() {
  try {
    await access(publicLogo, constants.R_OK);
  } catch (error) {
    throw new Error(
      `Cannot read ${publicLogo}. Ensure the shared logo exists before generating mobile assets.`
    );
  }
}

function runCommand(command, args, options) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      ...options,
    });

    child.on('error', rejectPromise);
    child.on('close', (code) => {
      if (code === 0) {
        resolvePromise();
      } else {
        rejectPromise(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}

async function cleanupAssets() {
  await rm(assetsLogo, { force: true });
  try {
    const entries = await readdir(assetsDir);
    if (entries.length === 0) {
      await rm(assetsDir, { recursive: true, force: true });
    }
  } catch (error) {
    // Ignore errors when removing the assets directory. It may not exist or may contain other files.
  }
}

async function main() {
  await ensureLogoExists();
  await mkdir(assetsDir, { recursive: true });
  await copyFile(publicLogo, assetsLogo);

  try {
    await runCommand('npx', ['--yes', '@capacitor/assets@latest', 'generate', '--ios', '--android'], {
      cwd: projectRoot,
    });
  } finally {
    await cleanupAssets();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
