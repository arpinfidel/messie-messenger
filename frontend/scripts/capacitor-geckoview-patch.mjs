import { existsSync } from 'node:fs';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(new URL(import.meta.url)));
const projectRoot = path.resolve(scriptDir, '..');
const androidDir = path.join(projectRoot, 'android');
const MOZILLA_REPO_LINE = '        maven { url "https://maven.mozilla.org/maven2/" }';

async function updateFile(filePath, transform) {
  if (!existsSync(filePath)) {
    return false;
  }

  const original = await readFile(filePath, 'utf8');
  const updated = transform(original);

  if (updated == null || updated === original) {
    return false;
  }

  await writeFile(filePath, updated, 'utf8');
  return true;
}

function addMozillaRepository(content) {
  if (content.includes('maven.mozilla.org')) {
    return null;
  }

  return content.replace(/(mavenCentral\(\)[^\S\r\n]*\r?\n)/g, `$1${MOZILLA_REPO_LINE}\n`);
}

function ensureJava17(content) {
  if (content.includes('JavaVersion.VERSION_17')) {
    return null;
  }

  if (!content.includes('JavaVersion.VERSION_11')) {
    return null;
  }

  return content.replace(/JavaVersion\.VERSION_11/g, 'JavaVersion.VERSION_17');
}

async function main() {
  const touched = [];

  const buildGradle = path.join(androidDir, 'build.gradle');
  if (await updateFile(buildGradle, addMozillaRepository)) {
    touched.push(path.relative(projectRoot, buildGradle));
  }

  const appCapacitorGradle = path.join(androidDir, 'app', 'capacitor.build.gradle');
  if (await updateFile(appCapacitorGradle, ensureJava17)) {
    touched.push(path.relative(projectRoot, appCapacitorGradle));
  }

  if (touched.length) {
    console.log(`Applied GeckoView patches to: ${touched.join(', ')}`);
  } else {
    console.log('GeckoView patch: no changes needed.');
  }
}

main().catch((error) => {
  console.error('Failed to apply GeckoView patch:', error);
  process.exit(1);
});
