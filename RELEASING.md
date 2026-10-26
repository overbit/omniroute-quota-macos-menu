# Trusted macOS releases

Regular GitHub Actions test artifacts are deliberately **ad-hoc signed**. They
will trigger Gatekeeper approval because they have no Apple Developer ID or
notarization ticket. **Use GitHub Releases for end-user downloads.**

Apple's supported direct-distribution chain is:

1. Sign the app with a **Developer ID Application** certificate, hardened
   runtime, and a secure timestamp.
2. Upload the signed app ZIP to Apple's notarization service via
   `xcrun notarytool submit --wait`.
3. **Staple** the returned ticket to the `.app`, then verify it.
4. Only after stapling, create the distributable ZIP and publish a GitHub
   Release. (A ZIP cannot be stapled directly.)

The implementation is `.github/workflows/release.yml` and
`scripts/package-app.sh`. No certificate or API key goes into the repository.

## One-time Apple setup

Requires an active Apple Developer Program membership. A team Account Holder
creates the **Developer ID Application** certificate at
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list),
then installs it in the local Mac Keychain, with its **private key**. In Keychain
Access, select it under **My Certificates**, export the certificate and private
key as a password-protected `.p12`.

Generate an **App Store Connect *team* API key** with Developer role or higher
at [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api).
Download the private `.p8` once and retain the Key ID and Issuer ID.
Individual API keys do not support the Notary service. Prefer the least
privileged team key accepted for notarization.

## One-time GitHub setup

In this repository, go to **Settings → Environments → New environment** and
create an environment named **`release`**. Configure required reviewers and
restrict deployments to version tags (`v*`) where supported. Protect who can
push or create release tags. The workflow additionally rejects tags whose
commit is not on `main`.

Add these five **environment secrets** (not plain repository variables):

| Secret | Value |
|---|---|
| `APPSTORE_CERTIFICATES_FILE_BASE64` | Base64 of the Developer ID Application `.p12` |
| `APPSTORE_CERTIFICATES_PASSWORD` | Password used to export that `.p12` |
| `APPSTORE_API_PRIVATE_KEY` | Full PEM contents of the **team** API `.p8`, including BEGIN/END lines |
| `APPSTORE_API_KEY_ID` | App Store Connect team API Key ID |
| `APPSTORE_ISSUER_ID` | App Store Connect API Issuer ID (UUID) |

On your Mac, you can put the P12 base64 on the clipboard without printing it:

```sh
base64 -i ~/Downloads/DeveloperID-Application.p12 | pbcopy
```

Paste the result into the matching GitHub environment secret. Paste the full
`.p8` file contents into `APPSTORE_API_PRIVATE_KEY`. **Do not paste
private keys, certificates, or passwords into an issue, PR, chat, or commit.**

## Release a version

After the feature branch containing the release workflow is merged to
`main`, create a semantic version tag on `main`:

```sh
git switch main
git pull --ff-only origin main
git tag v0.1.0
git push origin v0.1.0
```

The tag starts the protected `Notarized macOS release` workflow. It tests the
app, imports the P12 into a temporary runner Keychain, signs with a hardened
runtime and secure timestamp, notarizes, staples, validates Gatekeeper,
publishes a versioned ZIP to **GitHub Releases**, and deletes the temporary
credentials. The workflow **fails closed** if signing credentials are absent,
Apple rejects the submission, or validation fails. Nothing is published in
those cases. The version in the tag becomes `CFBundleShortVersionString`.

For subsequent updates, create a new tag (for example `v0.1.1`). Continue
using the **same developer team/Developer ID** so macOS recognizes updates
from the same publisher. Do not install ad-hoc CI builds over trusted releases.

## Check the downloaded app

After extracting the GitHub Release ZIP on a Mac:

```sh
codesign --verify --deep --strict --verbose=2 OmniRouteQuota.app
codesign --display --verbose=4 OmniRouteQuota.app
xcrun stapler validate OmniRouteQuota.app
spctl --assess --type execute --verbose=4 OmniRouteQuota.app
```

The signature must identify a **Developer ID Application**, the runtime must
be hardened, the notarization ticket must validate, and Gatekeeper must accept
the app. The first launch can still show macOS's standard confirmation that
an identified developer's app was downloaded from the internet; this is
normal and does not require a security bypass.

If instead the dialog asks for permission to use **Keychain credentials**,
that is separate from Gatekeeper. The stable Developer ID signature should
help prevent repeated app-identity changes, but existing entries created
by ad-hoc builds may require a one-time Keychain access confirmation.

References:
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Customize the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
