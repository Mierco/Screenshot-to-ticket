# Screenshot to Jira (iOS MVP)

SwiftUI MVP that:
- picks up to 3 images/videos from Photos
- uses OpenAI to draft Bug summary/description
- applies optional user hint as both instruction and appended reporter notes
- creates Jira issue in `TMNEWS`
- auto-selects biggest unreleased semantic fix version
- uploads selected images/videos as attachments

## Project setup in Xcode

This repository currently contains app source files only.

1. Create a new iOS app project in Xcode:
- Interface: `SwiftUI`
- Language: `Swift`
- Product name: `ScreenshotToTicketApp`

2. Replace the generated source with files from:
- `ScreenshotToTicketApp/App`
- `ScreenshotToTicketApp/Models`
- `ScreenshotToTicketApp/Services`
- `ScreenshotToTicketApp/ViewModels`
- `ScreenshotToTicketApp/Views`
- `ScreenshotToTicketApp/Utils`

3. Add `Privacy - Photo Library Usage Description` (`NSPhotoLibraryUsageDescription`) in Info settings.
Suggested value: `Needed to pick screenshots to attach to Jira issues.`

4. Run on iOS 16+ (PhotosPicker API).

## Runtime configuration

Open the app, tap `Settings`, then fill:
- Jira Workspace URL (default: `https://iagentur.jira.com`)
- Project Key (default: `TMNEWS`)
- Atlassian Email
- Jira API Token
- OpenAI API Key
- OpenAI Model ID (fully configurable; default: `gpt-5.4-codex`)

Credentials are stored in Keychain. Workspace URL/project/model are in UserDefaults.

## Notes

- Issue type is fixed to `Bug`.
- Priority is left to Jira default.
- Fix version logic: largest unreleased semantic version parsed from project versions.
- Images are resized/compressed to JPEG before upload.
