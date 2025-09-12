# Nova

Nova is a **package manager and build environment tool for Free Pascal projects**. It helps you manage dependencies, ensure reproducible builds, and streamline your development workflow.

With Nova, you can:

* Install and update Free Pascal packages from remote sources.
* Ensure consistent and reproducible builds across machines and pipelines — Nova is particularly well-suited for **CI/CD environments**.
* Automatically generate and update your `fpc.cfg` configuration.

## Installation

You can install Nova in two ways:

1. **Download a binary release**

   * Visit the [Nova releases page](https://github.com/daar/nova/releases) and download and install the appropriate binary for your platform.

2. **Update to the latest version**

   * Once installed, you can always upgrade Nova by running:

     ```bash
     nova self-update
     ```

## Workflow Overview

Nova provides **four main workflow commands**. Each command affects the `nova.json`, `nova.lock`, or the `vendor` folder in different ways. Understanding this relationship is key to managing your development environment.

| Command   | `nova.json`                  | `nova.lock`                     | `vendor`                              | Notes                          |
|-----------|------------------------------|---------------------------------|---------------------------------------|--------------------------------|
| `require` | Adds package with constraint | Resolves + updates lock file    | Installs new packages, updates vendor | Fetch + install in one step    |
| `remove`  | Removes package entry        | Re-resolves + updates lock file | Removes unused packages               | Keeps required transitive deps |
| `update`  | No changes                   | Re-resolves + updates lock file | Rebuilds vendor entirely              | Upgrades all dependencies      |
| `install` | No changes                   | Uses existing lock (no changes) | Syncs vendor with lock file           | Reproducible environment setup |


> **Note:** After every command, Nova automatically regenerates `fpc.cfg` from the `nova.lock` file, ensuring your build configuration stays up to date.

## Getting Started

A typical workflow to set up a new project might look like this:

```bash
# Initialize nova.json (optional but recommended)
nova init

# Add a dependency (resolves version automatically)
nova require daar/linkedlist

# Update lock file and rebuild vendor folder
nova update
```

Once your project is ready, make sure to commit both `nova.json` and `nova.lock` to version control.

To reproduce an environment locally or in a deployment pipeline, run:

```bash
nova install
```

This ensures the `vendor` folder is synced exactly to the versions in `nova.lock`, giving you a reproducible build.

## Version Constraints

Nova follows **Semantic Versioning (SemVer)** rules when resolving dependencies. You can define version constraints in `nova.json`.

### Exact Version

```json
"vendor/package": "1.2.3"
```

* Installs exactly `1.2.3` (no updates).

### Caret (`^`) Constraint

```json
"vendor/package": "^1.2"
```

* Installs the latest compatible version where the **major version is unchanged**.
* Example: `^1.2` allows `1.2.0 → 1.9.9` but **not** `2.0.0`.

#### Special Behavior for Major Version `0`

Semantic Versioning treats `0.x` releases as **unstable**, so caret ranges are more restrictive.

| Constraint | Allowed Versions                | Not Allowed       |
| ---------- | ------------------------------- | ----------------- |
| `^0.2`     | `0.2.0 → 0.2.x` (patch updates) | `0.3.0` and above |
| `^0.0.3`   | Exactly `0.0.3`                 | `0.0.4`, `0.1.0`  |

This ensures unstable packages (major version `0`) don’t introduce breaking changes unexpectedly.


### Tilde (`~`) Constraint

```json
"vendor/package": "~1.2.3"
```

* Installs patch updates only.
* Example: `~1.2.3` allows `1.2.3 → 1.2.99` but not `1.3.0`.

### Range Constraints

```json
"vendor/package": ">=1.2.0 <2.0.0"
```

* Installs any version within the defined range.

### Wildcard

```json
"vendor/package": "*"
```

* Installs the latest available version (not reproducible).

### Development Dependencies

Mark a package as a **development dependency** with `--dev`:

```bash
nova require vendor/package --dev
```

* Saved under `require-dev` in `nova.json`.
* Only installed in development environments.