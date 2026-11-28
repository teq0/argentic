# Releasing Argentic for macOS

The [Release macOS workflow](../.github/workflows/release-macos.yml) builds a single
**Universal app** containing native `arm64` (Apple Silicon) and `x86_64` (Intel)
executables. Both require **macOS 14 Sonoma or later**. There is no iOS release in
this workflow.

Pushing a stable version tag such as **`v0.1.0`** runs tests, builds a Release app,
signs it with Developer ID, submits it to Apple's notarization service, staples
the accepted ticket, checks Gatekeeper, and uploads these files to a **draft**
GitHub Release:

- `Argentic-v0.1.0-macOS-universal.zip`
- `SHA256SUMS.txt`

The workflow never publishes the draft automatically and does not fall back to
an unsigned release if credentials, signing or notarization fail. No Mac App
Store submission is involved.

## One-time Apple setup

1. Activate your **Apple Developer Program** membership and accept any pending
   agreements in your Apple developer account.
2. In Xcode, sign in under **Settings → Accounts**, select the paid team and open
   **Manage Certificates**. Create a **Developer ID Application** certificate.
   This must not be an Apple Development, Apple Distribution, or Developer ID
   Installer certificate. Apple may require the team's Account Holder or an
   appropriately authorized administrator to create it.
3. In **Keychain Access → My Certificates**, find that certificate, including its
   private key, and export it as a password-protected `.p12` file. A certificate
   without its private key cannot sign the app. Keep a secure backup and never
   commit it or its password.
4. Find your ten-character **Team ID** in your Apple developer account's
   membership details.
5. At [account.apple.com](https://account.apple.com/), create an **app-specific
   password** for notarization using the Apple account associated with the team.
   Do not use your normal Apple account password.

The app's current sandbox/file-access entitlements do not need a Developer ID
provisioning profile. Revisit signing if restricted Apple services or additional
entitlements are added later.

## GitHub repository secrets

In **teq0/argentic → Settings → Secrets and variables → Actions → Repository
secrets**, add:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded exported Developer ID Application `.p12`, including its private key. |
| `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting the `.p12`. |
| `APPLE_TEAM_ID` | The team ID matching the Developer ID certificate. |
| `APPLE_ID` | The Apple account email used for notarization. |
| `APPLE_APP_SPECIFIC_PASSWORD` | The app-specific password created above. |

For example, copy the encoded certificate to the clipboard on your Mac:

```sh
base64 -i /path/to/DeveloperIDApplication.p12 | pbcopy
```

Alternatively, send it directly to GitHub CLI without displaying it:

```sh
base64 -i /path/to/DeveloperIDApplication.p12 |
  gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo teq0/argentic
```

The workflow generates a temporary keychain password itself, imports the signing
identity and notarization credentials into that keychain, and deletes it even
when a step fails. Signing secrets are not passed to the GitHub Release upload
job. Only that final job gets a GitHub token with `contents: write` permission.
Repository/organization policy must allow that workflow permission.

Only trusted maintainers should be able to create release tags or edit the
workflow and build scripts: tagged source runs with access to signing secrets.
Configure GitHub rulesets for `v*` tags and protect the default branch as
appropriate. Do not run this workflow against unreviewed code.

## Create v0.1.0

1. Commit and push the intended source, including the release workflow and build
   helper, to GitHub. Make sure the Apple membership and all five secrets are
   ready before tagging.
2. From that release commit, create and push the tag:

   ```sh
   mise run tag-release -- v0.1.0
   ```

   This creates an annotated tag at `HEAD` and pushes it to `origin`. If the
   push fails, the local tag remains; push it again or remove it before retrying.

   To remove a tag before publishing a release:

   ```sh
   mise run delete-tag -- v0.1.0
   ```

   This fetches the tag from `origin` if it is not already local, deletes it
   remotely, then deletes it locally. The task refuses to delete a tag that has
   an associated GitHub Release; deleting a tag does not delete a release or
   its assets.

3. Watch **Actions → Release macOS**. Tests run first. Hosted Intel runners run
   a small CI-safe package-test subset instead of the long Oracle suite.
   The full package and app suites run on Apple Silicon only when a Metal device
   is available. Run the full
   `mise run test` and `mise run test-app` suites on a physical Mac before release.
   The interactive native Spaces test remains opt-in and is not run on CI.
4. Open **Releases**, edit the generated **draft**, and download/test the ZIP.
   Check the notes, acknowledgements and licensing before public distribution.
   The ZIP contains `Argentic.app`; users unzip it and drag the app to
   **Applications**. Test on both an Apple Silicon Mac and an Intel Mac if
   possible: the workflow verifies both executable slices, but runs tests only
   on the runner's native architecture.
5. Choose **Publish release** when satisfied.

The tag supplies the app's marketing version (`v0.1.0` becomes `0.1.0`), and the
workflow run number supplies its build number. Future releases use a new stable
`vMAJOR.MINOR.PATCH` tag; prerelease suffixes are not supported by this workflow.

To retry an existing tag, re-run its failed workflow, or choose **Run workflow**
and enter the existing tag. Manual runs check out the tag, not the selected
branch's current source. Successful reruns replace files on an existing draft,
but refuse to modify a published release. Do not publish a draft while a rerun
is in progress, and do not move version tags after distributing them.

## Build locally without Apple credentials

```sh
mise run build-release -- 0.1.0
```

This builds and verifies both architectures at:

```text
app/.build/DerivedData-Release/Build/Products/Release/Argentic.app
```

Without `MACOS_SIGNING_IDENTITY`, this is an **unsigned local preview**, not a
distributable/notarized release. It does not change the Debug build used by
`mise run run`. With an installed Developer ID identity, the build helper also
accepts `MACOS_SIGNING_IDENTITY` (identity name or SHA-1), `APPLE_TEAM_ID`, and an
optional positive `ARGENTIC_BUILD_NUMBER`. The GitHub workflow requires signing
credentials and performs the subsequent notarization/packaging steps.

## Troubleshooting

- **Missing secret:** configure every secret above; the workflow deliberately
  stops rather than uploading an unsigned app.
- **No matching identity:** re-export the certificate **with its private key**,
  check its expiry and Team ID, and ensure it is a **Developer ID Application**
  certificate. Import only one matching signing identity in the `.p12`.
- **Notarization rejected or timed out:** inspect the notarization step's JSON
  response and submission ID. When available, Apple's rejection log is printed
  there. The workflow waits up to 30 minutes for Apple; initial submissions may
  take longer. Check your developer agreements/account status before retrying.
- **Cannot create the draft:** check GitHub Actions permissions and repository
  policy. A draft is created only after signing, notarization and Gatekeeper
  validation have succeeded.
- **Xcode image changes:** CI selects Xcode 26.3 on `macos-15-intel`. Update
  `DEVELOPER_DIR` and the runner label together if GitHub removes that version.
  The app's minimum macOS version remains 14.0 regardless of the build host.
