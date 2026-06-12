from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


def emit(progress: float, task: str, event: str | None = None) -> None:
    payload: dict[str, Any] = {"progress": progress, "task": task}
    if event:
        payload["event"] = event
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run PaddleOCR-VL for MarkAnyDown.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--pipeline-version", default="v1")
    parser.add_argument("--model-dir", default=None)
    parser.add_argument("--layout-model-dir", default=None)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--engine", default=None)
    parser.add_argument("--parent-pid", type=int, default=None)
    parser.add_argument("--vl-rec-backend", default=None)
    parser.add_argument("--vl-rec-server-url", default=None)
    return parser.parse_args()


def load_pipeline(args: argparse.Namespace) -> Any:
    emit(0.16, "检查 Python PaddleOCR-VL 运行环境")
    try:
        from paddleocr import PaddleOCRVL
    except Exception as exc:  # pragma: no cover - depends on local runtime.
        emit(1.0, "PaddleOCR-VL 依赖不可用", event="failed")
        print(f"Unable to import PaddleOCRVL: {exc}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        raise

    kwargs: dict[str, Any] = {
        "pipeline_version": args.pipeline_version,
        "device": args.device,
    }

    if args.engine:
        kwargs["engine"] = args.engine
    if args.model_dir:
        kwargs["vl_rec_model_dir"] = str(Path(args.model_dir).expanduser())
    if args.layout_model_dir:
        kwargs["layout_detection_model_dir"] = str(Path(args.layout_model_dir).expanduser())
    if args.vl_rec_backend:
        kwargs["vl_rec_backend"] = args.vl_rec_backend
    if args.vl_rec_server_url:
        kwargs["vl_rec_server_url"] = args.vl_rec_server_url

    emit(0.34, "初始化 PaddleOCR-VL 完整解析管线")
    pipeline = PaddleOCRVL(**kwargs)

    emit(0.78, "加载 PaddleOCR-VL native 模型权重")
    return pipeline


class RuntimeHandler(BaseHTTPRequestHandler):
    pipeline: Any = None

    def do_GET(self) -> None:
        if self.path != "/health":
            self.send_error(404)
            return

        self._send_json({"status": "ok", "model": "PaddleOCR-VL"})

    def do_POST(self) -> None:
        if self.path != "/parse":
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            input_path = payload["input"]
            output_dir = payload.get("output_dir", "output")

            results = []
            for result in self.pipeline.predict(input_path):
                result.save_to_json(save_path=output_dir)
                result.save_to_markdown(save_path=output_dir)
                results.append(str(result))

            self._send_json({"status": "ok", "results": results})
        except Exception as exc:  # pragma: no cover - depends on local runtime.
            self._send_json({"status": "error", "message": str(exc)}, status=500)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    args = parse_args()
    configure_runtime_home()
    start_parent_monitor(args.parent_pid)

    try:
        RuntimeHandler.pipeline = load_pipeline(args)
    except Exception as exc:
        emit(1.0, "PaddleOCR-VL native runtime 初始化失败", event="failed")
        print(f"Unable to load PaddleOCR-VL pipeline: {exc}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return 2

    emit(0.92, "启动 PaddleOCR-VL 本地推理服务")
    server = ThreadingHTTPServer((args.host, args.port), RuntimeHandler)
    emit(1.0, f"PaddleOCR-VL native runtime 就绪: http://{args.host}:{args.port}", event="ready")
    server.serve_forever()
    return 0


def start_parent_monitor(parent_pid: int | None) -> None:
    if not parent_pid or parent_pid <= 0:
        return

    def monitor() -> None:
        while True:
            time.sleep(2)
            if not is_process_alive(parent_pid):
                os._exit(0)

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()


def is_process_alive(pid: int) -> bool:
    if sys.platform == "win32":
        return is_windows_process_alive(pid)

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def is_windows_process_alive(pid: int) -> bool:
    try:
        import ctypes
        from ctypes import wintypes
    except Exception:
        return True

    synchronize = 0x00100000
    wait_timeout = 0x00000102
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    open_process = kernel32.OpenProcess
    open_process.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    open_process.restype = wintypes.HANDLE
    wait_for_single_object = kernel32.WaitForSingleObject
    wait_for_single_object.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    wait_for_single_object.restype = wintypes.DWORD
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [wintypes.HANDLE]
    close_handle.restype = wintypes.BOOL

    handle = open_process(synchronize, False, pid)
    if not handle:
        return False

    try:
        return wait_for_single_object(handle, 0) == wait_timeout
    finally:
        close_handle(handle)


def configure_runtime_home() -> None:
    runtime_home_env = os.environ.get("MARKANYDOWN_RUNTIME_HOME")
    if runtime_home_env:
        runtime_home = Path(runtime_home_env).expanduser().resolve()
    elif (Path.cwd() / ".git").exists():
        runtime_home = (Path.cwd() / ".runtime_home").resolve()
    else:
        runtime_home = (Path.home() / ".markanydown" / "runtime").resolve()

    runtime_home.mkdir(parents=True, exist_ok=True)

    os.environ["HOME"] = str(runtime_home)
    os.environ.setdefault("PADDLE_PDX_CACHE_HOME", str(runtime_home / "paddlex"))
    os.environ.setdefault("PADDLEX_HOME", str(runtime_home / "paddlex"))
    os.environ.setdefault("HF_HOME", str(runtime_home / "huggingface"))
    os.environ.setdefault("TRANSFORMERS_CACHE", str(runtime_home / "huggingface"))


if __name__ == "__main__":
    raise SystemExit(main())
