#!/usr/bin/env node

import fetch from 'node-fetch';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

type Args = {
  serverUrl: string;
  timeoutMs: number;
};

function normalizeBase(url: string): string {
  // Ensure no trailing slash
  return url.replace(/\/$/, '');
}

async function main() {
  const argv = (await yargs(hideBin(process.argv))
    .usage('Usage: $0 --server-url <http://host:port> [--timeout-ms 5000]')
    .options({
      'server-url': {
        type: 'string',
        describe: 'Base homeserver URL',
        demandOption: true,
      },
      'timeout-ms': {
        type: 'number',
        default: 5000,
        describe: 'HTTP timeout in milliseconds',
      },
    })
    .strict()
    .parse()) as unknown as Args;

  const base = normalizeBase(argv.serverUrl);
  const url = `${base}/_matrix/client/unstable/org.matrix.simplified_msc3575/sync`;

  process.stdout.write(`Probing Simplified Sliding Sync endpoint at ${url} ...\n`);
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), argv.timeoutMs);
    const res = await fetch(url, { method: 'GET', signal: controller.signal });
    clearTimeout(timer);

    // Endpoint presence is indicated by any non-404. For unauthenticated GETs,
    // common codes are 401 (Unauthorized) or 405 (Method Not Allowed). A 200
    // is also acceptable if the server permits GET/unauthenticated access.
    if (res.status === 404) {
      process.stderr.write(`FAILED: got 404 Not Found — endpoint likely disabled.\n`);
      process.exit(2);
    }

    process.stdout.write(`OK: endpoint reachable (HTTP ${res.status}).\n`);
    process.exit(0);
  } catch (e: any) {
    process.stderr.write(`ERROR: request failed: ${e?.message || String(e)}\n`);
    process.exit(3);
  }
}

main();

