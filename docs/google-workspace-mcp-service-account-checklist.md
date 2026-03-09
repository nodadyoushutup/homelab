# Google Workspace MCP Service Account Setup Checklist

Use this checklist to make `mcp-google-workspace` work with service-account delegation (no interactive OAuth flow).

## 1) Create service account in Google Cloud

1. In Google Cloud Console, create/select your project.
2. Enable the APIs you plan to use (see API list below).
3. Create a service account (for example `mcp-google-workspace`).
4. In the service account settings, enable **Domain-wide delegation**.
5. Create and download a JSON key for that service account.
6. Mount that JSON key into the MCP container and set:
   - `WORKSPACE_MCP_SERVICE_ACCOUNT_FILE` (path to JSON)
   - `WORKSPACE_MCP_DELEGATED_USER` (Workspace admin/user email to impersonate)

## 2) Grant domain-wide delegation in Google Admin

1. Go to Admin Console: `Security` -> `API controls` -> `Domain-wide delegation`.
2. Click `Add new`.
3. Set `Client ID` to the service account OAuth 2.0 Client ID.
4. Add required OAuth scopes (comma-separated).
5. Save and wait a few minutes for propagation.

If this step is wrong/incomplete, delegated token refresh fails with `unauthorized_client`.

## 3) Required OAuth scopes

Use only what you need, but for the read checks we ran, include at least:

- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/gmail.labels`
- `https://www.googleapis.com/auth/drive.readonly`
- `https://www.googleapis.com/auth/calendar.readonly`
- `https://www.googleapis.com/auth/contacts.readonly`
- `https://www.googleapis.com/auth/tasks.readonly`
- `https://www.googleapis.com/auth/spreadsheets.readonly`
- `https://www.googleapis.com/auth/documents.readonly`

If you use additional MCP tools, also add scopes for those surfaces (for example Slides, Forms, Chat, Script).

## 4) APIs to enable in Google Cloud

Enable these APIs in the same project as the service account:

- Gmail API
- Google Drive API
- Google Calendar API
- People API
- Google Tasks API
- Google Sheets API
- Google Docs API

Common optional APIs (enable if you use related tools):

- Google Slides API
- Google Forms API
- Google Chat API
- Apps Script API
- Custom Search API

## 5) MCP runtime settings

Set service-account mode explicitly in container env:

- `WORKSPACE_MCP_USE_SERVICE_ACCOUNT=true`
- `WORKSPACE_MCP_SERVICE_ACCOUNT_FILE=/run/secrets/service_account.json`
- `WORKSPACE_MCP_DELEGATED_USER=admin@yourdomain.com`

Also ensure the key file is readable by the container process.

## 6) Quick verification sequence

1. Confirm delegated auth can mint a token (no `unauthorized_client`).
2. Run simple read tool calls:
   - `list_drive_items` (root)
   - `list_calendars`
   - `list_gmail_labels`
   - `list_contacts`
3. If any call fails with API disabled, enable that API and retry.
4. If calls fail with auth errors, re-check DWD Client ID + scopes + delegated user.

## 7) Known failure patterns

- `unauthorized_client`: DWD/scopes not correctly granted in Admin Console.
- OAuth secret errors during SA mode: service-account path failed and code fell back to OAuth flow.
- `accessNotConfigured`/API disabled: corresponding API is not enabled in GCP project.
