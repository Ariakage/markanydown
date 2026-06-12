from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


REPO_ID = "PaddlePaddle/PaddleOCR-VL"
REVISION = "main"
REQUIRED_FILES = (
    "config.json",
    "model.safetensors",
    "PP-DocLayoutV2/inference.pdmodel",
    "PP-DocLayoutV2/inference.pdiparams",
    "PP-DocLayoutV2/inference.yml",
)
USER_AGENT = "MarkAnyDown model downloader"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download PaddleOCR-VL from Hugging Face.")
    parser.add_argument(
        "--target",
        default="models/paddleocr_vl/PaddleOCR-VL",
        help="Local directory for the Hugging Face model repository.",
    )
    parser.add_argument(
        "--revision",
        default=REVISION,
        help="Hugging Face revision to download.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-check and overwrite files even when the required model files exist.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    target = Path(args.target).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)

    if _should_skip_model_download():
        print("Skipping PaddleOCR-VL model download.")
        return 0

    if not args.force and _has_required_files(target):
        print(f"PaddleOCR-VL model already exists at {target}")
        return 0

    if _download_with_huggingface_hub(target, args.revision):
        return 0

    if _download_with_git(target) == 0:
        return 0

    return _download_with_stdlib(target, args.revision)


def _download_with_huggingface_hub(target: Path, revision: str) -> bool:
    try:
        from huggingface_hub import snapshot_download
    except Exception:
        return False

    snapshot_download(
        repo_id=REPO_ID,
        revision=revision,
        local_dir=target,
        local_dir_use_symlinks=False,
        resume_download=True,
    )
    print(f"Downloaded {REPO_ID} to {target}")
    return True


def _download_with_git(target: Path) -> int:
    if not shutil.which("git") or not shutil.which("git-lfs"):
        print("git is required when huggingface_hub is not installed.", file=sys.stderr)
        return 2

    if (target / ".git").exists():
        commands = [
            ["git", "-C", str(target), "pull", "--ff-only"],
            ["git", "-C", str(target), "lfs", "pull"],
        ]
    else:
        commands = [
            ["git", "clone", f"https://huggingface.co/{REPO_ID}", str(target)],
            ["git", "-C", str(target), "lfs", "pull"],
        ]

    for command in commands:
        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            return result.returncode

    print(f"Downloaded {REPO_ID} to {target}")
    return 0


def _download_with_stdlib(target: Path, revision: str) -> int:
    print(f"Downloading {REPO_ID}@{revision} to {target}")
    try:
        files = _list_repo_files(revision)
    except Exception as exc:
        print(f"Unable to list Hugging Face model files: {exc}", file=sys.stderr)
        return 2

    target.mkdir(parents=True, exist_ok=True)
    for index, file_info in enumerate(files, start=1):
        path = file_info["path"]
        size = file_info.get("size")
        destination = target / path
        print(f"[{index}/{len(files)}] {path}")
        try:
            _download_file(path, destination, revision, size)
        except Exception as exc:
            print(f"Unable to download {path}: {exc}", file=sys.stderr)
            return 2

    if not _has_required_files(target):
        print("Downloaded files are incomplete.", file=sys.stderr)
        return 2

    print(f"Downloaded {REPO_ID} to {target}")
    return 0


def _list_repo_files(revision: str) -> list[dict[str, object]]:
    encoded_repo = urllib.parse.quote(REPO_ID, safe="")
    encoded_revision = urllib.parse.quote(revision, safe="")
    url = (
        f"https://huggingface.co/api/models/{encoded_repo}/tree/"
        f"{encoded_revision}?recursive=1"
    )
    with _open_url(url) as response:
        payload = json.loads(response.read().decode("utf-8"))

    files: list[dict[str, object]] = []
    for item in payload:
        if item.get("type") == "file":
            files.append(
                {
                    "path": item["path"],
                    "size": item.get("size"),
                }
            )
    return files


def _download_file(
    path: str,
    destination: Path,
    revision: str,
    expected_size: object,
) -> None:
    if isinstance(expected_size, int) and destination.exists():
        if destination.stat().st_size == expected_size:
            return

    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(f"{destination.name}.part")
    resume_from = partial.stat().st_size if partial.exists() else 0
    headers = {}
    mode = "ab"
    if resume_from > 0:
        headers["Range"] = f"bytes={resume_from}-"
    else:
        mode = "wb"

    encoded_path = urllib.parse.quote(path)
    encoded_revision = urllib.parse.quote(revision, safe="")
    url = f"https://huggingface.co/{REPO_ID}/resolve/{encoded_revision}/{encoded_path}"
    request = urllib.request.Request(url, headers=headers)
    request.add_header("User-Agent", USER_AGENT)

    try:
        response = urllib.request.urlopen(request)
    except urllib.error.HTTPError as exc:
        if exc.code == 416 and isinstance(expected_size, int):
            if partial.exists() and partial.stat().st_size == expected_size:
                partial.replace(destination)
                return
        raise

    with response:
        if resume_from > 0 and response.status != 206:
            mode = "wb"
            resume_from = 0

        downloaded = resume_from
        started_at = last_report = time.monotonic()
        with partial.open(mode + "") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                downloaded += len(chunk)
                now = time.monotonic()
                if now - last_report >= 5:
                    _print_progress(downloaded, expected_size, started_at)
                    last_report = now

    if isinstance(expected_size, int) and partial.stat().st_size != expected_size:
        raise RuntimeError(
            f"size mismatch: expected {expected_size}, got {partial.stat().st_size}"
        )

    partial.replace(destination)


def _open_url(url: str):
    request = urllib.request.Request(url)
    request.add_header("User-Agent", USER_AGENT)
    return urllib.request.urlopen(request)


def _print_progress(downloaded: int, expected_size: object, started_at: float) -> None:
    elapsed = max(time.monotonic() - started_at, 0.001)
    speed = downloaded / elapsed / 1024 / 1024
    if isinstance(expected_size, int) and expected_size > 0:
        percent = downloaded / expected_size * 100
        print(f"  {percent:5.1f}% {downloaded / 1024 / 1024:.1f} MiB at {speed:.1f} MiB/s")
    else:
        print(f"  {downloaded / 1024 / 1024:.1f} MiB at {speed:.1f} MiB/s")


def _has_required_files(target: Path) -> bool:
    return all((target / path).is_file() for path in REQUIRED_FILES)


def _should_skip_model_download() -> bool:
    value = os.environ.get("MARKANYDOWN_SKIP_MODEL_DOWNLOAD", "")
    return value.lower() in {"1", "true", "yes"}


if __name__ == "__main__":
    raise SystemExit(main())
