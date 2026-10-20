# GitHub Build

This repository includes `.github/workflows/ios-build.yml`. GitHub Actions runs the Xcode build on a macOS runner for every push/PR to `main` or `master`, and can also be started manually from **Actions → iOS Build → Run workflow**.

The workflow builds an **unsigned iOS Simulator app** and uploads `3105-simulator-build` as a workflow artifact. This is for CI/build verification; a physical-device IPA still requires Apple code signing/provisioning.

## Real auth later

The startup key screen is already connected to `KeyAuthManager`. For production, set `demoMode = false` and provide `verificationURL`. Keep the one-key/one-device binding logic on the server.
