# Rails/Ruby Local API Documentation System

Local API documentation and compatibility checker for Rails and Ruby.
Fast, offline, grep-based lookups — no external websites needed.

## How Claude Code Should Use This System

### Priority Order (fastest to slowest):

1. **`bin/api-lookup`** — Single API check (~100ms, 1-3 lines of output)
2. **`bin/api-history`** — Track API across all indexed versions (~500ms)
3. **`bin/compat-check --api`** — Detailed version comparison with replacements
4. **`known-changes/*.tsv`** — Read curated breaking changes directly
5. **`bin/compat-check`** — Full version comparison
6. **Read source files** — Only when implementation details are needed

### Quick Lookup

```bash
# Does this API exist in a version?
bin/api-lookup rails 7.2.2.2 "where"
bin/api-lookup --exact rails 7.2.2.2 "ActiveRecord::QueryMethods#where"
bin/api-lookup ruby 3.4.7 "Hash#except"

# Track across all indexed versions
bin/api-history rails "update_attributes"
bin/api-history ruby "filter_map"
```

### Compatibility Check

```bash
# Single API comparison
bin/compat-check rails 5.0.7 7.2.2.2 --api "update_attributes"
bin/compat-check ruby 2.6.7 3.4.7 --api "Hash#except"

# Known breaking changes only
bin/compat-check rails 5.0.7 7.2.2.2 --known-only

# Scan a whole project
bin/compat-check rails 5.0.7 7.2.2.2 --project /path/to/app
```

### DO:
- Use `bin/api-lookup` for quick yes/no checks
- Use `bin/api-history` to see when an API was added/removed
- Use `known-changes/*.tsv` for well-known deprecations and replacements
- Cite file:line from the index in responses
- Read source only for implementation details or edge cases

### DO NOT:
- Fetch api.rubyonrails.org or ruby-doc.org
- Read entire source files when a lookup suffices
- Guess about API availability — always check the index

## Index Format

Each `.idx` file is pipe-delimited (one entry per line):

```
TYPE|QUALIFIED_NAME|SIGNATURE|FILE:LINE
```

Types: `class`, `module`, `imethod` (instance), `cmethod` (class/singleton), `attr_r`, `attr_w`, `attr_rw`

## Exit Codes (api-lookup)

- `0` — Found
- `1` — Not found
- `2` — Usage error or missing index

## Adding New Versions

```bash
bin/fetch-source rails 8.0.0
bin/build-index rails 8.0.0
# All tools automatically see the new version
```
