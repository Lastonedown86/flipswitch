# FlipSwitch — GitHub Growth & Sponsorship Plan

## Goal

Build community adoption modeled on NebulaLogger's trajectory: strong GitHub presence, organic developer discovery, and sustainable sponsorship income. NebulaLogger reached ~1,000 stars and meaningful sponsorship without AppExchange — FlipSwitch follows the same playbook.

---

## Foundation: The Repository Must Convert

Stars and sponsorship don't come from the code — they come from a developer landing on your repo and immediately understanding the value. This is the foundation everything else builds on.

### README Requirements (do this before any promotion)

```
README structure:
  1. One-line tagline — what it does in plain English
  2. Badges — package version, coverage, license, GitHub Sponsors
  3. 30-second demo GIF — shows the kill switch or gate component working
  4. The Problem (3 bullet points max)
  5. The Solution (code snippet — FeatureFlag.isEnabled one-liner)
  6. Quick Install (one command, sandbox + production links)
  7. Feature list (scannable, not exhaustive)
  8. Docs link / full API reference
  9. Contributing guide link
  10. Sponsor CTA
```

The demo GIF is the highest-leverage item. Developers decide whether to star a repo in the first 10 seconds. A GIF showing a feature toggling in a Salesforce org without a deployment is more convincing than any amount of copy.

### Repo Hygiene Checklist

- [ ] `CONTRIBUTING.md` — how to file issues, open PRs, run tests
- [ ] `CODE_OF_CONDUCT.md` — required for community trust
- [ ] Issue templates — Bug Report, Feature Request, Question
- [ ] PR template — checklist for contributors
- [ ] GitHub Actions CI — tests run automatically on PRs (shows green badge)
- [ ] `CHANGELOG.md` — updated every release
- [ ] GitHub Releases with release notes (not just git tags)
- [ ] Topics set on repo: `salesforce`, `apex`, `feature-flags`, `lwc`, `salesforce-dx`, `progressive-delivery`
- [ ] Social preview image (1280×640) — repo looks professional in link previews

---

## GitHub Sponsors Setup

### Enable Sponsors First

Go to your GitHub profile → Sponsors → "Set up GitHub Sponsors". Requires:
- US bank account or Stripe Connect (international)
- W-9 (US) or W-8BEN (international) tax form
- ~2 weeks for GitHub approval

### Sponsorship Tiers

| Tier | Monthly | Perks |
|------|---------|-------|
| Coffee | $5 | Name in SPONSORS.md, warm feelings |
| Supporter | $15 | All above + priority issue responses |
| Company | $50 | All above + logo in README (small), 1 feature request/quarter |
| Enterprise | $200 | All above + logo in README (large), direct Slack access, quarterly roadmap input |

Keep tiers simple. Most Sponsors income comes from a handful of Company/Enterprise sponsors, not many individual supporters.

### README Sponsor Placement

Sponsors section belongs in the README, **above the fold on the GitHub page** (within the first screen without scrolling). Below the tagline and badges, before the install instructions.

```markdown
## Sponsors

FlipSwitch is free and open-source. If your team relies on it, consider sponsoring:

[![Sponsor](https://img.shields.io/badge/Sponsor-❤️-pink)](https://github.com/sponsors/Lastonedown86)

<!-- Sponsor logos auto-inserted by GitHub Sponsors widget -->
```

---

## Launch Strategy

### Phase 1: Soft Launch (when v1 is installable)

Purpose: get the first 50 stars and validate the README works.

1. **Post in Unofficial Salesforce Slack** — `#apex-development` and `#javascript-lwc` channels. ~15,000 Salesforce developers active. Post once, no spam.
2. **Trailblazer Community post** in the [Apex](https://trailhead.salesforce.com/trailblazer-community/groups/0F93A000000LjDf) and [Developer](https://trailhead.salesforce.com/trailblazer-community/groups/0F93A000000LjDd) groups. Write a genuine "here's a thing I built" post, not a sales pitch. Include the problem story.
3. **Salesforce Stack Exchange** — answer 3–5 existing questions about feature toggles, deployment risk, or progressive delivery in Salesforce. Reference FlipSwitch as part of the answer (not as spam — only where genuinely relevant).
4. **Personal network** — DM 10–15 Salesforce developer contacts directly. Ask for honest feedback, not stars. Stars follow genuine engagement.

### Phase 2: Content Launch (first 6 weeks after v1)

Write one piece of content per week for 6 weeks. Quality over quantity.

| Week | Content | Platform |
|------|---------|----------|
| 1 | "Why every Salesforce deployment is a gamble (and how to fix it)" | Medium / Salesforce Ben guest post |
| 2 | Short demo video: kill switch in 60 seconds | YouTube + LinkedIn |
| 3 | "FlipSwitch vs LaunchDarkly: native vs SaaS for Salesforce" | Personal blog + Trailblazer Community |
| 4 | "How to do a canary deployment in Salesforce" (tutorial using FlipSwitch) | Medium |
| 5 | "5 ways feature flags speed up Salesforce development" | LinkedIn article |
| 6 | Retrospective: "What I learned building an open-source Salesforce package" | Any platform — developer story, not product pitch |

**Salesforce Ben** (salesforceben.com) is the highest-leverage content placement. They publish contributed articles and have a large admin/developer readership. Pitch a tutorial article — they're more likely to publish educational content than product announcements.

### Phase 3: Community Amplification

**Salesforce MVPs** — identify 3–5 MVPs whose focus is Apex/development (not admins). Tweet/DM asking for feedback. If they find it useful, they amplify naturally. Don't ask for promotion — ask for feedback.

**"Awesome Salesforce" list** — submit a PR to [github.com/mailtoharshit/awesome-salesforce](https://github.com/mailtoharshit/awesome-salesforce). Legitimate curated lists drive consistent long-tail discovery.

**Dev to (dev.to)** — cross-post the tutorial content. The Salesforce tag on dev.to has a small but engaged audience.

**Conference talks** — submit to:
- **Dreamforce** (annual, San Francisco) — highest reach, competitive to get accepted
- **TDX (Trailblazer DX)** — developer-focused, more accessible for new speakers
- **Local Salesforce User Groups (SFDGs)** — easiest path to speaking, builds local credibility first

---

## Sustained Growth Tactics

### Release Cadence

Regular releases keep the project visible in GitHub's "recently updated" filters and give you repeated opportunities to post updates.

- Aim for a release every 4–6 weeks during active development
- Write proper release notes (not just a list of commits)
- Tweet/post each release with one highlight feature or fix

### GitHub Discussions

Enable GitHub Discussions. The `Q&A` category lets users ask questions publicly — answers become searchable content that drives organic discovery. NebulaLogger uses this effectively.

### Showcase Installs

When an org installs and uses FlipSwitch publicly, ask if they'll add themselves to a `ADOPTERS.md` or a "Used by" section in the README. Social proof accelerates adoption.

### Respond to Every Issue (especially early)

Response time in the first 30 days of a repo's life determines whether it looks active or abandoned. A repo with 5 open unanswered issues looks dead. A repo with 5 closed issues with thoughtful responses looks maintained. Prioritize closing and responding over building features in the first month.

---

## Metrics to Track

| Metric | Target (3 months) | Target (12 months) |
|--------|------------------|-------------------|
| GitHub stars | 50 | 250+ |
| Package installs | 20 orgs | 100+ orgs |
| GitHub Sponsors | 1–2 | 5–10 |
| Monthly sponsorship income | $50 | $500+ |
| Issues filed (signal of usage) | 10 | 50+ |
| Contributors | 1 (you) | 3–5 |

NebulaLogger benchmarks for comparison: reached ~500 stars in year 1, ~1,000 by year 2–3. FlipSwitch solves a narrower (but more urgent) problem, which may drive faster initial traction but a smaller long-term ceiling.

---

## What Not to Do

- **Don't post in every Salesforce community simultaneously on day 1** — it reads as spam and burns goodwill in communities that require genuine participation.
- **Don't ask for stars directly** — "please star this repo" posts are ignored and create a negative impression.
- **Don't neglect issues** — an unanswered bug report is worse for reputation than not posting at all.
- **Don't over-invest in Twitter/X early** — the Salesforce developer community is more active on LinkedIn, Trailblazer Community, and Slack than Twitter.
- **Don't launch before the README and demo GIF are ready** — you only get one first impression with each community.

---

## Quick Reference: Salesforce Community Channels

| Channel | Audience | Best use |
|---------|----------|----------|
| Unofficial SF Slack | Developers, architects | Soft launch, Q&A |
| Trailblazer Community | Admins + devs | Announcements, tutorials |
| Salesforce Stack Exchange | Developers | Answer questions, reference tool |
| Salesforce Ben | Admins + devs | Guest tutorial articles |
| LinkedIn | Professionals | Release announcements, articles |
| Dreamforce / TDX | Everyone | Talks, demos |
| Local SFDGs | Local community | First speaking experience |
| dev.to | Developers | Cross-posted technical content |
| "Awesome Salesforce" list | Developers (discovery) | Evergreen listing |
