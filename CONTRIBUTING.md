# Contributing

Changes must go through a pull request and receive approval before merging. Do not push directly to `main`, force-push it, delete it, or bypass review.

1. Fork the repository or create a feature branch if you have access.
2. Make a focused change and update relevant documentation.
3. Run `./scripts/test.sh` on macOS and manually check affected interactions.
4. Open a pull request explaining the behavior, validation, and privacy impact.
5. Wait for code-owner approval and passing required checks. New commits invalidate earlier approvals.

The code owner is **@GeethaPardheev (Geetha Pardheev)**.

Never commit credentials, personal diagnostic files, temporary generation data, or build caches. Changes to keyboard monitoring, audio detection, permissions, workflows, and repository policy need explicit attention during review.

GitHub protection settings enforce merge rules; this document alone cannot enforce them. Public visitors can read or fork the repository and propose changes, but cannot modify this repository without write access. Repository administrators can change protection settings, so these rules are not an immutable lock against the owner.

With administrator enforcement enabled, even an owner cannot directly push to `main`. GitHub does not allow approving your own pull request. If the sole code owner authors a pull request, a separately authorized code owner/reviewer arrangement is needed; do not silently bypass protection.
