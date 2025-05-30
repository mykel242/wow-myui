# MyUI - World of Warcraft Addon

## Development Setup

### Automatic Version Updates

This repo includes Git hooks that automatically update the version number in `MyUI.lua` based on your current Git branch and commit hash.

#### Installation

**Linux/Mac:**
```bash
./hooks/install-hooks.sh
```

**Windows:**
```batch
hooks\install-hooks.bat
```

**Manual Installation:**
```bash
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

#### How it Works

Every time you commit, the pre-commit hook will:
1. Get your current Git branch name
2. Get the short commit hash
3. Update `addon.VERSION` to `branch-hash` format
4. Update `addon.BUILD_DATE` to current timestamp
5. Add the updated file to your commit

#### Version Format Examples
- `main-a1b2c3d` (main branch, commit a1b2c3d)
- `feature-absorb-x9y8z7` (feature branch)
- `dev-m4n5o6` (development branch)

This ensures you always know exactly which code version is running in WoW!
----
Note -

Adding New Spells:
If a new absorb spell is missed, you just need to add it to one of the arrays:
lua-- For pattern-based (recommended):
"newpattern"  -- to absorbPatterns

-- For specific names:
"exact spell name"  -- to specificAbsorbSpells
Coverage Estimate:

~95% of absorb spells should be caught automatically
Only truly unique names would need manual addition.
