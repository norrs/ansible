"""Render auth templates with synthetic data; no secrets or host access needed."""

from pathlib import Path
import re
import unittest

from jinja2 import Environment, StrictUndefined, UndefinedError
import yaml


ROOT = Path(__file__).resolve().parents[2]


def render(path, values):
    env = Environment(undefined=StrictUndefined, keep_trailing_newline=True)
    env.filters["regex_replace"] = lambda value, pattern, replacement: re.sub(
        pattern, replacement, value
    )
    return env.from_string((ROOT / path).read_text()).render(**values)


def auth_values():
    return {
        "tinyauth_hostname": "auth.example.test",
        "pocket_id_hostname": "identity.example.test",
        "tinyauth_pocket_id_client_id": "synthetic-upstream-id",
        "tinyauth_pocket_id_client_secret": "synthetic-upstream-secret",
        "tinyauth_effective_oauth_whitelist": "",
        "tinyauth_apps": [],
    }


class OIDCTemplateTests(unittest.TestCase):
    def test_absent_clients_do_not_register_an_implicit_client(self):
        text = render("playbooks/tinyauth/templates/env.j2", auth_values())
        self.assertNotIn("TINYAUTH_OIDC_CLIENTS_", text)
        self.assertIn("TINYAUTH_OAUTH_PROVIDERS_POCKETID_CLIENTID=", text)

    def test_two_clients_keep_their_existing_credentials(self):
        values = auth_values()
        values["tinyauth_oidc_clients"] = [
            {"id": "beszel", "name": "Metrics",
             "trusted_redirect_uris": "https://metrics.example.test/callback"},
            {"id": "start", "name": "Launchpad",
             "trusted_redirect_uris": ["https://start.example.test/auth/callback",
                                       "https://portal.example.test/auth/callback"]},
        ]
        values["tinyauth_oidc_client_credentials"] = {
            "beszel": {"client_id": "existing-metrics", "client_secret": "test-one"},
            "start": {"client_id": "existing-start", "client_secret": "test-two"},
        }
        text = render("playbooks/tinyauth/templates/env.j2", values)
        for env_id, client_id, secret in (
            ("BESZEL", "existing-metrics", "test-one"),
            ("START", "existing-start", "test-two"),
        ):
            self.assertIn(f"TINYAUTH_OIDC_CLIENTS_{env_id}_CLIENTID={client_id}\n", text)
            self.assertIn(f"TINYAUTH_OIDC_CLIENTS_{env_id}_CLIENTSECRET={secret}\n", text)
        self.assertIn(
            "TINYAUTH_OIDC_CLIENTS_START_TRUSTEDREDIRECTURIS="
            "https://start.example.test/auth/callback,"
            "https://portal.example.test/auth/callback\n", text,
        )

    def test_client_id_normalization_and_existing_app_rules(self):
        values = auth_values()
        values["tinyauth_oidc_clients"] = [
            {"id": "status-page", "name": "Status",
             "trusted_redirect_uris": "https://status.example.test/callback"},
        ]
        values["tinyauth_oidc_client_credentials"] = {
            "status-page": {"client_id": "status-id", "client_secret": "test-only"},
        }
        values["tinyauth_apps"] = [
            {"id": "metrics", "domain": "metrics.example.test",
             "oauth_groups": ["metrics-admins", "operators"]},
        ]
        text = render("playbooks/tinyauth/templates/env.j2", values)
        self.assertIn("TINYAUTH_OIDC_CLIENTS_STATUSPAGE_CLIENTID=status-id", text)
        self.assertIn("TINYAUTH_APPS_METRICS_CONFIG_DOMAIN=metrics.example.test", text)
        self.assertIn("TINYAUTH_APPS_METRICS_OAUTH_GROUPS=metrics-admins,operators", text)

    def test_missing_client_credentials_fail_rendering(self):
        values = auth_values()
        values["tinyauth_oidc_clients"] = [{"id": "missing"}]
        values["tinyauth_oidc_client_credentials"] = {}
        with self.assertRaises(UndefinedError):
            render("playbooks/tinyauth/templates/env.j2", values)

    def test_start_environment_contains_only_a_secret_file_reference(self):
        values = {
            "start_hostname": "start.example.test",
            "tinyauth_hostname": "auth.example.test",
            "start_oidc_client_id": "synthetic-start-id",
            "start_oidc_client_secret": "must-not-appear-in-the-environment",
        }
        text = render("playbooks/start/templates/env.j2", values)
        self.assertIn("STARTPAGE_OIDC_CLIENT_ID=synthetic-start-id\n", text)
        self.assertIn("STARTPAGE_OIDC_ISSUER=https://auth.example.test\n", text)
        self.assertIn("STARTPAGE_OIDC_CLIENT_SECRET_FILE=/run/secrets/oidc_client_secret", text)
        self.assertNotIn("STARTPAGE_OIDC_CLIENT_SECRET=", text)
        self.assertNotIn(values["start_oidc_client_secret"], text)

    def test_start_container_has_loopback_and_read_only_secret_mount(self):
        text = render("playbooks/start/files/start/compose.yaml", {
            "start_image": "registry.example.test/start:test",
            "start_hostname": "start.example.test",
            "start_container_uid": "65532", "start_container_gid": "65532",
        })
        service = yaml.safe_load(text)["services"]["start"]
        self.assertEqual(service["ports"], ["127.0.0.1:18080:8080"])
        self.assertEqual(service["user"], "65532:65532")
        self.assertTrue(service["read_only"])
        self.assertIn("./secrets/oidc_client_secret:/run/secrets/oidc_client_secret:ro",
                      service["volumes"])
        self.assertEqual(service["cap_drop"], ["ALL"])

    def test_secret_store_vaults_are_not_hardcoded_in_play_vars(self):
        for role, variable in (("start", "start_op_vault"),
                               ("tinyauth", "tinyauth_op_vault")):
            play = yaml.safe_load((ROOT / f"playbooks/{role}/playbook.yaml").read_text())[0]
            self.assertNotIn(variable, play["vars"])
            self.assertTrue(any(
                variable in str(task.get("ansible.builtin.assert", {}))
                for task in play["tasks"]
            ))

    def test_tinyauth_secret_environment_suppresses_logs_and_diffs(self):
        play = yaml.safe_load((ROOT / "playbooks/tinyauth/playbook.yaml").read_text())[0]
        task = next(task for task in play["tasks"]
                    if task.get("ansible.builtin.template", {}).get("src") == "templates/env.j2")
        self.assertTrue(task["no_log"])
        self.assertFalse(task["diff"])


if __name__ == "__main__":
    unittest.main()
