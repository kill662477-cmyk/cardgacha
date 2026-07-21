const fs = require('fs');
const path = require('path');
const testsDir = path.join(process.cwd(), 'tests');
const migrationsDir = path.join(process.cwd(), 'supabase', 'migrations');
const migrations = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql'));

fs.readdirSync(testsDir).forEach(file => {
  if (!file.endsWith('.test.js')) return;
  const filePath = path.join(testsDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  let changed = false;
  
  content = content.replace(/['`]\.\.\/supabase\/(renewal_migration_\d+_[a-z0-9_]+\.sql)['`]/g, (match, p1) => {
    const realMigration = migrations.find(m => m.includes(p1));
    if (realMigration) {
      changed = true;
      return match[0] + '../supabase/migrations/' + realMigration + match[0];
    }
    return match;
  });

  // Also fix tests/renewal-repository-hygiene.test.js
  content = content.replace(/['`]supabase\/(renewal_migration_\d+_[a-z0-9_]+\.sql)['`]/g, (match, p1) => {
    const realMigration = migrations.find(m => m.includes(p1));
    if (realMigration) {
      changed = true;
      return match[0] + 'supabase/migrations/' + realMigration + match[0];
    }
    return match;
  });

  content = content.replace(/at\('supabase'\)/g, () => {
    changed = true;
    return "at('supabase/migrations')";
  });

  if (changed) {
    fs.writeFileSync(filePath, content);
    console.log('Updated', file);
  }
});
