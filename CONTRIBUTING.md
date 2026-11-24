# Contributing to HomePanel

Thanks for helping. Bug reports, device support and fixes are all welcome.

## Getting set up

Follow **Build and install** in the [README](README.md): install XcodeGen, copy `Config/Signing.xcconfig.template` to `Config/Signing.xcconfig` with your own team ID, then `xcodegen generate`. Run `xcodegen generate` again whenever you add or remove files.

## Before you open a pull request

- `cd Packages/HAKit && swift test` passes. Add tests for logic that lives in HAKit (parsing, layout generation, device wording and features).
- The app builds without warnings. The project uses Swift 6 with strict concurrency.
- Keep personal details out of commits: no access tokens, real IP addresses, team IDs or entity IDs from your own home. Test fixtures use made-up names like `light.shelf_strip`.
- Never log tokens, lock or alarm codes, or attribute values. Entity IDs and states are fine at `.notice` level.
- Be careful with real devices while testing. Some (A/C units, for example) beep on every command.

## Adding a device type

1. Put the logic in HAKit: supported-feature flags and wording in `Devices.swift`, with tests in `DeviceTests.swift`.
2. Add the screen under `HomePanel/Panel/Devices/`, showing only the controls the entity supports.
3. Route it in `PanelRootView` and give it a quick action in `AppModel.quickAction` if one makes sense.
4. Teach `LayoutGenerator` where it belongs in generated rooms.

## Reporting a bug

Include your macOS and Home Assistant versions, the integration behind the device, and what you expected. Redact anything personal from screenshots and logs.
