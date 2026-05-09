# Review And Deploy Stages

These instructions describe what happens after development submits a GitHub pull
request and the main Jira issue moves into `CODE REVIEW`.

## Code Review Outcomes

- Code review may be completed manually by the user or automatically by the Tech
  Lead specialist.
- If code review fails, transition the main issue from `CODE REVIEW` back to
  `DEVELOPMENT` for another implementation pass.
- If code review passes or the pull request is approved, transition the main
  issue from `CODE REVIEW` to `DEPLOY` by default.

## Optional Testing

- Testing before deploy is optional and user-directed for now.
- By default, do not add a separate testing stop after approval; move approved
  work toward deploy.
- If the user asks to test an approved pull request before deployment, handle
  that request gracefully using the available workflow transition and testing
  tools.
- If Jira exposes a `TEST` status and the user requested testing, transition the
  main issue to `TEST` before `DEPLOY`.
- After requested testing is complete, transition the main issue to `DEPLOY`.

## Deploy Stage

- `DEPLOY` means launching, applying, or otherwise getting the completed work
  online in the appropriate way for the change.
- Deployment details are intentionally broad for now. Different work may require
  different deployment paths such as application rollout, Kubernetes changes,
  Terraform changes, documentation publishing, or another operational action.
- Use the relevant repo workflow docs and available tools for the specific
  deployment path when those rules exist.
- Do not invent deployment ceremony when the change has low or no deployment
  needs. Record or report that the deploy impact is low when appropriate.

## Done Transition

- After deployment is complete, transition the main issue from `DEPLOY` to
  `DONE`.
- Treat `DEPLOY -> DONE` as the normal completion handoff for work that passed
  review and was launched or otherwise finalized.
- If Jira does not expose a direct `DONE` transition, inspect live transitions
  and report the blocker instead of pretending the issue is complete.
