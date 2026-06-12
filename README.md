# MarkAnyDown

Convert most files to Markdown format

## PaddleOCR-VL runtime

MarkAnyDown starts a native PaddleOCR-VL runtime when the app opens. The Flutter
UI owns the loading screen; the model stays loaded in a local Python/PaddleOCR
process for faster later inference.

The app does not download the model at startup. Desktop builds ensure the model
and native runtime exist at build time and then package them into the app
resources. A fresh clone can build directly; the first build downloads
PaddleOCR-VL and builds the platform runtime automatically:

```bash
flutter build macos
flutter build windows
flutter build linux
```

You can also download or refresh the Hugging Face model manually:

```bash
python3 tools/paddleocr_vl/download_model.py
```

Set `MARKANYDOWN_SKIP_MODEL_DOWNLOAD=1` to disable the build-time download for
offline CI jobs that provide `models/` another way.
Set `MARKANYDOWN_SKIP_RUNTIME_BUILD=1` to disable automatic sidecar builds when
your CI provides `runtime/` another way.

For development fallback without a sidecar, create the Python runtime
environment manually:

```bash
python3 -m venv .venv_paddleocr
.venv_paddleocr/bin/python -m pip install paddlepaddle==3.2.1 -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
.venv_paddleocr/bin/python -m pip install -U "paddleocr[doc-parser]"
```

The default model path is ignored by git:

```text
models/paddleocr_vl/PaddleOCR-VL
```

Desktop bundles look for the same layout inside the app resources:

```text
models/paddleocr_vl/PaddleOCR-VL
runtime/paddleocr_vl/
```

When the Flutter window closes, the view model stops the native runtime. The
runtime also watches the Flutter parent process and exits by itself if the app
process disappears unexpectedly.

Packaged builds use an onedir native runtime under `runtime/paddleocr_vl/`:

```text
runtime/paddleocr_vl/markanydown_paddleocr_vl_runtime/
  markanydown_paddleocr_vl_runtime      # macOS/Linux
  markanydown_paddleocr_vl_runtime.exe  # Windows
  _internal/
```

Build the runtime manually on the current platform if you want to refresh it:

```bash
python3 tools/paddleocr_vl/ensure_runtime.py
```

If that executable is not present, development builds fall back to running
`runtime/paddleocr_vl/native_runtime.py` or `tools/paddleocr_vl/native_runtime.py`
with Python.

Useful environment variables:

```bash
MARKANYDOWN_PADDLEOCR_VL_PYTHON=.venv_paddleocr/bin/python
MARKANYDOWN_PADDLEOCR_VL_MODEL_DIR=/path/to/PaddleOCR-VL
MARKANYDOWN_PADDLEOCR_VL_DEVICE=cpu
MARKANYDOWN_PADDLEOCR_VL_ENGINE=paddle
MARKANYDOWN_PADDLEOCR_VL_PORT=8765
```
