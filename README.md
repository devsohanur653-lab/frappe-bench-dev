# frappe-bench-dev

One command to start a Frappe development session and open it in your browser.

```bash
./dev.sh
```

It starts:

- `bench serve`: Python changes reload automatically
- `bench watch`: JS/CSS changes rebuild automatically

Then it waits until the site answers and opens `http://localhost:8030` in your browser.
Press **Ctrl+C** to stop everything it started.

## Install

Clone the repo anywhere and run the script from inside your bench:

```bash
git clone https://github.com/devsohanur653-lab/frappe-bench-dev.git ~/frappe-bench-dev
cd /path/to/your-bench
~/frappe-bench-dev/dev.sh
```

Or copy `dev.sh` into the bench root and run `./dev.sh`.

## Options

| Option | Default | What it does |
|---|---|---|
| `--site SITE` | auto | Site to serve. Auto = `default_site`, else the only site in `sites/` |
| `--port PORT` | `8030` | Port for the dev server (also `PORT=8031 ./dev.sh`) |
| `--bench DIR` | auto | Bench folder. Auto = search upward from the current folder |
| `--no-watch` | | Skip `bench watch` |
| `--no-browser` | | Don't open a browser |

Logs go to `logs/dev-serve.log` and `logs/dev-watch.log` inside the bench.

Because the server runs with `--site`, `http://localhost:PORT` opens your site directly.
You don't need a hosts file entry.

## Where it works

| Setup | Works | Browser opens on |
|---|---|---|
| Remote Linux server through **VS Code Remote-SSH** (from Windows, macOS or Linux) | Yes | Your own computer. VS Code forwards the port automatically |
| Ubuntu / Linux desktop | Yes | Default browser (`xdg-open`) |
| macOS | Yes | Default browser (`open`) |
| Windows | Through **WSL** (Frappe does not run natively on Windows) | Windows default browser |
| Plain SSH without VS Code | Yes | Nothing opens. Tunnel the port: `ssh -L 8030:localhost:8030 user@server` |

To view the site inside VS Code instead, run **Simple Browser: Show** from the command palette,
or use **Preview in Editor** on the port in the **Ports** tab.

## Shared benches

On servers where the bench belongs to another user and you were added to that user's group
(`usermod -aG <group> <you>`), new groups only apply after you log in again.
The script detects this and re-runs itself with `sg <group>`, so you don't need to log out first.

## What needs more than a refresh

| You changed | Do this |
|---|---|
| Python | Nothing, the dev server reloads |
| JS / CSS | Nothing while `bench watch` runs |
| DocType JSON, patches, new fields | `bench --site SITE migrate` |
| After `git pull` or switching branches | `bench --site SITE migrate` (take a `bench --site SITE backup` first) |

## Notes

- The dev server uses the same database as any production server running on the same site.
  Records you create or delete while testing are real.
- If the port is already serving the site, the script reuses it instead of starting a second server.
  If the port is busy with something else, it stops and tells you.
