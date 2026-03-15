# rails-ruby-docs

Local API documentation and compatibility checker for Rails and Ruby version upgrades.

Fast, offline, grep-based lookups. No external documentation websites needed.

## Why

When upgrading Rails or Ruby, you need answers to:

- Was this API removed between versions?
- When was this method introduced?
- What replaced this deprecated method?
- Will my code break after upgrading?

Reading online docs or full source files is slow and expensive (especially for AI coding assistants that pay per token). This tool gives you the same answers in **under a second** with **1-5 lines of output**.

## How It Works

1. **Download** Rails/Ruby source code for the versions you care about
2. **Index** the source into compact, grep-friendly `.idx` files
3. **Query** the indexes with simple CLI tools

Index format (pipe-delimited, one entry per line):

```
TYPE|QUALIFIED_NAME|SIGNATURE|FILE:LINE
imethod|ActiveRecord::Persistence#save|save(**options, &block)|activerecord/lib/active_record/persistence.rb:392
```

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/rails-ruby-docs.git
cd rails-ruby-docs

# Setup with common upgrade versions
bin/setup --defaults
# Fetches Rails 5.0.7 + 7.2.2.2 and Ruby 2.6.7 + 3.4.7
# Then builds all indexes (~2 minutes)

# Or fetch specific versions
bin/fetch-source rails 6.1.7
bin/fetch-source ruby 3.2.0
bin/build-index all
```

### Requirements

- **bash** (macOS/Linux)
- **Ruby** 2.6+ (for the index builder and compatibility checker)
- **curl** (for downloading source tarballs)
- **grep** (ripgrep recommended but not required)

## Usage

### Look Up an API

```bash
# Partial search (finds all matches containing the query)
bin/api-lookup rails 7.2.2.2 "where"

# Exact match
bin/api-lookup --exact rails 7.2.2.2 "ActiveRecord::QueryMethods#where"

# Just file locations
bin/api-lookup --files ruby 3.4.7 "Hash#except"

# Count matches
bin/api-lookup --count rails 5.0.7 "before_filter"
```

**Output:**
```
FOUND in rails 7.2.2.2:
imethod|ActiveRecord::QueryMethods#where|where(*args)|activerecord/lib/active_record/relation/query_methods.rb:1011
```

Or simply:
```
NOT_FOUND: filter_map in ruby 2.6.7
```

### Track an API Across Versions

```bash
bin/api-history rails "update_attributes"
```

**Output:**
```
API HISTORY: update_attributes
Framework:   rails
  Known: removed -> use update (Deprecated in Rails 5, removed in Rails 6.1)
---
  5.0.7         FOUND  imethod  [update_attributes] ...
  6.1.7.10      NOT_FOUND
  7.2.2.2       NOT_FOUND
  8.0.1         NOT_FOUND
```

### Check Compatibility Between Versions

```bash
# Check a single API
bin/compat-check rails 5.0.7 7.2.2.2 --api "update_attributes"

# Show all known breaking changes
bin/compat-check rails 5.0.7 7.2.2.2 --known-only

# Check Ruby compatibility
bin/compat-check ruby 2.6.7 3.4.7 --api "Hash#except"

# Scan an entire project
bin/compat-check rails 5.0.7 7.2.2.2 --project /path/to/your/app
```

**Output:**
```
============================================================
COMPATIBILITY REPORT: rails 5.0.7 -> 7.2.2.2
============================================================

KNOWN BREAKING CHANGES (2):
----------------------------------------
  update_attributes
    Status:      removed
    Replacement: update
    Note:        Deprecated in Rails 5, removed in Rails 6.1

REMOVED APIs (in 5.0.7, not in 7.2.2.2): 1
----------------------------------------
  update_attributes
    Was at: activerecord/lib/active_record/persistence.rb:279
```

### Scan a Project

```bash
bin/scan-project /path/to/your/rails/app
bin/scan-project /path/to/your/rails/app --rails-version 5.0.7
```

## Adding Versions

```bash
# Fetch and index a new version
bin/fetch-source rails 8.0.1
bin/build-index rails 8.0.1

# All tools automatically pick up new versions
bin/api-history rails "some_method"  # now includes 8.0.1
```

### Supported Version Ranges

Any released version with a GitHub tag:

- **Rails**: Any tag from [github.com/rails/rails/tags](https://github.com/rails/rails/tags) (e.g., 4.2.11, 5.0.7, 6.1.7, 7.0.8, 7.2.2.2, 8.0.1)
- **Ruby**: Any tag from [github.com/ruby/ruby/tags](https://github.com/ruby/ruby/tags) (e.g., 2.6.7, 2.7.8, 3.0.7, 3.1.6, 3.2.6, 3.3.6, 3.4.2)

## Tools Reference

| Tool | Purpose | Speed |
|------|---------|-------|
| `bin/api-lookup` | Single API check | ~100ms |
| `bin/api-history` | API across all versions | ~500ms |
| `bin/compat-check` | Version comparison | ~1-10s |
| `bin/scan-project` | Project API scanner | ~2-10s |
| `bin/fetch-source` | Download source code | ~30s |
| `bin/build-index` | Generate API index | ~5-30s |
| `bin/setup` | First-time setup | ~2min |

## Known Breaking Changes

The `known-changes/` directory contains curated TSV files with well-known breaking changes that provide context beyond what source parsing can detect:

- `rails-5-to-7.tsv` — Rails 5.x to 7.x removals, deprecations, and behavior changes
- `ruby-2.6-to-3.x.tsv` — Ruby 2.6 to 3.x keyword argument changes, removed methods, new features

Format:
```
API_NAME	STATUS	REPLACEMENT	NOTE
```

Contributions welcome! Add entries for version ranges you've dealt with.

## Claude Code Integration

This system is designed for use with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and similar AI coding assistants.

See [CLAUDE.md](CLAUDE.md) for integration instructions. When this repo is cloned to your machine, Claude Code automatically reads `CLAUDE.md` and knows to use the local tools instead of fetching external documentation.

**Priority order** (fastest to slowest):

1. `bin/api-lookup` — quick yes/no check (~100ms, 1-3 lines)
2. `bin/api-history` — version timeline (~500ms)
3. `bin/compat-check --api` — detailed comparison with replacements
4. `known-changes/*.tsv` — curated breaking changes
5. Read source files — only when implementation details matter

## Architecture

```
rails-ruby-docs/
├── bin/                    # CLI tools
│   ├── setup              # One-time setup
│   ├── fetch-source       # Download source by version
│   ├── build-index        # Parse source -> .idx files
│   ├── api-lookup         # Fast grep-based lookup
│   ├── api-history        # Track API across versions
│   ├── scan-project       # Scan Rails project for APIs
│   └── compat-check       # Compare versions
├── lib/
│   └── source_parser.rb   # Ruby + C source parser
├── indexes/               # Generated .idx files (git-ignored)
│   ├── rails/
│   └── ruby/
├── rails-src/             # Downloaded source (git-ignored)
├── ruby-src/              # Downloaded source (git-ignored)
├── known-changes/         # Curated breaking changes
├── CLAUDE.md              # AI assistant integration guide
└── README.md
```

### What the Parser Captures

**From Ruby (`.rb`) files:**
- `class` / `module` definitions with full namespace resolution
- `def` / `def self.` methods (instance + class methods)
- `class << self` eigenclass methods
- `attr_reader` / `attr_writer` / `attr_accessor`
- `alias` / `alias_method`
- `delegate` methods

**From C (`.c`) files** (Ruby core):
- `rb_define_method` / `rb_define_singleton_method`
- `rb_define_module_function` / `rb_define_global_function`
- `rb_define_class` / `rb_define_module` (with parent resolution)

### Typical Index Sizes

| Version | Entries | Size |
|---------|---------|------|
| Rails 5.0.7 | ~12,000 | 1.5 MB |
| Rails 7.2.2 | ~19,000 | 2.4 MB |
| Ruby 2.6.7 | ~21,000 | 1.5 MB |
| Ruby 3.4.x | ~85,000 | 6.7 MB |

## Contributing

1. Fork the repo
2. Add known-changes entries for version ranges you've worked with
3. Improve the parser to capture more patterns
4. Submit a PR

### Adding Known Changes

Edit files in `known-changes/` following the TSV format:

```
API_NAME\tSTATUS\tREPLACEMENT\tNOTE
```

Status values: `removed`, `deprecated`, `changed`, `renamed`, `moved`, `added`

## License

MIT
