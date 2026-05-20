# Screenshot-to-ticket

Easy way to create Jira tickets from screenshots and videos.

## iOS MVP

SwiftUI app that:
- picks up to 3 images or videos from Photos
- uses OpenAI to draft bug summary and description
- applies an optional user hint as instruction and appended reporter notes
- creates a Jira issue in the selected Jira profile/project
- auto-selects the biggest unreleased semantic fix version
- uploads selected images and videos as attachments

## Project setup in Xcode

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
- Atlassian Email
- Jira API Token
- OpenAI API Key
- OpenAI Model ID (fully configurable; default: `gpt-5.4-codex`)

Credentials are stored in Keychain. Workspace URL, Jira profiles, active profile, and model are stored in `UserDefaults`.

Jira profiles are managed in Settings:
- load available Jira projects
- use a selected project as a profile
- rename the profile
- add default Jira fields as a JSON `fields` object

Default field JSON is merged into the Jira issue fields. The app always sets `project`, `summary`, `description`, and automatic `fixVersions`; `issuetype` may be set per profile and falls back to `Bug`.

## Notes

- Issue type defaults to `Bug` unless a Jira profile sets `issuetype`.
- Priority is left to the Jira default.
- Fix version logic picks the largest unreleased semantic version from project versions.
- Images are resized and compressed to JPEG before upload.
