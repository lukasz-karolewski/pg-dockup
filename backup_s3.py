"""S3 publication, latest-backup downloads, and local retention."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def aws(*args):
    result = subprocess.run(
        ["aws", "--region", os.environ["AWS_S3_REGION"], "--output", "json", *map(str, args)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def head(key):
    try:
        return json.loads(aws(
            "s3api", "head-object", "--bucket", os.environ["AWS_S3_BUCKET_NAME"], "--key", key,
        ))
    except RuntimeError as error:
        if "(404)" in str(error) or "(NoSuchKey)" in str(error):
            return None
        raise


def upload(path):
    bucket = os.environ["AWS_S3_BUCKET_NAME"]
    prefix = os.environ["BACKUP_NAME_PREFIX"]
    key = path.name
    checksum = sha256(path)
    options = shlex.split(os.environ.get("AWS_S3_CP_OPTIONS", "--sse AES256"))
    aws("s3", "cp", path, f"s3://{bucket}/{key}", "--metadata", f"sha256={checksum}", *options)
    created = datetime.strptime(path.name[len(prefix) + 1:-3], "%Y-%m-%dT%H-%M-%SZ").replace(tzinfo=timezone.utc)
    # A failed publication leaves the previous pointer and local backups intact.
    manifest = {
        "version": 1, "key": key, "size": path.stat().st_size,
        "sha256": checksum, "created_at": created.isoformat(),
    }
    with tempfile.TemporaryDirectory() as directory:
        pointer = Path(directory) / "latest.json"
        pointer.write_text(json.dumps(manifest) + "\n")
        aws("s3", "cp", pointer, f"s3://{bucket}/latest.json", "--content-type", "application/json", *options)
    print(f"Published backup and latest.json: s3://{bucket}/{key}")


def valid_key(key):
    prefix = os.environ["BACKUP_NAME_PREFIX"]
    if not isinstance(key, str) or "/" in key or "\\" in key:
        return False
    return key.startswith(prefix + "-") and key.endswith(".gz")


def read_pointer():
    with tempfile.TemporaryDirectory() as directory:
        pointer = Path(directory) / "latest.json"
        aws("s3api", "get-object", "--bucket", os.environ["AWS_S3_BUCKET_NAME"], "--key", "latest.json", pointer)
        data = json.loads(pointer.read_text())
    if (
        not isinstance(data, dict) or data.get("version") != 1
        or not valid_key(data.get("key"))
        or type(data.get("size")) is not int or data["size"] <= 0
        or not isinstance(data.get("sha256"), str)
        or not re.fullmatch(r"[0-9a-f]{64}", data["sha256"])
    ):
        raise ValueError("invalid latest.json")
    metadata = head(data["key"])
    if metadata is None or metadata["ContentLength"] != data["size"]:
        raise ValueError("latest.json references a missing or changed backup")
    return data


def newest_by_listing():
    prefix = os.environ["BACKUP_NAME_PREFIX"]
    # JSON output applies max_by once after AWS CLI collects all pages.
    latest = json.loads(aws(
        "s3api", "list-objects-v2", "--bucket", os.environ["AWS_S3_BUCKET_NAME"],
        "--prefix", prefix + "-", "--query",
        "max_by(Contents[?ends_with(Key, '.gz')] || `[]`, &LastModified)",
    ))
    if latest is None:
        print(f"ERROR: No backups found matching prefix {prefix}")
        raise SystemExit(2)
    if not valid_key(latest["Key"]):
        raise RuntimeError("listed backup has an invalid key")
    metadata = head(latest["Key"])
    if metadata is None:
        raise RuntimeError("listed backup no longer exists")
    return {
        "key": latest["Key"], "size": metadata["ContentLength"],
        "sha256": metadata.get("Metadata", {}).get("sha256"),
    }


def download():
    try:
        latest = read_pointer()
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        print(f"Latest pointer unavailable ({error}); falling back to S3 listing.")
        latest = newest_by_listing()
    directory = Path(os.environ["LOCAL_BACKUP_DIR"])
    target = directory / Path(latest["key"]).name
    with tempfile.TemporaryDirectory(prefix=".download-", dir=directory) as temporary:
        path = Path(temporary) / target.name
        aws("s3", "cp", f"s3://{os.environ['AWS_S3_BUCKET_NAME']}/{latest['key']}", path)
        if path.stat().st_size != latest["size"]:
            raise RuntimeError("downloaded backup size does not match")
        if latest.get("sha256") and sha256(path) != latest["sha256"]:
            raise RuntimeError("downloaded backup SHA-256 does not match")
        path.replace(target)
    print(f"Backup successfully downloaded to {target}")


def rotate():
    count = int(os.environ.get("BACKUP_RETENTION_COUNT", "10"))
    if count < 1:
        raise ValueError("BACKUP_RETENTION_COUNT must be at least 1")
    directory = Path(os.environ["LOCAL_BACKUP_DIR"])
    prefix = os.environ["BACKUP_NAME_PREFIX"]
    files = sorted(
        (path for path in directory.iterdir() if path.is_file() and path.name.startswith(prefix + "-") and path.suffix == ".gz"),
        key=lambda path: path.stat().st_mtime_ns, reverse=True,
    )
    for path in files[count:]:
        path.unlink()
    print(f"Local rotation complete (keeping {count} most recent backups)")


if __name__ == "__main__":
    operation = sys.argv[1]
    try:
        if operation == "upload":
            upload(Path(sys.argv[2]))
        elif operation == "download":
            download()
        elif operation == "rotate":
            rotate()
        else:
            raise ValueError(f"unknown operation: {operation}")
    except (RuntimeError, ValueError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(3 if operation == "download" else 5)
