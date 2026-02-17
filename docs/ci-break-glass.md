# CI Break-Glass Procedure

## Owner

Repository administrator (`tomcat65`). Only the owner may execute this procedure.

## When to Use

Emergency merge when CI is broken due to infrastructure issues (GitHub Actions outage, runner failures) — NOT to bypass legitimate test/wiring failures.

## Disable Branch Protection

```bash
gh api -X PUT repos/tomcat65/spectra/branches/main/protection \
  -f required_status_checks='null' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='null' \
  -f restrictions='null'
```

## Perform Emergency Merge

```bash
git checkout main
git merge <branch>
git push origin main
```

## Re-enable Branch Protection

```bash
gh api -X PUT repos/tomcat65/spectra/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Lint", "Tests", "Wiring"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

## Post-Incident Audit

After every break-glass use, create a record:

```markdown
### Break-Glass Incident — [DATE]
- **Who:** [admin username]
- **Why:** [reason CI was bypassed]
- **What merged:** [branch name, commit hash]
- **Duration unprotected:** [time from disable to re-enable]
- **Follow-up:** [what was done to prevent recurrence]
```

Append to this file under the "Incident Log" section below.

---

## Incident Log

(No incidents recorded.)
