<div align="center">

# ⚡ frappe-bench-dev

**Live development mode for any Frappe bench, in one command.**

Save your code, refresh the browser, see the change. No `bench restart`, no `bench build`.

![Frappe](https://img.shields.io/badge/Frappe-v15%2B-0089FF?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=flat-square&logo=python&logoColor=white)
![Platforms](https://img.shields.io/badge/runs%20on-Linux%20%7C%20macOS%20%7C%20WSL-555?style=flat-square)
![VS Code Remote-SSH](https://img.shields.io/badge/VS%20Code-Remote--SSH%20ready-007ACC?style=flat-square&logo=visualstudiocode&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

```bash
bench dev
```

</div>

---

## Contents

- [Why](#-why)
- [Install](#-install)
- [Usage](#-usage)
- [Choosing a site](#-choosing-a-site)
- [VS Code Remote-SSH](#%EF%B8%8F-vs-code-remote-ssh)
- [Where it works](#-where-it-works)
- [What reloads by itself](#-what-reloads-by-itself)
- [Shared benches](#-shared-benches)
- [Running next to production](#%EF%B8%8F-running-next-to-production)
- [Troubleshooting](#-troubleshooting)
- [Without installing: `dev.sh`](#-without-installing-devsh)
- [How it works](#%EF%B8%8F-how-it-works)

---

## 💡 Why

Working on a bench over **VS Code Remote-SSH** usually means the site runs in production mode
(supervisor + gunicorn). Every change costs you a restart, a build, and a hunt for the right port.

`bench dev` starts a development session **next to** production:

| | Production (supervisor) | `bench dev` |
|---|---|---|
| 🐍 Python change | `bench restart` | ✅ reloads automatically |
| 🎨 JS / CSS change | `bench build` | ✅ rebuilds automatically |
| 🛠️ Developer mode | `set-config developer_mode 1` + `clear-cache` | ✅ on for the session, off again on exit |
| 🧹 Stale cache | `bench clear-cache` | ✅ cleared on start |
| 🌐 Open the site | find port → forward → open | ✅ opens in your browser |
| ⏹️ Stop | `supervisorctl stop` | ✅ **Ctrl+C** |

Production keeps running on its own port.

---

## 📦 Install

Once per bench:

```bash
cd /path/to/your-bench
bench get-app https://github.com/devsohanur653-lab/frappe-bench-dev
bench dev --help        # check it's there
```

> [!NOTE]
> The app only adds the `bench dev` command. It has no DocTypes and you **don't** need
> `bench install-app` on any site.

> [!WARNING]
> **Production benches:** if `sites/common_site_config.json` has `"restart_supervisor_on_update": true`,
> `bench get-app` restarts production when it finishes. If you don't want that (for example the
> database isn't migrated yet), install by hand instead. It does the same steps without the restart:
>
> ```bash
> cd /path/to/your-bench
> git clone https://github.com/devsohanur653-lab/frappe-bench-dev apps/frappe_bench_dev
> env/bin/python -m pip install -e apps/frappe_bench_dev
> [ -n "$(tail -c1 sites/apps.txt)" ] && echo >> sites/apps.txt   # apps.txt may lack a final newline
> echo frappe_bench_dev >> sites/apps.txt
> ```

**Update** to the latest version: `cd apps/frappe_bench_dev && git pull`

**Remove:** `bench remove-app frappe_bench_dev`

---

## 🚀 Usage

```bash
bench dev                          # pick a site (menu if several), port 8030
bench --site mysite.local dev      # a specific site, no menu
bench dev --port 8031              # another port
bench dev --no-watch               # Python only, skip bench watch
bench dev --no-browser             # don't open a browser
bench dev --keep-dev-mode          # leave developer_mode on after Ctrl+C
bench dev --no-dev-mode            # don't touch developer_mode
```

What you'll see:

```text
==> Bench: /home/me/my-bench
==> Site:  mysite.local
==> Developer mode: turned on (goes back off when you press Ctrl+C)
==> Clearing cache...
==> Starting dev server on http://localhost:8030   (log: logs/dev-serve.log)
==> Starting bench watch           (log: logs/dev-watch.log)
==> Waiting for the server...
==> Ready: http://localhost:8030
==> Opened in your browser.

==> Save code and refresh the browser. Ctrl+C to stop.
```

### Options

| Option | Default | What it does |
|---|---|---|
| `bench --site NAME dev` | menu / auto | Site to serve. `--site` goes **before** `dev`, like other bench site commands |
| `--port PORT` | `8030` | Port for the dev server |
| `--no-watch` | | Skip `bench watch` (faster start when you only touch Python) |
| `--no-browser` | | Don't open a browser |
| `--keep-dev-mode` | | Leave `developer_mode` on after Ctrl+C |
| `--no-dev-mode` | | Don't change `developer_mode` (cache is still cleared) |
| `--help` | | Show usage |

### Developer mode and cache

After you pick a site, `bench dev`:

1. Turns on `developer_mode` in `sites/SITE/site_config.json`, unless it's already on
   (in the site's config or in `common_site_config.json`).
2. Runs `bench --site SITE clear-cache`.
3. On **Ctrl+C**, puts `developer_mode` back exactly as it was (removes the key, or restores `0`)
   and clears the cache again. If it was already on, it's left alone.

With developer mode on you can create and edit DocTypes from the UI and they're saved as JSON
files in your app, ready to commit.

> [!TIP]
> The dev server runs with `--site`, so `http://localhost:PORT` opens your site directly.
> No hosts file entry like `127.0.0.1 mysite.local` is needed.

---

## 🧭 Choosing a site

| Situation | What happens |
|---|---|
| `bench --site NAME dev` | That site is used |
| One site in the bench | Used automatically |
| Several sites | A menu asks which one |
| Several sites, no terminal to ask in | Last site you picked, else `default_site`. Neither? It stops and lists the sites |

```text
This bench has 3 sites:
   1) alpha.local
   2) beta.local  <- default
   3) gamma.local
Choose a site [1-3 or name, Enter = beta.local]:
```

Type a number or a name, or press **Enter** for the default.
Your last pick is remembered per bench in `~/.cache/frappe-bench-dev/`.

---

## 🖥️ VS Code Remote-SSH

`bench dev` runs **on the server**, in VS Code's terminal. Your laptop can be Windows, macOS or Linux.

1. Connect with **Remote-SSH** and open the bench folder.
2. Open a terminal (`` Ctrl+` ``) and run `bench dev`.
3. VS Code forwards the port and opens the site in **your laptop's browser**.
   If it asks to open an external link, click **Open**.

<details>
<summary><b>Browser didn't open?</b></summary>

<br>

- Open the **Ports** tab in the bottom panel. `8030` should have a green dot. If not, **Add Port** → `8030`.
- Open `http://localhost:8030` on your laptop.

</details>

<details>
<summary><b>View the site inside VS Code</b></summary>

<br>

- `Ctrl+Shift+P` / `Cmd+Shift+P` → **Simple Browser: Show** → `http://localhost:8030`, or
- **Ports** tab → hover the port → **Preview in Editor**.

Chrome or Firefox is still better for debugging: you get the full developer tools.

</details>

<details>
<summary><b>Plain SSH, no VS Code</b></summary>

<br>

Tunnel the port from your laptop, then open `http://localhost:8030`:

```bash
ssh -L 8030:localhost:8030 user@your-server
```

</details>

---

## 🌍 Where it works

| Setup | Works | Browser opens on |
|---|:---:|---|
| Remote server via VS Code Remote-SSH (any laptop OS) | ✅ | Your laptop's default browser |
| Ubuntu / Linux desktop | ✅ | Default browser |
| macOS | ✅ | Default browser |
| Windows | ✅ via **WSL** | Windows default browser |
| Plain SSH | ✅ | Use an SSH tunnel |

Requires Frappe **v15+** and Node/Yarn for `bench watch` (any bench already has them).

---

## 🔄 What reloads by itself

| You changed | What to do |
|---|---|
| 🐍 Python: controllers, APIs | Nothing. Refresh the browser |
| 🎨 JS / CSS / Vue in `public/` | Nothing while `bench watch` runs. Refresh the browser |
| 🪝 `hooks.py` | Usually reloads. If not, Ctrl+C and `bench dev` again |
| 🧱 DocType JSON, new fields, patches | `bench --site SITE migrate` |
| 🔀 After `git pull` / switching branch | `bench --site SITE backup` → `bench --site SITE migrate` |
| 🧹 Stale cached data | `bench --site SITE clear-cache` |

> [!TIP]
> `bench dev` turns on developer mode for the session, so DocTypes you create or edit from the UI
> are saved as files in your app. See [Developer mode and cache](#developer-mode-and-cache).

---

## 👥 Shared benches

On team servers the bench often belongs to one user (say `frappe`) and developers join that user's group:

```bash
sudo usermod -aG frappe your-user
```

A new group only applies after a fresh login, and VS Code's server keeps the old one.
Until then **every** bench command fails with:

```text
PermissionError: [Errno 13] Permission denied: '.../logs/bench.log'
```

| Fix | How |
|---|---|
| Right now, once | `sg frappe -c "bench dev"` |
| This terminal | `newgrp frappe`, then `bench dev` |
| For good | `Ctrl+Shift+P` → **Remote-SSH: Kill VS Code Server on Host** → reconnect |
| No app needed | Use [`dev.sh`](#-without-installing-devsh), which switches the group by itself |

---

## ⚠️ Running next to production

> [!CAUTION]
> The dev server and production share **the same database** when they serve the same site.
> Records you create, edit or delete while testing are real.

- `bench watch` writes to `sites/assets`, which production serves too. Users may see in-progress JS/CSS.
- Background jobs and the scheduler run on production's workers, which pick up new Python only after a production restart.
- `developer_mode` lives in the site's config, so while `bench dev` runs it's on for **production too**:
  users see full error tracebacks, and DocType edits made from the UI write files into the app.
  It goes back off when you press Ctrl+C. Use `--no-dev-mode` if that's a problem on this site.
- If the terminal is killed hard (`kill -9`, lost SSH session with no tmux), the cleanup can't run.
  Check `developer_mode` in `sites/SITE/site_config.json` afterwards.
- Testing something destructive? Use a copy of the site (`bench new-site` + restore a backup).

---

## 🩺 Troubleshooting

<details>
<summary><b>Show common problems</b></summary>

<br>

| Message / symptom | Cause and fix |
|---|---|
| `No such command 'dev'` | App isn't in this bench. See [Install](#-install) |
| `Permission denied: .../logs/bench.log` | Group not active in this terminal. See [Shared benches](#-shared-benches) |
| `Port 8030 is busy with something else` | Another program, or a `bench serve` without `--site`, holds it. Stop it or use `--port 8031` |
| `Port 8030 already serves a site, reusing it` | A dev server is already running there. It's reused, not duplicated |
| Browser shows `localhost does not exist` | That server was started without `--site`. Stop it and use `bench dev` |
| `Site 'x' does not exist` | Check the name, or drop `--site` to get the menu |
| `Server did not come up in 90s` | The end of `logs/dev-serve.log` is printed. Usually a Python error or a missing `migrate` |
| Edits don't show up | JS/CSS: is `bench watch` running? DocType: `migrate`. Then hard-refresh: `Ctrl+Shift+R` / `Cmd+Shift+R` |
| Browser doesn't open | Open `http://localhost:PORT` yourself; on a server, check the **Ports** tab |

Logs: `logs/dev-serve.log` (web server, Python errors) and `logs/dev-watch.log` (JS/CSS build).
Both also stream in the terminal while `bench dev` runs.

</details>

---

## 🐚 Without installing: `dev.sh`

A standalone shell script with the same behaviour, for benches where you can't add an app.
It also activates the bench owner's group by itself.

```bash
cd /path/to/your-bench          # or any folder inside it
/path/to/frappe-bench-dev/dev.sh [--site NAME] [--port PORT] [--bench DIR] [--no-watch] [--no-browser] \
                                 [--keep-dev-mode] [--no-dev-mode]
```

---

## ⚙️ How it works

<details>
<summary><b>Step by step</b></summary>

<br>

1. Frappe loads `frappe_bench_dev/commands.py` from every app in `apps.txt`. That's how `bench dev` exists.
2. Picks the site: `--site`, the only site, or the menu.
3. Turns on `developer_mode` (remembering the old value) and runs `clear-cache`.
4. Checks the port: reuses a running dev server for the site, refuses if something else is there.
5. Starts `bench --site SITE serve --port PORT` and `bench watch`, each in its own process group.
6. Polls `/api/method/ping` until the site answers (up to 90 s).
7. Opens the URL via VS Code's `$BROWSER`, `open` (macOS), `wslview` (WSL) or the default browser (Linux).
8. Streams both logs. On Ctrl+C it stops every process it started (children included),
   restores `developer_mode` and clears the cache again.

</details>

---

<div align="center">

MIT © Sohanur Rahman · [Report an issue](https://github.com/devsohanur653-lab/frappe-bench-dev/issues)

</div>
