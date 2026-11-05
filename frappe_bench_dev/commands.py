"""`bench dev`: run a site in development mode and open it in the browser.

Starts `bench serve` (Python auto-reload) and `bench watch` (JS/CSS rebuild)
next to whatever else runs on the bench, waits until the site answers, opens
it in the browser and streams the logs. Ctrl+C stops everything it started.
"""

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import webbrowser

import click

DEFAULT_PORT = 8030
READY_TIMEOUT = 90  # seconds


# --------------------------------------------------------------------- output
def say(msg):
	click.secho("==> ", fg="blue", bold=True, nl=False)
	click.echo(msg)


def warn(msg):
	click.secho(f"!! {msg}", fg="yellow", err=True)


def die(msg):
	click.secho(f"xx {msg}", fg="red", err=True)
	sys.exit(1)


# ---------------------------------------------------------------------- bench
def get_bench_path():
	import frappe.utils

	return frappe.utils.get_bench_path()


def get_sites(bench_path):
	import frappe.utils

	return frappe.utils.get_sites(os.path.join(bench_path, "sites"))


def get_default_site(bench_path):
	try:
		with open(os.path.join(bench_path, "sites", "common_site_config.json")) as f:
			return json.load(f).get("default_site") or ""
	except Exception:
		return ""


# --------------------------------------------------------- remembered choice
def _last_site_file(bench_path):
	cache = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
	return os.path.join(cache, "frappe-bench-dev", "last-site" + bench_path.replace(os.sep, "_"))


def read_last_site(bench_path):
	try:
		with open(_last_site_file(bench_path)) as f:
			return f.read().strip()
	except Exception:
		return ""


def save_last_site(bench_path, site):
	try:
		path = _last_site_file(bench_path)
		os.makedirs(os.path.dirname(path), exist_ok=True)
		with open(path, "w") as f:
			f.write(site + "\n")
	except Exception:
		pass


# --------------------------------------------------------------- site choice
def site_given_on_command_line():
	"""True when the user typed `bench --site X dev` (or set FRAPPE_SITE).

	Frappe fills ctx.obj["sites"] with default_site even when --site is not
	given, so look at the actual arguments to tell the two apart.
	"""
	return any(a == "--site" or a.startswith("--site=") for a in sys.argv) or bool(
		os.environ.get("FRAPPE_SITE")
	)


def choose_site(sites, default):
	click.echo()
	click.echo(f"This bench has {len(sites)} sites:")
	for i, s in enumerate(sites, 1):
		mark = click.style("  <- default", fg="green") if s == default else ""
		click.echo(f"  {i:>2}) {s}{mark}")

	hint = f"1-{len(sites)} or name" + (f", Enter = {default}" if default else "")
	while True:
		ans = click.prompt(f"Choose a site [{hint}]", default=default or "", show_default=False).strip()
		if ans.isdigit() and 1 <= int(ans) <= len(sites):
			return sites[int(ans) - 1]
		if ans in sites:
			return ans
		click.echo("  Not a valid choice, try again.")


def resolve_site(bench_path, explicit_site):
	sites = get_sites(bench_path)
	if not sites:
		die(f"No sites found in {bench_path}/sites.")

	if explicit_site:
		if explicit_site not in sites:
			die(f"Site '{explicit_site}' does not exist. Available: {' '.join(sites)}")
		return explicit_site

	if len(sites) == 1:
		return sites[0]

	default = read_last_site(bench_path)
	if default not in sites:
		default = get_default_site(bench_path)
	if default not in sites:
		default = ""

	if sys.stdin.isatty():
		site = choose_site(sites, default)
		save_last_site(bench_path, site)
		return site
	if default:
		return default
	die(f"This bench has several sites, pass one with --site: {' '.join(sites)}")


# ---------------------------------------------------------------- networking
def port_in_use(port):
	with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
		s.settimeout(1)
		return s.connect_ex(("127.0.0.1", port)) == 0


def site_up(url):
	try:
		with urllib.request.urlopen(f"{url}/api/method/ping", timeout=3) as r:
			return b"pong" in r.read()
	except Exception:
		return False


def open_browser(url):
	"""Open the URL on the user's machine. Returns True if something was launched."""
	try:
		if os.environ.get("BROWSER"):  # VS Code (incl. Remote-SSH) sets this
			subprocess.Popen(
				[os.environ["BROWSER"], url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
			)
			return True
		if sys.platform == "darwin":
			subprocess.Popen(["open", url])
			return True
		if shutil.which("wslview"):
			subprocess.Popen(["wslview", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
			return True
		if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
			return webbrowser.open(url)
	except Exception:
		pass
	return False


# ----------------------------------------------------------------- processes
class Processes:
	def __init__(self):
		self.procs = []

	def start(self, cmd, cwd, log_path=None):
		out = open(log_path, "w") if log_path else None
		p = subprocess.Popen(
			cmd,
			cwd=cwd,
			stdout=out,
			stderr=subprocess.STDOUT if out else None,
			stdin=subprocess.DEVNULL,
			start_new_session=True,  # own process group, so children stop too
		)
		self.procs.append(p)
		return p

	def stop(self):
		for p in self.procs:
			try:
				os.killpg(p.pid, signal.SIGTERM)
			except (ProcessLookupError, PermissionError):
				pass
		deadline = time.time() + 10
		for p in self.procs:
			try:
				p.wait(timeout=max(0.1, deadline - time.time()))
			except subprocess.TimeoutExpired:
				try:
					os.killpg(p.pid, signal.SIGKILL)
				except ProcessLookupError:
					pass


# ------------------------------------------------------------------- command
@click.command("dev")
@click.option("--port", default=DEFAULT_PORT, show_default=True, type=int, help="Port for the dev server")
@click.option("--no-watch", is_flag=True, default=False, help="Do not run bench watch (JS/CSS)")
@click.option("--no-browser", is_flag=True, default=False, help="Do not open a browser")
@click.pass_context
def dev(ctx, port, no_watch, no_browser):
	"""Run a site in development mode with auto-reload and open it in the browser.

	\b
	Examples:
	  bench dev                       # pick a site (menu if several), port 8030
	  bench --site mysite.local dev   # a specific site
	  bench dev --port 8031 --no-watch
	"""
	bench_path = get_bench_path()
	sites_from_ctx = (ctx.obj or {}).get("sites") or []
	explicit = sites_from_ctx[0] if (site_given_on_command_line() and len(sites_from_ctx) == 1) else None
	site = resolve_site(bench_path, explicit)

	bench_cmd = shutil.which("bench") or "bench"
	url = f"http://localhost:{port}"
	logs_dir = os.path.join(bench_path, "logs")
	os.makedirs(logs_dir, exist_ok=True)
	serve_log = os.path.join(logs_dir, "dev-serve.log")
	watch_log = os.path.join(logs_dir, "dev-watch.log")

	say(f"Bench: {bench_path}")
	say(f"Site:  {site}")

	procs = Processes()
	serve_proc = None

	def handle_term(signum, frame):
		raise KeyboardInterrupt

	signal.signal(signal.SIGTERM, handle_term)

	try:
		if port_in_use(port):
			if site_up(url):
				say(f"Port {port} already serves a site, reusing it.")
			else:
				die(
					f"Port {port} is busy with something else (maybe a bench serve started without --site). "
					f"Stop it or use --port."
				)
		else:
			say(f"Starting dev server on {url}   (log: logs/dev-serve.log)")
			serve_proc = procs.start(
				[bench_cmd, "--site", site, "serve", "--port", str(port)], bench_path, serve_log
			)

		if not no_watch:
			say("Starting bench watch           (log: logs/dev-watch.log)")
			procs.start([bench_cmd, "watch"], bench_path, watch_log)

		click.secho("==> ", fg="blue", bold=True, nl=False)
		click.echo("Waiting for the server", nl=False)
		for _ in range(READY_TIMEOUT):
			if site_up(url):
				break
			click.echo(".", nl=False)
			time.sleep(1)
		click.echo()

		if not site_up(url):
			warn(f"Server did not come up in {READY_TIMEOUT}s. Last lines of logs/dev-serve.log:")
			try:
				with open(serve_log) as f:
					click.echo("".join(f.readlines()[-20:]))
			except Exception:
				pass
			sys.exit(1)

		say(f"Ready: {url}")
		if not no_browser:
			if open_browser(url):
				say("Opened in your browser.")
			else:
				say(f"Open {url} in your browser (forward port {port} first if this is a remote server).")

		click.echo()
		say("Save code and refresh the browser. Ctrl+C to stop.")
		click.echo("-" * 60)

		logs = [serve_log] + ([] if no_watch else [watch_log])
		logs = [l for l in logs if os.path.exists(l)]
		if logs and shutil.which("tail"):
			procs.start(["tail", "-n", "0", "-F", *logs], bench_path)

		while True:
			time.sleep(1)
			# If the dev server we started dies, stop the session.
			if serve_proc is not None and serve_proc.poll() is not None:
				warn("Dev server stopped. See logs/dev-serve.log")
				break
	except KeyboardInterrupt:
		click.echo()
	finally:
		if procs.procs:
			say("Stopping...")
			procs.stop()
			say("Stopped.")


commands = [dev]
