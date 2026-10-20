"""Exercise the startup hook against temporary synthetic files, never live hashes."""

from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

from jinja2 import Environment, StrictUndefined
import yaml


ROOT = Path(__file__).resolve().parent
HOOK = ROOT / "files/rtorrent-rutorrent/99-protect-htpasswd.sh"
NAMES = ("rpc.htpasswd", "rutorrent.htpasswd", "webdav.htpasswd")


class PasswordPermissionsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rtorrent-permissions-")
        self.addCleanup(self.temporary.cleanup)
        self.passwd = Path(self.temporary.name)
        for name in NAMES:
            path = self.passwd / name
            path.write_bytes(b"synthetic-test-data\n")
            path.chmod(0o644)

    def run_hook(self):
        # Only rewrite the test filesystem root; production has no path override.
        script = HOOK.read_text().replace("/passwd/", f"{self.passwd}/")
        return subprocess.run(["sh", "-c", script], capture_output=True, check=False)

    def assert_modes(self, expected):
        for name in NAMES:
            self.assertEqual(stat.S_IMODE((self.passwd / name).stat().st_mode), expected)

    def test_upstream_modes_are_restricted_without_changing_credentials(self):
        before = {name: (self.passwd / name).stat() for name in NAMES}
        unrelated = self.passwd / "unmanaged.htpasswd"
        unrelated.write_bytes(b"unmanaged-test-data\n")
        unrelated.chmod(0o644)
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_modes(0o640)
        for name in NAMES:
            path = self.passwd / name
            self.assertEqual(path.read_bytes(), b"synthetic-test-data\n")
            self.assertEqual(path.stat().st_mtime_ns, before[name].st_mtime_ns)
            self.assertEqual(path.stat().st_uid, before[name].st_uid)
            self.assertEqual(path.stat().st_gid, before[name].st_gid)
            self.assertEqual(path.stat().st_ino, before[name].st_ino)
        self.assertEqual(stat.S_IMODE(unrelated.stat().st_mode), 0o644)

    def test_repeated_startup_and_empty_files_are_supported(self):
        (self.passwd / NAMES[0]).write_bytes(b"")
        for _ in range(2):
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_modes(0o640)
        self.assertEqual((self.passwd / NAMES[0]).read_bytes(), b"")

    def test_symlink_is_refused_before_any_file_changes(self):
        path = self.passwd / NAMES[-1]
        path.unlink()
        path.symlink_to(self.passwd / NAMES[0])
        self.assertNotEqual(self.run_hook().returncode, 0)
        self.assert_modes(0o644)

    def test_missing_file_is_refused_before_any_file_changes(self):
        (self.passwd / NAMES[-1]).unlink()
        self.assertNotEqual(self.run_hook().returncode, 0)
        for name in NAMES[:-1]:
            self.assertEqual(stat.S_IMODE((self.passwd / name).stat().st_mode), 0o644)

    def test_directory_is_refused_before_any_file_changes(self):
        path = self.passwd / NAMES[-1]
        path.unlink()
        path.mkdir()
        self.assertNotEqual(self.run_hook().returncode, 0)
        for name in NAMES[:-1]:
            self.assertEqual(stat.S_IMODE((self.passwd / name).stat().st_mode), 0o644)

    def test_compose_mounts_hook_read_only_only_in_rtorrent(self):
        values = {
            "rtorrent_rutorrent_geoip_enabled": False,
            "rtorrent_rutorrent_image": "example/rtorrent:test",
            "rtorrent_rutorrent_media_network_enabled": False,
            "rtorrent_rutorrent_auth_enabled": False,
            "rtorrent_rutorrent_publish_rutorrent_port": False,
            "rtorrent_rutorrent_volumes": [],
            "rtorrent_rutorrent_storage_pools": [],
            "rtorrent_rutorrent_delete_guard_enabled": False,
            "rtorrent_rutorrent_media_pruner_backups": "",
            "rtorrent_rutorrent_service_dir": "/srv/rtorrent",
            "rtorrent_rutorrent_logs_image": "bash:test",
            "rtorrent_rutorrent_log_volume": "/srv/logs:/log",
            "rtorrent_rutorrent_network_name": "torrent-test",
        }
        env = Environment(undefined=StrictUndefined)
        env.filters["bool"] = bool
        text = env.from_string((ROOT / "files/rtorrent-rutorrent/compose.yaml").read_text())
        compose = yaml.safe_load(text.render(**values))
        mount = (
            "/srv/rtorrent/init/99-protect-htpasswd.sh:"
            "/usr/local/share/rtorrent/99-protect-htpasswd.sh:ro"
        )
        self.assertIn(mount, compose["services"]["rtorrent-rutorrent"]["volumes"])
        self.assertNotIn(mount, compose["services"]["rtorrent-logs"]["volumes"])
        service = compose["services"]["rtorrent-rutorrent"]
        self.assertEqual(service["entrypoint"], ["/bin/sh", "/usr/local/sbin/rtorrent-passwd-init"])
        self.assertIn(
            "/srv/rtorrent/init/start-with-passwd-protection.sh:"
            "/usr/local/sbin/rtorrent-passwd-init:ro", service["volumes"],
        )
        self.assertFalse(any(":/etc/cont-init.d/" in value for value in service["volumes"]))

    def test_entrypoint_copies_hook_and_execs_upstream_with_arguments(self):
        source = self.passwd / "source.sh"
        source.write_bytes(HOOK.read_bytes())
        target = self.passwd / "installed.sh"
        upstream = self.passwd / "upstream"
        upstream.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        upstream.chmod(0o755)
        script = (ROOT / "files/rtorrent-rutorrent/start-with-passwd-protection.sh").read_text()
        script = script.replace("/usr/local/share/rtorrent/99-protect-htpasswd.sh", str(source))
        script = script.replace("/etc/cont-init.d/99-protect-htpasswd.sh", str(target))
        script = script.replace('/init "$@"', f'{upstream} "$@"')
        result = subprocess.run(
            ["sh", "-c", script, "--", "one argument", "two"], capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"one argument\ntwo\n")
        self.assertEqual(target.read_bytes(), source.read_bytes())
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)

    def test_playbook_installs_root_owned_hook_and_restarts_on_hook_change(self):
        tasks = yaml.safe_load((ROOT / "playbook.yaml").read_text())[0]["tasks"]
        install = next(task for task in tasks if task.get("register") == "rtorrent_rutorrent_passwd_init")
        self.assertEqual(install["ansible.builtin.copy"]["owner"], "root")
        self.assertEqual(install["ansible.builtin.copy"]["group"], "root")
        self.assertEqual(install["ansible.builtin.copy"]["mode"], "0755")
        restart = next(task for task in tasks if task.get("name") == "Restart rTorrent/ruTorrent when config changed")
        self.assertIn("rtorrent_rutorrent_passwd_init.changed", restart["when"])


if __name__ == "__main__":
    unittest.main()
