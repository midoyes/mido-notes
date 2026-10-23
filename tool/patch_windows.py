#!/usr/bin/env python3
"""把 `flutter create --platforms=windows` 產生的 windows/ 骨架改成 Mido筆記需要的樣子。

由 GitHub Actions 在 flutter create 之後執行：
  1. 新版 Visual Studio 把 <experimental/coroutine> 標成錯誤，會讓 local_auth_windows 編譯失敗，
     在 CMake 加上 _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS 讓它通過。
  2. 視窗標題改成「Mido筆記」。
"""
import pathlib
import re
import subprocess
import sys

# Windows 主控台預設不是 UTF-8，印出中文會當掉；訊息一律用英文，並強制 UTF-8。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = pathlib.Path(__file__).resolve().parent.parent
WIN = ROOT / "windows"

# 1. CMake: silence the experimental coroutine header error for all plugins
cmake = WIN / "CMakeLists.txt"
if cmake.exists():
    text = cmake.read_text(encoding="utf-8")
    marker = "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
    if marker not in text:
        define = (
            "\n# Mido: newer MSVC treats <experimental/coroutine> as an error (local_auth_windows)\n"
            "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)\n"
        )
        new, n = re.subn(r"(^project\([^\n]*\)[^\n]*\n)", lambda m: m.group(1) + define, text, count=1, flags=re.M)
        if n:
            cmake.write_text(new, encoding="utf-8")
            print("CMake: coroutine warning silenced")
        else:
            print("patch_windows: project(...) not found in CMakeLists.txt", file=sys.stderr)
            sys.exit(1)
    else:
        print("CMake: already patched")
else:
    print("patch_windows: windows/CMakeLists.txt not found", file=sys.stderr)
    sys.exit(1)

# 3. AI OCR (RapidOCR / PaddleOCR models, ONNX, offline) -> windows/ai_ocr_dist/mido_ocr/
#    Uses the official Python "embeddable" runtime (signed python.exe) + site-packages + mido_ocr.py,
#    installed next to the app as <app>/ocr/python/python.exe. (A PyInstaller exe was flagged by antivirus.)
#    Failure here is NOT fatal: the app simply hides the "AI OCR" option when it is missing.
def build_ai_ocr():
    import shutil
    import urllib.request
    import zipfile

    src = ROOT / "tool" / "ai_ocr" / "mido_ocr.py"
    out = WIN / "ai_ocr_dist" / "mido_ocr"
    if not src.exists():
        print("ai_ocr: source not found, skipping")
        return False
    try:
        v = sys.version_info
        ver = "%d.%d.%d" % (v.major, v.minor, v.micro)
        url = "https://www.python.org/ftp/python/%s/python-%s-embed-amd64.zip" % (ver, ver)
        shutil.rmtree(out, ignore_errors=True)
        (out / "python").mkdir(parents=True)
        zpath = ROOT / "py_embed.zip"
        print("ai_ocr: downloading", url)
        urllib.request.urlretrieve(url, str(zpath))
        with zipfile.ZipFile(zpath) as z:
            z.extractall(out / "python")
        pth = out / "python" / ("python%d%d._pth" % (v.major, v.minor))
        pth.write_text(
            "python%d%d.zip\n.\n..\\site-packages\nimport site\n" % (v.major, v.minor),
            encoding="utf-8",
        )
        site = out / "site-packages"
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "--target", str(site),
            "--only-binary=:all:", "rapidocr==3.10.0", "onnxruntime",
        ])
        shutil.copyfile(src, out / "mido_ocr.py")
        py = out / "python" / "python.exe"
        # smoke test: the embedded runtime must be able to import everything
        subprocess.check_call([str(py), "-c", "import cv2, numpy, onnxruntime, rapidocr; print('ai_ocr import ok')"])
        for pyc in out.rglob("__pycache__"):
            shutil.rmtree(pyc, ignore_errors=True)
    except Exception as e:  # noqa: BLE001
        print("ai_ocr: build failed, continuing without it:", e, file=sys.stderr)
        shutil.rmtree(WIN / "ai_ocr_dist", ignore_errors=True)
        return False
    text = cmake.read_text(encoding="utf-8")
    if "ai_ocr_dist" not in text:
        text += (
            "\n# Mido: bundle the AI OCR runtime next to the app\n"
            'install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/ai_ocr_dist/mido_ocr/" '
            'DESTINATION "${CMAKE_INSTALL_PREFIX}/ocr" COMPONENT Runtime)\n'
        )
        cmake.write_text(text, encoding="utf-8")
    print("ai_ocr: built and added to the install bundle")
    return True


build_ai_ocr()

# 2. Window title
main_cpp = WIN / "runner" / "main.cpp"
if not main_cpp.exists():
    print("patch_windows: windows/runner/main.cpp not found, skipping window title", file=sys.stderr)
    sys.exit(0)

text = main_cpp.read_text(encoding="utf-8")
# 用 \u 跳脫，避免編譯器的檔案編碼問題：Mido筆記
title = 'L"Mido\\u7B46\\u8A18"'
new, n = re.subn(r'(window\.Create\()L"[^"]*"', lambda m: m.group(1) + title, text, count=1)
if n:
    main_cpp.write_text(new, encoding="utf-8")
    print("window title patched")
else:
    print("patch_windows: window.Create(...) not found, keeping default title")
