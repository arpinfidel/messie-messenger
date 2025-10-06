import { createClient } from 'matrix-js-sdk';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option('server-url', { type: 'string', demandOption: true })
    .option('username', { type: 'string', demandOption: true })
    .option('password', { type: 'string', demandOption: true })
    .option('device-id', { type: 'string', default: 'MESSIE_SAS_PEER' })
    .option('device-name', { type: 'string', default: 'Messie SAS Peer' })
    .option('state-dir', { type: 'string', demandOption: true })
    .help()
    .parse();

  const client = createClient({ baseUrl: argv['server-url'] });
  const res = await (client as any).login('m.login.password', {
    user: argv['username'],
    password: argv['password'],
    device_id: argv['device-id'],
    initial_device_display_name: argv['device-name'],
  } as any);

  if (!res?.user_id || !res?.access_token) {
    throw new Error('Login response missing user_id or access_token');
  }

  const outDir = argv['state-dir'];
  const outPath = path.join(outDir, 'access_token.json');
  await fs.promises.mkdir(outDir, { recursive: true });
  await fs.promises.writeFile(
    outPath,
    JSON.stringify({ user_id: res.user_id, device_id: res.device_id ?? argv['device-id'], access_token: res.access_token }, null, 2),
    { encoding: 'utf-8' },
  );
  console.log(`[token] wrote ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

