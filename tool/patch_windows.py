#!/usr/bin/env python3
"""把 `flutter create --platforms=windows` 產生的 windows/ 骨架改成 Mido筆記需要的樣子。

由 GitHub Actions 在 flutter create 之後執行：
  1. 新版 Visual Studio 把 <experimental/coroutine> 標成錯誤，會讓 local_auth_windows 編譯失敗，
     在 CMake 加上 _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS 讓它通過。
  2. 視窗標題改成「Mido筆記」。
"""
import pathlib
import re
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
