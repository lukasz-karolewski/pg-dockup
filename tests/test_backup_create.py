"""Publication and rotation tests using the real AWS CLI and a fake pg_dump."""

import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import unittest

import test_backup_download as downloads


@unittest.skipUnless(shutil.which("aws"), "AWS CLI is required")
class BackupCreateTests(unittest.TestCase):
    setUp = downloads.BackupDownloadTests.setUp

    def run_upload(self, stamp="2026-10-06T04-00-01Z", payload=b"backup contents"):
        path = self.root / f"pg_dump-{stamp}.gz"
        path.write_bytes(payload)
        result = subprocess.run(
            [sys.executable, str(downloads.SCRIPT.with_name("backup_s3.py")), "upload", str(path)],
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        return result, path

    def test_upload_stores_backup_then_pointer(self):
        result, path = self.run_upload()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.put_requests, [path.name, "latest.json"])
        pointer = json.loads(self.server.objects["latest.json"][0])
        self.assertEqual(pointer["key"], path.name)
        self.assertEqual(pointer["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(pointer["size"], path.stat().st_size)
        self.assertEqual(self.server.objects[path.name][2], pointer["sha256"])

    def test_upload_failure_leaves_previous_pointer(self):
        self.server.objects["latest.json"] = (b"previous pointer", "2026-10-05T00:00:01Z", None)
        self.server.fail_put_keys.add("pg_dump-2026-10-06T04-00-01Z.gz")
        result, _ = self.run_upload()
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assertEqual(self.server.objects["latest.json"][0], b"previous pointer")
        self.assertNotIn("latest.json", self.server.put_requests)

    def run_create(self, stamp="2026-10-06T04-00-01Z"):
        directory = self.root / "downloads"
        directory.mkdir(exist_ok=True)
        payload = self.root / "dump"
        payload.write_bytes(b"-- PostgreSQL database dump\n" + random.Random(42).randbytes(4096))
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        pg_dump = bin_dir / "pg_dump"
        pg_dump.write_text('#!/bin/sh\ncat "$BACKUP_TEST_PAYLOAD"\n')
        pg_dump.chmod(0o755)
        date = bin_dir / "date"
        date.write_text(f'#!/bin/sh\nif [ "$1" = "-u" ]; then echo "{stamp}"; else exec /usr/bin/date "$@"; fi\n')
        date.chmod(0o755)
        self.env.update({
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "BACKUP_TEST_PAYLOAD": str(payload), "POSTGRES_HOST": "test",
            "POSTGRES_USER": "test", "POSTGRES_PASSWORD": "test", "POSTGRES_DB": "test",
            "PG_DUMP_OPTIONS": "", "BACKUP_RETENTION_COUNT": "1",
        })
        return subprocess.run(
            ["bash", str(downloads.SCRIPT.with_name("backup-create.sh"))],
            env=self.env, capture_output=True, text=True, timeout=30,
        )

    def old_local_backup(self):
        directory = self.root / "downloads"
        directory.mkdir()
        path = directory / "pg_dump-2026-10-05T04-00-01Z.gz"
        path.write_bytes(b"previous backup")
        os.utime(path, (1, 1))
        return path

    def test_successful_publication_rotates_local_backups(self):
        old = self.old_local_backup()
        result = self.run_create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(old.exists())
        self.assertIn("latest.json", self.server.objects)

    def test_failed_publication_preserves_all_local_backups_then_retries(self):
        old = self.old_local_backup()
        self.server.fail_put_keys.add("latest.json")
        result = self.run_create()
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assertTrue(old.exists())
        self.assertEqual(len(list(old.parent.glob("*.gz"))), 2)
        self.server.fail_put_keys.clear()
        result = self.run_create(stamp="2026-10-06T06-00-01Z")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list(old.parent.glob("*.gz"))), 1)
        self.assertEqual(json.loads(self.server.objects["latest.json"][0])["key"],
                         "pg_dump-2026-10-06T06-00-01Z.gz")

    def test_missing_credentials_preserves_all_local_backups(self):
        old = self.old_local_backup()
        self.env["AWS_ACCESS_KEY_ID"] = ""
        result = self.run_create()
        self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
        self.assertTrue(old.exists())
        self.assertEqual(len(list(old.parent.glob("*.gz"))), 2)
        self.assertEqual(self.server.put_requests, [])

    def test_failed_backup_upload_preserves_all_local_backups(self):
        old = self.old_local_backup()
        self.server.fail_put_keys.add("pg_dump-2026-10-06T04-00-01Z.gz")
        result = self.run_create()
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assertTrue(old.exists())
        self.assertEqual(len(list(old.parent.glob("*.gz"))), 2)
        self.assertNotIn("latest.json", self.server.put_requests)


if __name__ == "__main__":
    unittest.main()
