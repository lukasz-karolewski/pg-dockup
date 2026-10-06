"""Exercise the download script with the real AWS CLI and a local S3 stub."""

import os
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit
from xml.sax.saxutils import escape


SCRIPT = Path(__file__).resolve().parents[1] / "backup-download-last.sh"
PAYLOAD = b"test backup contents"


class S3Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, status, body=b"", head=False):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Last-Modified", "Tue, 06 Oct 2026 04:00:01 GMT")
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def do_GET(self):
        request = urlsplit(self.path)
        query = parse_qs(request.query)
        if "list-type" in query:
            self.server.list_requests += 1
            if self.server.fail_listing:
                self.respond(403, b"<Error><Code>AccessDenied</Code></Error>")
                return
            prefix = query.get("prefix", [""])[0]
            pages = self.server.pages if prefix == "pg_dump-" else [[]]
            if self.server.objects:
                pages = [[(key, modified) for key, (_, modified, _) in self.server.objects.items() if key.startswith(prefix)]]
            index = int(query.get("continuation-token", ["0"])[0])
            page = pages[index]
            more = index + 1 < len(pages)
            contents = "".join(
                f"<Contents><Key>{escape(key)}</Key>"
                f"<LastModified>{modified}</LastModified>"
                f"<Size>{len(PAYLOAD)}</Size></Contents>"
                for key, modified in page
            )
            token = f"<NextContinuationToken>{index + 1}</NextContinuationToken>" if more else ""
            body = (
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
                f"<Name>backups</Name><Prefix>pg_dump</Prefix>"
                f"<IsTruncated>{str(more).lower()}</IsTruncated>"
                f"{contents}{token}</ListBucketResult>"
            ).encode()
            self.respond(200, body)
            return
        self.object_request(head=False)

    def do_HEAD(self):
        self.object_request(head=True)

    def do_PUT(self):
        key = unquote(urlsplit(self.path).path.removeprefix("/backups/"))
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.put_requests.append(key)
        if key in self.server.fail_put_keys:
            self.respond(403, b"<Error><Code>AccessDenied</Code></Error>")
            return
        self.server.objects[key] = (body, "2026-10-06T04:00:01Z", self.headers.get("x-amz-meta-sha256"))
        self.respond(200)

    def object_request(self, head):
        key = unquote(urlsplit(self.path).path.removeprefix("/backups/"))
        self.server.object_requests.append(key)
        if key in self.server.objects and not self.server.fail_download:
            body, _, checksum = self.server.objects[key]
            if checksum:
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("x-amz-meta-sha256", checksum)
                self.send_header("Last-Modified", "Tue, 06 Oct 2026 04:00:01 GMT")
                self.end_headers()
                if not head:
                    self.wfile.write(body)
            else:
                self.respond(200, body, head=head)
            return
        if self.server.fail_download or not any(
            key == item[0] for page in self.server.pages for item in page
        ):
            self.respond(404, head=head)
        else:
            self.respond(200, PAYLOAD, head=head)


@unittest.skipUnless(shutil.which("aws"), "AWS CLI is required")
class BackupDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "config").write_text("[default]\n")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), S3Handler)
        self.server.pages = [[]]
        self.server.list_requests = 0
        self.server.object_requests = []
        self.server.fail_listing = False
        self.server.fail_download = False
        self.server.objects = {}
        self.server.put_requests = []
        self.server.fail_put_keys = set()
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.env = {
            **os.environ,
            "LOCAL_BACKUP_DIR": str(self.root / "downloads"),
            "BACKUP_NAME_PREFIX": "pg_dump",
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
            "AWS_SESSION_TOKEN": "",
            "AWS_S3_REGION": "us-east-1",
            "AWS_DEFAULT_REGION": "us-east-1",
            "AWS_S3_BUCKET_NAME": "backups",
            "AWS_ENDPOINT_URL": f"http://127.0.0.1:{self.server.server_port}",
            "AWS_ENDPOINT_URL_S3": f"http://127.0.0.1:{self.server.server_port}",
            "AWS_CONFIG_FILE": str(self.root / "config"),
            "AWS_SHARED_CREDENTIALS_FILE": str(self.root / "credentials"),
            "AWS_PROFILE": "default",
            "AWS_PAGER": "",
            "AWS_EC2_METADATA_DISABLED": "true",
            "AWS_MAX_ATTEMPTS": "1",
            "AWS_REQUEST_CHECKSUM_CALCULATION": "when_required",
        }

    def run_script(self):
        return subprocess.run(
            ["bash", str(SCRIPT)], env=self.env, capture_output=True, text=True, timeout=30
        )

    def assert_download(self, key, pages):
        self.server.pages = pages
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.list_requests, len(pages))
        self.assertEqual(set(self.server.object_requests), {key, "latest.json"})
        self.assertEqual((self.root / "downloads" / key).read_bytes(), PAYLOAD)

    def test_latest_on_first_page(self):
        self.assert_download("pg_dump-a.gz", [
            [("pg_dump-a.gz", "2026-10-06T04:00:01Z")],
            [("pg_dump-z.gz", "2025-12-27T04:00:01Z")],
        ])

    def test_latest_on_last_page(self):
        self.assert_download("pg_dump-z.gz", [
            [("pg_dump-a.gz", "2025-12-27T04:00:01Z")],
            [("pg_dump-z.gz", "2026-10-06T04:00:01Z")],
        ])

    def test_single_page_and_json_escaping(self):
        key = 'pg_dump-quoted "backup" with spaces.gz'
        self.assert_download(key, [[(key, "2026-10-06T04:00:01Z")]])

    def test_empty_bucket(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("No backups found", result.stdout)
        self.assertEqual(self.server.object_requests, ["latest.json"])

    def test_listing_failure_does_not_download(self):
        self.server.fail_listing = True
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.server.list_requests, 1)
        self.assertNotIn("No backups found", result.stdout)
        self.assertEqual(self.server.object_requests, ["latest.json"])

    def test_download_failure(self):
        self.server.pages = [[("pg_dump-a.gz", "2026-10-06T04:00:01Z")]]
        self.server.fail_download = True
        result = self.run_script()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)

    def set_pointer(self, key="pg_dump-2026-10-06T04-00-01Z.gz", checksum=None):
        checksum = checksum or hashlib.sha256(PAYLOAD).hexdigest()
        self.server.objects[key] = (PAYLOAD, "2026-10-06T04:00:01Z", checksum)
        pointer = {"version": 1, "key": key, "size": len(PAYLOAD), "sha256": checksum}
        self.server.objects["latest.json"] = (json.dumps(pointer).encode(), "2026-10-06T04:00:01Z", None)
        return key

    def test_pointer_avoids_listing_and_verifies_checksum(self):
        key = self.set_pointer()
        self.server.fail_listing = True
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.list_requests, 0)
        self.assertEqual((self.root / "downloads" / Path(key).name).read_bytes(), PAYLOAD)

    def test_checksum_mismatch_preserves_existing_local_file(self):
        key = self.set_pointer(checksum="0" * 64)
        directory = self.root / "downloads"
        directory.mkdir()
        target = directory / Path(key).name
        target.write_bytes(b"existing backup")
        result = self.run_script()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("SHA-256 does not match", result.stderr)
        self.assertEqual(target.read_bytes(), b"existing backup")

    def test_invalid_pointer_falls_back_to_listing(self):
        key = self.set_pointer()
        self.server.objects["latest.json"] = (b"invalid json", "2026-10-06T04:00:01Z", None)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.list_requests, 1)
        self.assertEqual((self.root / "downloads" / Path(key).name).read_bytes(), PAYLOAD)

    def test_missing_referenced_backup_falls_back_to_listing(self):
        expired = self.set_pointer()
        del self.server.objects[expired]
        key = "pg_dump-2026-10-01T04-00-01Z.gz"
        self.server.objects[key] = (PAYLOAD, "2026-10-01T04:00:01Z", hashlib.sha256(PAYLOAD).hexdigest())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.list_requests, 1)
        self.assertEqual((self.root / "downloads" / Path(key).name).read_bytes(), PAYLOAD)

    def test_pointer_with_unsafe_key_falls_back(self):
        key = self.set_pointer()
        pointer = json.loads(self.server.objects["latest.json"][0])
        pointer["key"] = "../pg_dump-unsafe.gz"
        self.server.objects["latest.json"] = (json.dumps(pointer).encode(), "2026-10-06T04:00:01Z", None)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn(pointer["key"], self.server.object_requests)
        self.assertEqual((self.root / "downloads" / key).read_bytes(), PAYLOAD)


if __name__ == "__main__":
    unittest.main()
