# apidex — Claude Code Integration

Local API index and compatibility checker for Rails and Ruby.
Fast, offline lookups — no external websites needed.

## How Claude Code Should Use This System

### Priority Order (fastest to slowest):

1. **`apidex lookup`** — Single API check (~100ms, 1-3 lines of output)
2. **`apidex history`** — Track API across all indexed versions (~500ms)
3. **`apidex check --api`** — Detailed version comparison with replacements
4. **`known-changes/*.tsv`** — Read curated breaking changes directly
5. **`apidex check`** — Full version comparison
6. **Read source files** — Only when implementation details are needed

### Quick Lookup

```bash
# Does this API exist in a version?
apidex lookup rails 7.2.2.2 "where"
apidex lookup --exact rails 7.2.2.2 "ActiveRecord::QueryMethods#where"
apidex lookup ruby 3.4.7 "Hash#except"

# Track across all indexed versions
apidex history rails "update_attributes"
apidex history ruby "filter_map"
```

### Compatibility Check

```bash
# Single API comparison
apidex check rails 5.0.7 7.2.2.2 --api "update_attributes"
apidex check ruby 2.6.7 3.4.7 --api "Hash#except"

# Known breaking changes only
apidex check rails 5.0.7 7.2.2.2 --known-only

# Scan a whole project
apidex check rails 5.0.7 7.2.2.2 --project /path/to/app
```

### DO:
- Use `apidex lookup` for quick yes/no checks
- Use `apidex history` to see when an API was added/removed
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

## Exit Codes (lookup)

- `0` — Found
- `1` — Not found
- `2` — Usage error or missing index

## Adding New Versions

```bash
apidex fetch rails 8.0.0
apidex build rails 8.0.0
# All tools automatically see the new version
```
