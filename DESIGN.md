# Design Notes

- Use `SettingsCard`, `SettingsRow`, and `SettingsSwitchRow` from `lib/components/ui_components.dart` for grouped settings UI. Do not create per-screen `_settingsCard` / left-label-right-value row variants.
- Left-label/right-value rows must right-align the value text and keep the chevron at the far right.
- Do not use Material `Switch` in app UI. Use `SettingsSwitchRow` or `CupertinoSwitch`.
