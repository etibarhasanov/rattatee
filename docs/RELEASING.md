# Packaging Rattatee

Two workflows, two jobs:

| Workflow | Runs | Makes |
| --- | --- | --- |
| `build` (`.github/workflows/ios.yml`) | only when asked | a simulator build and the screenshots — proof it compiles, nothing installable |
| `package` (`.github/workflows/release.yml`) | only when asked | a signed `.ipa`, sent to TestFlight unless told not to |

A push never makes a package. There are two ways to ask for one.

**From the Actions tab.** Actions → **package** → **Run workflow**, pick the
branch, and leave **Send the build to TestFlight** ticked. Untick it for an
`.ipa` that stays on the run as an artifact for 30 days and goes nowhere
else. This is the way to put a build from a branch on your own phone before
it lands.

**With a tag.** A tag that starts with `v` packages that commit and sends it
to TestFlight, and the tag becomes the version people see:

```bash
git tag v1.2
```

```bash
git push origin v1.2
```

**A release is a merge of `develop` into `main`, tagged.** Work happens on
`develop`; `main` only ever moves when a version is ready and its number has
been chosen. For version 0.6.9, say:

```bash
git checkout develop
```

Set `MARKETING_VERSION = 0.6.9;` in `Rattatee.xcodeproj/project.pbxproj`
(both Debug and Release), commit it on `develop`, then:

```bash
git checkout main
```

```bash
git merge --no-ff develop -m "Release 0.6.9"
```

```bash
git tag v0.6.9
```

```bash
git push origin main develop v0.6.9
```

The tag is what packages it and sends it to TestFlight.

**A release has no radio, for now.** A tag, or a package made from `main`, is
built with `NO_RADIO`. The riding screen then has no radio row and nothing
plays (README.md, **Not in a release, for now**). A package from `develop`
or any other branch still has the radio.

The build number is `BUILD_NUMBER_BASE` (100, at the top of the workflow)
plus the run number, so it only goes up. Without a tag, the version is the
`MARKETING_VERSION` in the project.

Both are at the foot of the Account tab, *Version 1.0 (142)*, read from the
installed app, so a tester can say which build they have. A build from Xcode
says `(1)`, the project's own `CURRENT_PROJECT_VERSION`.

## The four secrets, once

The workflow signs with Xcode's automatic signing and an App Store Connect
API key, so there is no certificate or profile to export or renew. It needs
four repository secrets — GitHub → the repository → **Settings → Secrets and
variables → Actions → New repository secret**. The same four values work in
all three app repositories (Tallinn Taste Buds, Kohuke and Rattatee).

1. **`APPLE_TEAM_ID`** — the ten characters under **Membership details** at
   <https://developer.apple.com/account>.
2. In App Store Connect → **Users and Access → Integrations → App Store
   Connect API → Team Keys**, press **+**, name it `GitHub`, give it the
   **Admin** role (automatic signing has to be allowed to create the
   distribution certificate; App Manager cannot), and **Generate**.
   - **`ASC_ISSUER_ID`** — the Issuer ID shown above the list of keys.
   - **`ASC_KEY_ID`** — the new key's Key ID.
   - **`ASC_KEY_P8`** — press **Download API Key**, open the `.p8` file in a
     text editor, and paste the whole of it, the `BEGIN` and `END` lines
     included. Apple lets you download it once.

The app's record has to exist in App Store Connect before the first upload
(bundle id `ee.tallinntastebuds.rattatee.app`); `docs/` says how where it covers the listing.

If the run stops at **Check the signing secrets are set**, one of the four
is missing, and the error names it.
