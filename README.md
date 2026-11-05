# frappe-bench-dev

One command to run a Frappe site in development mode and open it in your browser,
so code changes show up live instead of needing a bench restart each time.

```bash
./dev.sh
```

## The problem it solves

When you work on a Frappe bench on a remote server through **VS Code Remote-SSH**, the site is
usually running in production mode (supervisor + gunicorn). Every change then means:

1. `bench restart` (or `supervisorctl restart`) for Python changes
2. `bench build` for JS/CSS changes
3. Finding the right port, forwarding it, opening the browser, logging in again

`dev.sh` replaces all of that with a development session that runs next to production:

| | Production (supervisor) | `dev.sh` session |
|---|---|---|
| Python change | `bench restart` | Reloads automatically |
| JS / CSS change | `bench build` | Rebuilds automatically (`bench watch`) |
| Opening the site | Find the port, forward it, open it | Opens in your browser automatically |
| Stopping | `supervisorctl stop` | **Ctrl+C** |

Production keeps running untouched on its own port.

## Quick start

```bash
# 1. Get the script (once)
git clone https://github.com/devsohanur653-lab/frappe-bench-dev.git ~/frappe-bench-dev

# 2. Go to your bench (or any folder inside it) and run it
cd /path/to/your-bench
~/frappe-bench-dev/dev.sh
```

You can also copy `dev.sh` into the bench root and run `./dev.sh`.

What you'll see:

```
==> Bench: /home/me/my-bench
==> Site:  mysite.local
==> Starting dev server on http://localhost:8030   (log: logs/dev-serve.log)
==> Starting bench watch           (log: logs/dev-watch.log)
==> Waiting for the server...
==> Ready: http://localhost:8030
==> Opened in your browser.

==> Save code and refresh the browser. Ctrl+C to stop.
```

Edit code, save, refresh the browser. Press **Ctrl+C** in that terminal when you're done.

## Choosing a site

| Situation | What happens |
|---|---|
| `--site NAME` given | That site is used |
| The bench has one site | It's used automatically |
| The bench has several sites | A menu asks which one |
| Several sites, no terminal to ask in (for example run from another script) | The last site you picked, else the bench's `default_site`. If neither exists, it stops and lists the sites |

The menu looks like this:

```
This bench has 3 sites:
   1) alpha.local
   2) beta.local  <- default
   3) gamma.local
Choose a site [1-3 or name, Enter = beta.local]:
```

Type a number or a site name, or press **Enter** for the default.
The default is the site you picked last time in this bench, otherwise the bench's `default_site`.
Your last pick is stored per bench in `~/.cache/frappe-bench-dev/`.

To skip the menu, pass the site:

```bash
./dev.sh --site mysite.local
```

## Options

| Option | Default | What it does |
|---|---|---|
| `--site NAME` | menu / auto | Site to serve (see above) |
| `--port PORT` | `8030` | Port for the dev server. Also `PORT=8031 ./dev.sh` |
| `--bench DIR` | auto | Bench folder. Auto = search upward from the current folder, then from the script's folder |
| `--no-watch` | | Skip `bench watch` (Python-only work, faster start) |
| `--no-browser` | | Don't open a browser |
| `-h`, `--help` | | Show usage |

The dev server runs with `--site`, so `http://localhost:PORT` opens your site directly.
You don't need a hosts file entry like `127.0.0.1 mysite.local`.

## Working on a remote server with VS Code Remote-SSH

This is the main use case. The script runs **on the server**, in VS Code's integrated terminal.
Your laptop can run Windows, macOS or Linux, and it works the same way on all of them.

1. Connect to the server with **Remote-SSH** and open the bench folder.
2. Open a terminal in VS Code (`` Ctrl+` ``) and run `./dev.sh`.
3. VS Code forwards the port and opens the site in **your laptop's default browser**.
   If VS Code asks whether to open the external link, click **Open**.

If the browser doesn't open:

- Open the **Ports** tab in VS Code's bottom panel. The port (`8030`) should be listed with a
  green dot. If it isn't, click **Add Port** and type it.
- Then open `http://localhost:8030` on your laptop.

To view the site inside VS Code instead of your browser:

- Command palette (`Ctrl+Shift+P` / `Cmd+Shift+P`), then **Simple Browser: Show**, then `http://localhost:8030`, or
- In the **Ports** tab, hover the port and click **Preview in Editor**.

Chrome or Firefox is better for real debugging, because you get the full developer tools.

Without VS Code, use an SSH tunnel from your laptop and open `http://localhost:8030`:

```bash
ssh -L 8030:localhost:8030 user@your-server
```

## Where it works

| Setup | Works | Browser opens on |
|---|---|---|
| Remote Linux server via VS Code Remote-SSH (laptop on Windows, macOS or Linux) | Yes | Your laptop's default browser |
| Ubuntu / Linux desktop with a local bench | Yes | Default browser (`xdg-open`) |
| macOS with a local bench | Yes | Default browser (`open`) |
| Windows | Only inside **WSL** (Frappe doesn't run natively on Windows) | Windows default browser |
| Plain SSH (no VS Code) | Yes | Nothing opens automatically. Use an SSH tunnel |

Requirements: `bash`, `bench` on your `PATH`, `curl`, and Node/Yarn for `bench watch`.

## What reloads by itself and what doesn't

| You changed | What to do |
|---|---|
| Python (`.py`): controllers, APIs, hooks code | Nothing. The dev server restarts itself, then refresh the browser |
| JS / CSS / Vue in `public/` | Nothing while `bench watch` runs. Refresh the browser |
| `hooks.py` | Usually reloads. If not, Ctrl+C and run `./dev.sh` again |
| DocType JSON, new fields, patches | `bench --site SITE migrate` |
| After `git pull` or switching branches | `bench --site SITE backup`, then `bench --site SITE migrate` |
| Cached data looks stale | `bench --site SITE clear-cache` |

To create or edit DocTypes from the UI and have them saved as files in your app, also turn on developer mode
(once per site):

```bash
bench --site SITE set-config developer_mode 1
bench --site SITE clear-cache
```

## Shared benches (bench owned by another user)

On team servers the bench often belongs to one user (for example `frappe`) and developers are added
to that user's group:

```bash
sudo usermod -aG frappe your-user
```

A new group only applies after you log in again, and VS Code's server keeps the old session,
so you usually get `Permission denied`. `dev.sh` detects this and re-runs itself with `sg <group>`,
so it works right away.

For your other terminals, either run `newgrp <group>`, or fully restart VS Code's server:
command palette, then **Remote-SSH: Kill VS Code Server on Host**, then reconnect.

## Running next to production

- The dev server and production use **the same database** when they serve the same site.
  Records you create, edit or delete while testing are real.
- `bench watch` writes built assets to `sites/assets`, which production serves too.
  Production users may see your in-progress JS/CSS.
- Background jobs and the scheduler still run through production's workers, which load new Python
  code only after a production restart.
- Prefer a copy of the site (`bench new-site` + restore a backup) if you test anything destructive.

## Troubleshooting

| Message / symptom | Cause and fix |
|---|---|
| `Port 8030 is busy with something else` | Another program, or a `bench serve` started without `--site`, holds the port. Stop it, or use `--port 8031` |
| `Port 8030 already serves a site, reusing it` | A dev server is already running there. The script reuses it and doesn't start a second one |
| Browser shows `localhost does not exist` | That server was started without `--site`. Stop it and use `dev.sh` |
| `No Frappe bench found` | Run it from inside a bench folder, or pass `--bench /path/to/bench` |
| `Site 'x' does not exist` | Check the name, or run without `--site` to get the menu |
| `Server did not come up in 90s` | The last lines of `logs/dev-serve.log` are printed. Usually a Python error or a missing `migrate` |
| `Permission denied` on logs or assets | You're not in the bench owner's group, or the group isn't active yet (see Shared benches) |
| Page loads but nothing changes after editing | JS/CSS: is `bench watch` running? (Don't use `--no-watch`.) DocType: run `migrate`. Then hard-refresh with `Ctrl+Shift+R` / `Cmd+Shift+R` |
| Browser doesn't open | Open `http://localhost:PORT` yourself. On a remote server, check the VS Code **Ports** tab |

Logs: `logs/dev-serve.log` (web server, Python errors) and `logs/dev-watch.log` (JS/CSS build).
Both are also streamed in the terminal while `dev.sh` runs.

## How it works

1. Finds the bench by walking up from the current folder (folder with `sites/` and `apps/frappe/`).
2. If the bench belongs to a group you're in but haven't activated, re-runs itself through `sg`.
3. Picks the site (option, single site, or menu).
4. Checks the port: reuses a running dev server for the site, refuses if something else is there.
5. Starts `bench --site SITE serve --port PORT` and `bench watch`, each in its own process group.
6. Polls `/api/method/ping` until the site answers (up to 90 seconds).
7. Opens the URL with VS Code's `$BROWSER`, `open` (macOS), `wslview` (WSL) or `xdg-open` (Linux).
8. Streams both logs. On Ctrl+C it stops every process it started, including child processes.
