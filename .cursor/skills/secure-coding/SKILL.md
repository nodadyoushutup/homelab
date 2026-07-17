---
name: secure-coding
description: Applies secure-by-default implementation and review rules to application code, APIs, authentication, secrets, infrastructure as code, containers, CI/CD, and dependency changes. Use proactively when creating or modifying code, configuration, manifests, workflows, public endpoints, authorization, data handling, or other security-sensitive behavior.
---

# Secure Coding

Prevent common AI-assisted coding failures without inventing requirements or adding security theater.

## Required workflow

For every substantive change:

1. Identify assets, untrusted inputs, trust boundaries, privileged operations, and externally reachable surfaces affected by the change.
2. Read the relevant implementation, callers, configuration, tests, and project guidance before editing. Never infer a security contract from a filename or one code fragment.
3. Check authorization, validation, secret handling, failure behavior, logging, dependency risk, and deployment exposure.
4. Prefer the smallest design that is secure by default. Do not add speculative frameworks, abstractions, permissions, ports, or dependencies.
5. Verify security-sensitive API and configuration behavior against installed-version documentation or source. Never guess option names, defaults, algorithms, or middleware behavior.
6. Test both allowed and denied paths. A successful happy-path test is not security verification.
7. Report residual risk and any assumptions that could not be verified.

## Core rules

### Trust and authorization

- Treat request data, headers, cookies, files, URLs, webhooks, queue messages, environment variables, database content, and tool output as untrusted until validated for the current use.
- Enforce authentication and authorization on the server at every privileged operation. UI hiding, route guards, object IDs, and possession of a URL are not authorization.
- Check access to the specific resource and action, not only a broad role. Prevent horizontal and vertical privilege escalation.
- Default to deny. Missing, malformed, expired, or unverifiable credentials must fail closed.
- Do not create bypasses, fallback credentials, debug authentication, magic users, or permissive development paths that can reach production.
- Re-check authorization after redirects, object lookup, tenant selection, and background-job dispatch.
- For multi-tenant data, scope queries by tenant or owner in the data-access operation; do not fetch globally and filter afterward.

### Input, output, and injection

- Validate at the trust boundary using an explicit schema: type, format, length, range, allowed values, and collection size. Reject unexpected fields when practical.
- Keep data separate from commands and code. Use parameterized database queries, argument arrays for processes, structured APIs, and safe templating.
- Never construct shell commands, SQL, LDAP filters, template source, or interpreter expressions by concatenating untrusted data.
- Avoid invoking a shell. If unavoidable, use a fixed executable and fixed command structure; allowlist arguments and document why shell execution is required.
- Encode output for its actual context. HTML escaping does not make data safe for JavaScript, CSS, URLs, HTTP headers, or shell commands.
- Prevent path traversal by resolving against an intended root, rejecting absolute paths and traversal, and verifying the resolved path remains inside that root.
- For uploads, enforce size and count limits, generate server-side filenames, store outside executable/static roots, and validate content rather than trusting extension or MIME headers.
- Do not deserialize untrusted data with formats or libraries capable of object construction or code execution.

### URLs, network calls, and public exposure

- Treat user-controlled URLs as SSRF risk. Allowlist schemes and destinations, resolve and verify addresses, and block loopback, link-local, private, metadata, and internal service ranges unless explicitly required.
- Revalidate redirect destinations; redirects must not bypass destination checks.
- Set explicit connect, read, and overall timeouts. Bound retries and response sizes.
- Verify TLS certificates. Do not disable verification or accept all certificates as a workaround.
- Bind services to the narrowest interface and expose only required ports. Do not assume an internal-looking hostname or port is private.
- Public endpoints need explicit authentication or a documented reason for anonymous access, plus abuse controls appropriate to cost and impact.
- Verify CORS, proxy trust, forwarded-header handling, and origin checks against the actual deployment topology. Never use wildcard origins with credentials.

### Secrets and sensitive data

- Never hardcode, print, commit, or copy secrets, tokens, private keys, passwords, cookies, credentials, or sensitive operator values.
- Use the repository's designated secret/config mechanism. Keep examples unmistakably nonfunctional.
- Do not expose secrets through command arguments, build layers, client bundles, Terraform outputs, exception text, telemetry, or test snapshots.
- Redact sensitive headers and fields from logs. Log stable identifiers and outcomes, not credentials or full payloads.
- Do not read unrelated secret files while debugging. Request only the minimum information needed.
- Use established password hashing, authenticated encryption, signature, and token libraries. Never design custom cryptography.
- Use cryptographically secure randomness for tokens and identifiers that grant access. Apply explicit expiry, rotation, and revocation behavior where relevant.
- Compare secrets with constant-time primitives when the framework does not already do so.

### Sessions, tokens, and browser security

- Use secure, `HttpOnly`, appropriately scoped cookies with a deliberate `SameSite` policy for browser sessions.
- Protect state-changing cookie-authenticated requests against CSRF.
- Rotate session identifiers after authentication and privilege changes; invalidate sessions on logout and credential reset where the system supports it.
- Validate token signature, algorithm, issuer, audience, expiry, and not-before claims. Never trust unsigned token claims.
- Do not store long-lived bearer tokens in browser-accessible storage unless the established architecture explicitly accepts that risk.
- Preserve framework protections against XSS, clickjacking, content sniffing, and open redirects. Do not disable them to make an integration pass.

### Data integrity, errors, and availability

- Perform security checks and state changes atomically when races could permit double-spend, duplicate execution, stale authorization, or time-of-check/time-of-use bugs.
- Use database constraints for invariants that must survive concurrency.
- Make privileged mutations idempotent where retries are possible.
- Return generic errors to untrusted clients while retaining actionable, redacted server diagnostics.
- Do not silently continue after failed validation, signature checks, authorization, secret loading, migration, or policy enforcement.
- Bound request bodies, pagination, recursion, decompression, regex work, concurrency, queues, and fan-out. Consider attacker-controlled cost.
- Rate limits are defense in depth, not a substitute for authorization or bounded work.

### Dependencies and generated code

- Prefer existing, maintained project dependencies and platform primitives.
- Do not add a package merely to avoid writing a small, auditable function.
- Verify a new dependency's source, maintenance status, license fit, transitive impact, and exact package identity before adding it. Watch for typosquatting.
- Use the package manager; do not invent versions or integrity hashes.
- Never paste code from search results without checking its behavior, license implications, and compatibility.
- Do not weaken lint, type, test, signature, provenance, or vulnerability checks to get a build passing.
- Treat generated code and AI output as untrusted code requiring the same review and tests as handwritten code.

### Infrastructure, containers, and CI/CD

- Apply least privilege to users, service accounts, IAM/RBAC, capabilities, mounts, devices, networks, and filesystem access.
- Do not use privileged containers, host networking/PID/IPC, Docker socket mounts, broad host paths, or wildcard RBAC unless the requirement is explicit and the risk is documented.
- Run containers as a non-root user where supported; use a read-only root filesystem and drop capabilities when compatible.
- Pin deployable artifacts to an immutable version or digest according to repository policy. Avoid floating tags for production.
- Keep secrets out of images, build arguments, source-controlled values, Terraform state outputs, and CI logs.
- Separate untrusted pull-request code from privileged secrets and deployment credentials. Do not run fork-controlled code in a privileged workflow context.
- Scope CI permissions explicitly and minimally. Pin third-party automation according to project policy.
- Do not expose a new ingress, DNS record, load-balancer port, firewall rule, or proxy route without tracing the full public path and its authentication/TLS controls.
- For Terraform and manifests, inspect the rendered plan or output; successful parsing does not prove secure behavior.

## Common AI failure patterns to reject

- Inventing a configuration key, middleware guarantee, library API, or secure default.
- Adding `0.0.0.0/0`, wildcard origins, wildcard permissions, anonymous access, `chmod 777`, `--privileged`, or disabled TLS checks to resolve connectivity.
- Catching all exceptions and returning success, empty data, or permissive fallback behavior.
- Trusting client-supplied user IDs, tenant IDs, roles, prices, filenames, callback URLs, or authorization claims.
- Using regex alone to sanitize a dangerous sink instead of avoiding the sink or using a structured API.
- Logging full request bodies, environment variables, headers, tokens, or third-party responses.
- Treating base64, hashing, obscurity, private repositories, or internal networks as encryption or access control.
- Adding a security comment, validation-looking helper, or test that never exercises the enforcement point.
- Fixing a security test by weakening the assertion, skipping it, or broadening permissions.
- Preserving an insecure old path as a compatibility fallback. Follow this repository's hard-cut rule unless the user explicitly requests a bounded migration bridge.
- Making unrelated cleanup during a security fix, which obscures the review and increases regression risk.

## Verification checklist

Use the checks relevant to the change:

- [ ] Untrusted inputs and trust boundaries are identified.
- [ ] Authentication and resource-level authorization are enforced server-side.
- [ ] Validation is explicit and dangerous sinks use structured APIs.
- [ ] Denied, malformed, expired, cross-user, and cross-tenant cases are tested.
- [ ] Secrets and sensitive data do not appear in code, logs, output, state, or artifacts.
- [ ] Network destinations, redirects, timeouts, TLS, and exposure are constrained.
- [ ] Permissions and runtime privileges are minimal.
- [ ] Failure paths fail closed without leaking sensitive details.
- [ ] Work, retries, payload sizes, and concurrency are bounded.
- [ ] Security-sensitive behavior was verified against real documentation, source, rendered config, or runtime evidence.
- [ ] New dependencies and automation are pinned and reviewed according to project policy.
- [ ] Tests, static checks, and relevant scanners pass without suppressing findings.

## Reporting findings

When reviewing, report only actionable findings:

- **Critical**: likely credential compromise, remote code execution, authentication bypass, broad data exposure, or destructive privileged action.
- **High**: practical privilege escalation, injection, SSRF, cross-tenant access, secret leakage, or major public exposure.
- **Medium**: exploitable weakness requiring meaningful preconditions or with limited impact.
- **Low**: concrete defense-in-depth gap with a plausible failure mode.

For each finding, include the affected location, attack or failure path, impact, and smallest safe correction. Distinguish verified vulnerabilities from assumptions needing confirmation. Do not inflate style preferences into security findings.
