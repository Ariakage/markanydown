from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Copy MarkAnyDown desktop resources.")
    parser.add_argument("--target", required=True, help="Bundle resource directory.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    target = Path(args.target).resolve()
    target.mkdir(parents=True, exist_ok=True)

    ensure_model(repo_root)
    ensure_runtime(repo_root)

    copy_dir(repo_root / "models", target / "models")
    copy_dir(repo_root / "runtime", target / "runtime")
    copy_dir(
        repo_root / "tools" / "paddleocr_vl",
        target / "runtime" / "paddleocr_vl",
        clean=False,
    )
    return 0


def copy_dir(source: Path, destination: Path, *, clean: bool = True) -> None:
    if not source.exists():
        return

    if clean:
        if destination.is_dir():
            shutil.rmtree(destination)
        elif destination.exists():
            destination.unlink()

    shutil.copytree(source, destination, dirs_exist_ok=True)


def ensure_model(repo_root: Path) -> None:
    if should_skip_model_download():
        return

    result = subprocess.run(
        [sys.executable, str(repo_root / "tools" / "paddleocr_vl" / "download_model.py")],
        cwd=repo_root,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def ensure_runtime(repo_root: Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(repo_root / "tools" / "paddleocr_vl" / "ensure_runtime.py"),
        ],
        cwd=repo_root,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def should_skip_model_download() -> bool:
    value = os.environ.get("MARKANYDOWN_SKIP_MODEL_DOWNLOAD", "")
    return value.lower() in {"1", "true", "yes"}


if __name__ == "__main__":
    raise SystemExit(main())
