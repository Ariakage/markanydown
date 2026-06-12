from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


RUNTIME_NAME = "markanydown_paddleocr_vl_runtime"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ensure the platform native PaddleOCR-VL runtime exists."
    )
    parser.add_argument(
        "--runtime-dir",
        default="runtime/paddleocr_vl",
        help="Directory where the runtime executable should be placed.",
    )
    parser.add_argument(
        "--venv",
        default=".venv_paddleocr",
        help="Virtual environment used for building the runtime.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    runtime_path = (
        repo_root
        / args.runtime_dir
        / RUNTIME_NAME
        / runtime_executable_name()
    )

    if should_skip_runtime_build():
        print("Skipping PaddleOCR-VL runtime build.")
        return 0

    if runtime_path.is_file():
        print(f"PaddleOCR-VL runtime already exists at {runtime_path}")
        return 0

    venv_dir = repo_root / args.venv
    python = venv_python(venv_dir)
    if not python.exists():
        run([sys.executable, "-m", "venv", str(venv_dir)], cwd=repo_root)

    run(
        [
            str(python),
            "-m",
            "pip",
            "install",
            "paddlepaddle==3.2.1",
            "-i",
            "https://www.paddlepaddle.org.cn/packages/stable/cpu/",
        ],
        cwd=repo_root,
    )
    run(
        [
            str(python),
            "-m",
            "pip",
            "install",
            "-U",
            "paddleocr[doc-parser]",
            "pyinstaller",
        ],
        cwd=repo_root,
    )
    run([str(python), "tools/paddleocr_vl/build_runtime.py"], cwd=repo_root)
    return 0


def run(command: list[str], cwd: Path) -> None:
    print("+ " + " ".join(command))
    subprocess.run(command, cwd=cwd, check=True)


def runtime_executable_name() -> str:
    if sys.platform == "win32":
        return f"{RUNTIME_NAME}.exe"
    return RUNTIME_NAME


def venv_python(venv_dir: Path) -> Path:
    if sys.platform == "win32":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def should_skip_runtime_build() -> bool:
    value = os.environ.get("MARKANYDOWN_SKIP_RUNTIME_BUILD", "")
    return value.lower() in {"1", "true", "yes"}


if __name__ == "__main__":
    raise SystemExit(main())
