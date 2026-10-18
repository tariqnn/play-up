const path = require('node:path');
const {spawnSync} = require('node:child_process');

const functionsDirectory = path.resolve(__dirname, '..');
const typescriptCli = path.join(
  functionsDirectory,
  'node_modules',
  'typescript',
  'bin',
  'tsc',
);

const result = spawnSync(process.execPath, [typescriptCli], {
  cwd: functionsDirectory,
  stdio: 'inherit',
});

if (result.error) {
  console.error(`Could not run the Functions build: ${result.error.message}`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
