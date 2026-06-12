from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

METADATA_PACKAGES = (
    "paddlex",
    "paddleocr",
    "paddlepaddle",
    "Jinja2",
    "beautifulsoup4",
    "einops",
    "ftfy",
    "imagesize",
    "latex2mathml",
    "lxml",
    "opencv-contrib-python",
    "openpyxl",
    "premailer",
    "pyclipper",
    "pypdfium2",
    "python-bidi",
    "regex",
    "safetensors",
    "scikit-learn",
    "scipy",
    "sentencepiece",
    "shapely",
    "tiktoken",
    "tokenizers",
    "openai",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the PaddleOCR-VL runtime executable.")
    parser.add_argument(
        "--name",
        default="markanydown_paddleocr_vl_runtime",
        help="Runtime executable name.",
    )
    parser.add_argument(
        "--dist-dir",
        default="runtime/paddleocr_vl",
        help="Output directory for the bundled runtime.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    entrypoint = repo_root / "tools" / "paddleocr_vl" / "native_runtime.py"
    dist_dir = (repo_root / args.dist_dir).resolve()
    build_dir = repo_root / "build" / "paddleocr_vl_runtime"
    config_dir = build_dir / "config"
    runtime_home = repo_root / ".runtime_home" / "pyinstaller"
    config_dir.mkdir(parents=True, exist_ok=True)
    runtime_home.mkdir(parents=True, exist_ok=True)
    clean_previous_outputs(dist_dir, args.name)

    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--clean",
        "--onedir",
        "--name",
        args.name,
        "--distpath",
        str(dist_dir),
        "--workpath",
        str(build_dir),
        "--specpath",
        str(build_dir),
        "--collect-all",
        "paddleocr",
        "--collect-all",
        "paddlex",
        "--collect-all",
        "paddle",
    ]
    for package in METADATA_PACKAGES:
        command += ["--copy-metadata", package]
    command.append(str(entrypoint))

    env = os.environ.copy()
    env["HOME"] = str(runtime_home)
    env["PYINSTALLER_CONFIG_DIR"] = str(config_dir)
    env.setdefault("MARKANYDOWN_RUNTIME_HOME", str(runtime_home))
    env.setdefault("PADDLE_PDX_CACHE_HOME", str(runtime_home / "paddlex"))
    env.setdefault("PADDLEX_HOME", str(runtime_home / "paddlex"))
    env.setdefault("HF_HOME", str(runtime_home / "huggingface"))

    return subprocess.run(command, check=False, env=env).returncode


def clean_previous_outputs(dist_dir: Path, name: str) -> None:
    runtime_dir = dist_dir / name
    if runtime_dir.is_dir():
        shutil.rmtree(runtime_dir)
    elif runtime_dir.exists():
        runtime_dir.unlink()

    legacy_onefile = dist_dir / executable_name(name)
    if legacy_onefile.is_file():
        legacy_onefile.unlink()


def executable_name(name: str) -> str:
    if sys.platform == "win32":
        return f"{name}.exe"
    return name


if __name__ == "__main__":
    raise SystemExit(main())
