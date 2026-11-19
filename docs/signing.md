# Release signing setup

Arbor releases are signed with a **stable self-signed certificate** instead of an ad hoc
signature. macOS privacy permissions (TCC), including Full Disk Access, are tied to the
app's designated requirement. With an ad hoc signature that requirement is the binary's
hash, so every update loses Full Disk Access. With a stable certificate the requirement
is `certificate leaf = H"…"`, so access survives updates as long as the certificate does
not change.

The certificate does not remove the Gatekeeper warning (that needs an Apple Developer ID
and notarization). See the README for how users open the app.

This is a one-time setup done by the maintainer. Never commit the certificate, the key
or the `.p12`; `.gitignore` excludes them.

## 1. Create the certificate

Use the system `/usr/bin/openssl` (LibreSSL): its `.p12` encryption is the one the macOS
`security` tool imports reliably. OpenSSL 3+ defaults can fail to import.

```bash
/usr/bin/openssl req -x509 -newkey rsa:4096 -sha256 -days 7300 -nodes \
  -keyout arbor-signing.key -out arbor-signing.crt \
  -subj "/CN=Arbor Self-Signed Code Signing" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
```

`-days 7300` gives 20 years. The common name must stay
`Arbor Self-Signed Code Signing`: `release.yml` signs with that identity name.

Check it:

```bash
/usr/bin/openssl x509 -in arbor-signing.crt -noout -subject -enddate -ext keyUsage,extendedKeyUsage
```

Expected: `Code Signing` under extended key usage, an end date about 20 years ahead.

## 2. Export the .p12

```bash
/usr/bin/openssl pkcs12 -export -inkey arbor-signing.key -in arbor-signing.crt \
  -name "Arbor Self-Signed Code Signing" -out arbor-signing.p12
```

Choose a strong export password when prompted and store it in your password manager.

## 3. Test the .p12 locally (throwaway keychain)

This mirrors what CI does, without touching your login keychain.

```bash
security create-keychain -p check /tmp/arbor-check.keychain-db
security import arbor-signing.p12 -k /tmp/arbor-check.keychain-db -T /usr/bin/codesign
security find-identity -p codesigning /tmp/arbor-check.keychain-db
```

`find-identity` must list `Arbor Self-Signed Code Signing` (it may be reported as not
trusted, which is expected for a self-signed certificate). Optionally sign a copy of a
local Arbor build to confirm the whole chain:

```bash
security unlock-keychain -p check /tmp/arbor-check.keychain-db
codesign --force --sign "Arbor Self-Signed Code Signing" --keychain /tmp/arbor-check.keychain-db \
  --timestamp=none /path/to/copy/of/Arbor.app
codesign --display --requirements - /path/to/copy/of/Arbor.app
```

Then delete the throwaway keychain:

```bash
security delete-keychain /tmp/arbor-check.keychain-db
```

## 4. Back up, then delete the loose files

- Keep an **offline backup** of `arbor-signing.p12` (for example on an encrypted
  external disk) and its password in your password manager. Losing it means a new
  certificate, and every user has to grant Full Disk Access again.
- Then delete `arbor-signing.key` and `arbor-signing.crt` (the `.p12` contains both), and
  delete the `.p12` from your working folder once it is uploaded and backed up.

## 5. Protected `release` environment on GitHub

The signing secrets live only in an environment named `release`, which only `release.yml`
uses and which only deploys from `v*` tags. `ci.yml` (pushes and pull requests, including
from forks) never references this environment, so it never receives the secrets.

In the web UI: **Settings › Environments › New environment** `release`, then
- **Deployment branches and tags** › *Selected branches and tags* › add a **tag** rule `v*`;
- optionally **Required reviewers** › yourself, to approve each release run;
- **Environment secrets** › add `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD`.

Do not add these as repository secrets.

Or with `gh` (replace `OWNER/REPO`):

```bash
gh api -X PUT repos/OWNER/REPO/environments/release \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
```

```bash
gh api -X POST repos/OWNER/REPO/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag
```

```bash
base64 -i arbor-signing.p12 | gh secret set SIGNING_P12_BASE64 --env release --repo OWNER/REPO
```

```bash
gh secret set SIGNING_P12_PASSWORD --env release --repo OWNER/REPO
```

Also restrict who can push `v*` tags: **Settings › Rules › Rulesets › New tag ruleset**,
target `v*`, restrict creations, updates and deletions to maintainers.

## 6. Releasing

```bash
git tag v0.1.0
git push origin v0.1.0
```

`release.yml` imports the `.p12` into a temporary keychain with a random password, builds
a universal Release, signs it, packages `.zip` + `.dmg` + `SHA256SUMS.txt`, publishes the
GitHub Release, and deletes the keychain even if a step fails.

Check a downloaded build:

```bash
codesign --display --requirements - /Applications/Arbor.app
```

The designated requirement must contain `certificate leaf = H"…"` with the same hash on
every release.

## Rotating the certificate

Only rotate if the key is compromised or about to expire. A new certificate changes the
designated requirement, so macOS drops Full Disk Access for every user on the next
update. Arbor's onboarding detects the lost access and walks users through granting it
again. Mention the rotation in the release notes.
