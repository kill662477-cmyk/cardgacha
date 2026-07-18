import { build } from 'esbuild';

await build({
  entryPoints: ['src/vendor/supabase-entry.js'],
  outfile: 'src/vendor/supabase.js',
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: ['es2022'],
  minify: true,
  legalComments: 'none',
});
console.log('browser vendor bundle synchronized');
