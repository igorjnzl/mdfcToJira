# Security Policy

## Supported Version

Security fixes are applied to the latest revision of the default branch.

## Report a Vulnerability

Do not report suspected vulnerabilities, credentials, signed callback URLs, tenant details, or customer data in a public issue.

Use GitHub private vulnerability reporting from the repository **Security** tab when it is enabled. Otherwise, contact the repository owner through the customer's approved private security channel.

Include:

- The affected component and revision
- Reproduction steps and expected impact
- Relevant logs with secrets and customer identifiers removed
- Any known mitigation

Do not test against customer production resources without explicit authorization.

## Secret Exposure

If a credential or signed URL is exposed, revoke or rotate it before removing it from Git history. Then run:

```powershell
.\scripts\Test-PublicRepository.ps1 -History
```
