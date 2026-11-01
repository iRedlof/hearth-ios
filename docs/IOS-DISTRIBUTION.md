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

The repository has no release workflow, Fastlane configuration, or `ExportOptions.plist`. Xcode's existing archive/distribution tools are the available path.

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
