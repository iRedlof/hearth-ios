# iOS distribution

Hearth can be built and verified in the iOS Simulator. A Simulator `.app` cannot be installed on a physical iPhone or uploaded to TestFlight. A signed device build, an archive, an exported package, a TestFlight build, and an App Store release are separate delivery states. Record the actual destination and version/build when reporting a release.

This guide describes the repository configuration and the remaining distribution work. It does not attest to an uploaded iOS build, a TestFlight invitation, or an App Store release.

## Configuration source

[project.yml](../project.yml) is the XcodeGen source of truth. Generated `.xcodeproj` files are ignored; signing or version edits made only in a generated project can be lost on regeneration.

| Item | Current configuration |
| --- | --- |
| App target / scheme | `Hearth` |
| Embedded WidgetKit target | `HearthWidgets`, a dependency of `Hearth` |
| App bundle identifier | `com.rohit.hearth` |
| Widget bundle identifier | `com.rohit.hearth.widgets` |
| App Group for both targets | `group.com.rohit.hearth` |
| Minimum iOS | 17.0 |
| Marketing version / build | `0.1.0` / `1` |
| Development team | Empty |
| Signing identity / required | `-` / `NO` |

The version values are configuration, not evidence of publication. Both targets' generated Info.plists use `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Bump those two settings under `settings.base` in `project.yml`, then regenerate. Keep the app and extension versions aligned; use a new build number for each upload.

The App Group entitlement exists in both [Hearth/Hearth.entitlements](../Hearth/Hearth.entitlements) and [HearthWidgets/HearthWidgets.entitlements](../HearthWidgets/HearthWidgets.entitlements), and is also declared in XcodeGen configuration.

## Simulator verification

From the repository root, with Xcode and XcodeGen installed:

```sh
xcodegen generate
xcodebuild -project Hearth.xcodeproj -scheme Hearth \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/SimulatorDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

This builds the app and embedded extension. It does not install them or produce a distributable iOS package. Use an installed Simulator destination for native widget installation and interaction checks. Package tests (`swift test` from `HearthKit`) and `scripts/check-beacon.sh` are verification steps; neither publishes an app. The README's gallery captures are also distinct from actual WidgetKit Home Screen captures.

## Signing and physical-device verification

Before running on a physical device or archiving for distribution:

1. Select the intended Apple Developer team in Xcode and establish access to the required signing certificates and profiles.
2. Register explicit App IDs for the app and extension. Confirm ownership of the configured bundle identifiers before using them.
3. Register `group.com.rohit.hearth` and enable that same App Group for both App IDs. Their provisioning profiles must permit the entitlement. If identifiers change, update the project, both entitlement files, and the App Group references in shared-storage code together; changing only the signing UI breaks shared storage.
4. Configure both targets for the same team. Replace the repository's ad hoc identity and disabled signing requirement using appropriate signing settings in `project.yml`, or command-line overrides. Automatic signing can manage profiles once the account and capabilities are available.
5. For development installation, select a connected registered iPhone in Xcode, enable Developer Mode when required, and run `Hearth`. Add the embedded widget on the Home Screen and verify shared readings, navigation, and interactions on the device.

Simulator success does not establish that App Group provisioning or physical-device installation works. A WidgetKit extension is embedded in its containing app; distribute the `Hearth` archive rather than an extension-only package.

## Archive and export

The repository's manual [direct release preparation workflow](../.github/workflows/ios-direct-release.yml) builds an unsigned device archive and checks existing signing prerequisites. It does not sign/export an IPA or publish a release. There is no Fastlane configuration or `ExportOptions.plist`; Xcode's archive/distribution tools remain the signing/export path.

In Xcode, regenerate and open `Hearth.xcodeproj`, select the `Hearth` scheme and a generic iOS device destination, then choose **Product > Archive** after configuring signing. Use Organizer to validate and distribute that archive.

For an equivalent local archive with automatic development signing, set `HEARTH_APPLE_TEAM_ID` locally to the authorized team identifier:

```sh
xcodebuild -project Hearth.xcodeproj -scheme Hearth \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/Hearth.xcarchive" \
  DEVELOPMENT_TEAM="$HEARTH_APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  -allowProvisioningUpdates archive
```

This requires an authorized developer account in Xcode and valid App Group signing. `-allowProvisioningUpdates` permits Xcode to contact Apple and manage provisioning; it does not supply missing account authorization. The archive is subsequently re-signed for the selected distribution method. Creating it does not upload or publish a build.

In Organizer, select **Distribute App**:

- **TestFlight & App Store** uploads to App Store Connect.
- **TestFlight Internal Only** restricts the build to internal testing.
- **Release Testing** or **Debugging** exports a package for registered devices, using the applicable profiles.

For command-line export, first obtain export options for the chosen distribution method and signing team. The file is not supplied by this repository:

```sh
xcodebuild -exportArchive \
  -archivePath "$PWD/build/Hearth.xcarchive" \
  -exportPath "$PWD/build/Distribution" \
  -exportOptionsPlist /absolute/path/to/ExportOptions.plist \
  -allowProvisioningUpdates
```

Check `xcodebuild -help` for the installed Xcode's export options. Current help uses `method=app-store-connect` for App Store Connect and `destination=export` or `upload`; older method names are deprecated. A local export does not establish an upload. Keep signing keys, profiles, and authentication material outside the repository and release notes.

## Direct GitHub build and release preparation

The requested delivery channel is GitHub, with no TestFlight. Run `iOS direct release preparation` manually in `iRedlof/hearth-ios`. Its `source_ref` input defaults to the exact accepted thermostat-label commit, `7f859c05fedfa7c473a8fa2b0c9b01e41732c027`; it accepts a reviewed full 40-character commit SHA. The workflow can be placed on the default branch through a workflow/docs-only commit while building this separate source commit. That does not merge its 84-commit product backlog into `main`.

```sh
gh workflow run ios-direct-release.yml --repo iRedlof/hearth-ios \
  --ref main \
  -f source_ref=7f859c05fedfa7c473a8fa2b0c9b01e41732c027
```

The build job uses GitHub's documented `xcode-27` arm64 image and explicitly selects `/Applications/Xcode_27.app/Contents/Developer`, which the current official image inventory lists as Xcode 27.0 build `27A266a` with the iOS 27.0 SDK. That is the exact toolchain which already produced the accepted source's successful local device Release archive. The workflow checks the build identifier and fails with `XCODE_UNAVAILABLE` or `XCODE_BUILD_CHANGED` if the documented toolchain is absent or different. It generates the existing XcodeGen project in the disposable checkout, rejects tracked configuration changes, and performs one generic iOS-device Release archive with `ARCHS=arm64 CODE_SIGNING_ALLOWED=NO`.

The first organization run, [41397277355](https://github.com/iRedlof/hearth-ios/actions/runs/41397277355), selected Xcode 26.3 successfully but failed archive compilation with 20 instances of “passing closure as a 'sending' parameter risks causing data races” in existing `HearthWidgetBundle.swift` snapshot/timeline callbacks. The build job had no signing secrets, and the signing job was skipped. The corrected build job selects the independently documented, already verified Xcode 27.0 toolchain; product Swift source, concurrency checking, versions and signing settings are unchanged. The next run must produce a successful archive and verified unsigned artifact before any build claim. If that attempt fails, stop on its precise new error and investigate before another dispatch. The separate certificate/profile preflight continues to use `macos-15`.

The `ios-UNSIGNED-<run>-<attempt>` artifact contains the archive ZIP, actual bundle/version/build metadata, executable and ZIP SHA-256 hashes, selected source/workflow commits, and build log. The current accepted release configuration is `0.1.0 (1)` for both `com.rohit.hearth` and `com.rohit.hearth.widgets`; the metadata guard rejects other bundle IDs or versions. Artifacts are retained for 14 days. The archive is **unsigned**, and cannot be installed on an iPhone as delivered. The workflow performs no native installation or test run and claims no publication.

A separate signing preflight runs after the unsigned artifact is retained. It does not check out or execute product source. It references the existing organization secret names `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, and `TEAM_ID`; it never retrieves secrets through the GitHub API. The certificate must be a Base64-encoded PKCS#12 containing an **Apple Distribution/iPhone Distribution certificate and its private key** for the intended team. The name `MACOS_CERTIFICATE` does not establish the certificate type. The inspected Glimpse/Poppy organization workflows use these names for macOS Developer ID signing and notarization, which is a different distribution path.

The preflight imports the PKCS#12 into a temporary runner keychain, reports only certificate-class counts and a team-match boolean, and deletes the temporary signing material. It checks already-installed iOS `.mobileprovision` files for both explicit bundle IDs, matching team/certificate, unexpired registered-device distribution profiles, the shared `group.com.rohit.hearth` entitlement, and at least one common registered device. It does not fetch or create certificates/profiles, register devices, contact Apple for provisioning, or choose device IDs. GitHub-hosted runners start clean; with the currently supplied five organization secret names and no profile installation, the profile check is expected to fail.

`APPLE_ID` and `APPLE_ID_PASSWORD` are deliberately unused: the inspected organization workflows pass them to macOS `notarytool`, which is not iOS provisioning or signing. These strings do not configure an authenticated Xcode developer account or the supported provisioning API-key mechanism. No notarization or Apple upload command exists in this workflow.

The sanitized `ios-signing-preflight-<run>-<attempt>` artifact and job summary use concrete blocker keys:

| Blocker | Required correction |
| --- | --- |
| `ORG_SECRETS_UNAVAILABLE` | An organization owner must grant the repository access to the existing named secrets. Public-repository-only secrets require a public repository; the workflow does not change visibility or secret access policy. |
| `SIGNING_INPUT_INVALID_OR_IMPORT_FAILED` | Confirm the supplied Base64 PKCS#12, password, team format and certificate/private-key importability. Values remain in GitHub secrets. |
| `IOS_DISTRIBUTION_IDENTITY_MISSING_OR_TEAM_MISMATCH` | Supply an iOS-compatible distribution identity for the intended team; a Developer ID certificate signs macOS software. |
| `IOS_REGISTERED_DEVICE_PROFILES_MISSING_OR_INCOMPATIBLE` | Authorize provision of two matching iOS distribution profiles for the app and widget, including their shared App Group and registered intended devices. No additional profile secret names or account credentials are assumed or created. |
| `IOS_PROFILES_HAVE_NO_COMMON_REGISTERED_DEVICE` | Ensure both profiles cover the same intended iPhone(s). |

For an installable direct iOS package, the account owner must establish the intended registered devices and usable profiles for both targets. Apple requires registered-device provisioning for ad hoc distribution; a GitHub download URL does not remove that requirement. Enterprise distribution is a separate entitlement and is not assumed. Once authorized signing/profile delivery is established, a signed archive/export step can be configured and independently verified for this channel. Even a green preflight means only that prerequisites are present: this workflow still exports no IPA.

Root owns the reviewed workflow commit, dispatch, final signing/native acceptance, and GitHub release publication. A release containing this build must label the asset **UNSIGNED device Release archive**, include its source commit and SHA-256, and state that it is not installable. Publishing an installable IPA requires successful signing/export and verification of the included app, widget, App Group and intended device coverage.

Official references for this path:

- [GitHub: hosted runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub runner-images: xcode-27 arm64 Xcode/SDK inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [GitHub: documented xcode-27 workflow label](https://github.com/actions/runner-images/issues/14404)
- [Apple: Xcode system requirements and SDKs](https://developer.apple.com/xcode/system-requirements)
- [GitHub: installing certificates and provisioning profiles on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub: organization secret access policies](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
- [Apple: ad hoc profiles require a distribution certificate and registered devices](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile)
- [Apple: distribution methods, including Developer ID for macOS](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html)

## TestFlight and App Store prerequisites

The repository does not establish these external prerequisites:

- An active Apple Developer Program team with appropriate signing and App Store Connect access.
- Registered app/extension IDs, the shared App Group, and usable development/distribution signing for both targets.
- An App Store Connect app record matching the app bundle identifier, required agreements, and the intended version/build.
- A processed uploaded build and configured TestFlight tester group. External testing may require Beta App Review.
- App Store metadata, privacy disclosures, screenshots, review information, and App Review approval for public release.

After upload, confirm processing in App Store Connect, assign the build to the intended TestFlight group, and verify installation before reporting TestFlight delivery. For an App Store release, submit the selected build and required metadata to App Review, then confirm its actual release state and store URL.

## References

- [Apple: distribute beta builds and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/)
- [Apple: register an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group)
- [Apple: enable App Group capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
- [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- Local `xcodebuild -help` for archive/export and provisioning options.
