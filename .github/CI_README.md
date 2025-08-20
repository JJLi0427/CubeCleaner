# CI/CD Configuration

This document describes the Continuous Integration (CI) setup for the CubeCleaner project.

## GitHub Actions Workflows

### 1. CI Build (`ci-build.yml`)

This workflow is triggered on:
- Push to `main` branch
- Pull requests targeting `main` branch

**Build Process:**
- Uses `macos-latest` runner
- Builds the project in Debug configuration for all triggers
- Additionally builds Release configuration only for pushes to main
- Archives the built app as compressed tar files
- Uploads artifacts for download

**Artifacts:**
- Debug builds: Retained for 30 days
- Release builds: Retained for 90 days (only for main branch pushes)

### 2. PR Check (`pr-check.yml`)

Simple check workflow to ensure PR requirements are met.

## Setting up Branch Protection

To ensure PRs can only be merged after CI passes:

1. Go to GitHub repository Settings → Branches
2. Add rule for `main` branch
3. Enable "Require status checks to pass before merging"
4. Select the "build" check from ci-build workflow
5. Enable "Require branches to be up to date before merging"

## Local Development

You can still use the local build script:

```bash
# Build debug version
./build.sh build

# Build release version
./build.sh release

# Clean and rebuild
./build.sh clean && ./build.sh build
```

## Artifact Download

After CI runs, you can download the built app:

1. Go to the Actions tab in GitHub
2. Click on the workflow run
3. Scroll down to "Artifacts" section
4. Download the compressed app file
5. Extract: `tar -xzf CubeCleaner-Debug.tar.gz`
