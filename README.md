# Organic Thoughts Ops

This repository is for operational checks and design-source docs for `organicthoughts.me` on Ghost(Pro).

## Scope

- DNS verification
- Launch verification (redirects, TLS, routes, portal)
- Weekly health checks
- Design workflow notes

## Not in this repo

- No content seeding scripts
- No content API/Admin API publishing flow
- Ghost remains the source of truth for posts/pages

## Install

```bash
bun install
cp .env.example .env
```

## Commands

```bash
bun run dev:site
bun run dev:ghost
bun run dev:ghost:logs
bun run dev:ghost:down
bun run theme:zip
bun run theme:validate
bun run theme:upload
bun run theme:publish
bun run check:dns
bun run check:launch
bun run check:health
```

## Environment

See `.env.example` for supported values:

- `CANONICAL_DOMAIN`
- `CHECK_DNS_RESOLVER`
- `CHECK_DNS_SOURCE`
- `EXPECTED_APEX_A`
- `EXPECTED_APEX_CNAME`
- `EXPECTED_WWW_CNAME`

`check:dns` may show `WARN` during recursive DNS propagation while still passing.

## Design Source in Git

Use this repo as design source, even with Ghost as content source:

1. Store branding tokens, typography, color, and component decisions in markdown docs here.
2. If/when you move to a custom Ghost theme, keep the theme code in this repo and deploy theme ZIPs from tagged commits.
3. Keep design changes PR-based so visual decisions remain auditable.

## Design Prototype

Minimal blog-style prototype files:

- `site/index.html`
- `site/styles.css`

Preview locally:

```bash
cd site
python3 -m http.server 4173
```

Hot reload:

```bash
bun run dev:site
```

## Live Ghost Data Integration

Current `site/index.html` uses mock thought content.

To connect this design to live Ghost data, convert it into a Ghost theme:

Theme scaffold is available at:

- `theme/organic-thoughts/default.hbs`
- `theme/organic-thoughts/index.hbs`
- `theme/organic-thoughts/post.hbs`
- `theme/organic-thoughts/page.hbs`
- `theme/organic-thoughts/assets/css/screen.css`

Publish commands:

```bash
bun run theme:zip
bun run theme:upload
```

`theme:upload` expects:

- `GHOST_ADMIN_URL`
- `GHOST_ADMIN_KEY`

You can set them in `.env`.

## Local Ghost CSS Testing

Run Ghost locally with your theme mounted live from this repo:

```bash
bun run dev:ghost
```

Then:

1. Open `http://localhost:2368/ghost` and complete setup (first run only).
2. Activate the `organic-thoughts` theme in Ghost Admin.
3. Edit `theme/organic-thoughts/assets/css/screen.css`.
4. Refresh `http://localhost:2368` to verify visual changes.

Useful commands:

```bash
bun run dev:ghost:logs
bun run dev:ghost:down
```

Local Ghost data persists under `local/ghost-content` (gitignored).

## CI Auto Deploy on `main`

This repo now includes `/Users/colemccracken/workspace/organicideas/.github/workflows/deploy-theme.yml`:

- Trigger: every push to `main` (and manual `workflow_dispatch`)
- Steps: validate theme, zip theme, upload + activate on Ghost

Required GitHub repository secrets:

- `GHOST_ADMIN_URL` (example: `https://organic-ideas.ghost.io`)
- `GHOST_ADMIN_KEY` (`id:secret` Admin API key from Ghost Admin)

## Optional Weekly Cron

```bash
0 9 * * 1 cd /path/to/repo && bun run check:health >> /path/to/repo/health.log 2>&1
```
