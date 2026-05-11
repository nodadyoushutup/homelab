# Code vs GitHub (homelab)

| Request | Owner |
| --- | --- |
| PR open/update/merge, checks, review requests, Actions API | `github` |
| File content, tests, conflict resolution in the working tree | `code` |
| Local git: status, fetch, pull, branch, checkout, commit, push | `code` |
| Jira issue status, ticket comments | `jira` |
| Architecture sign-off before large change | `tech_lead` (then `github` for PR) |

Typical Jira-led delivery: **`jira`** (context) → **`code`** (branch, implement,
commit, push) → **`github`** (PR, checks, dispatch monitoring).
