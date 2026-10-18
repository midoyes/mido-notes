#!/usr/bin/env python3
"""把 `flutter create` 產生的 android/ 骨架改成 Mido筆記需要的樣子。

由 GitHub Actions 在 flutter create 之後執行：
  1. MainActivity 改成 FlutterFragmentActivity，並加入防截圖的 MethodChannel
  2. 啟動主題改成 AppCompat（指紋視窗需要）
  3. AndroidManifest：App 名稱、USE_BIOMETRIC 權限、關閉 allowBackup
  4. minSdk 固定為 24
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
OVERLAY = ROOT / "android_overlay"
APP_LABEL = "Mido筆記"


def fail(msg: str) -> None:
    print(f"patch_android: {msg}", file=sys.stderr)
    sys.exit(1)


# 1. MainActivity
candidates = list(ANDROID.glob("app/src/main/kotlin/**/MainActivity.kt"))
if not candidates:
    fail("找不到 MainActivity.kt（Flutter 範本結構可能變了）")
main_activity = candidates[0]
m = re.search(r"^package\s+([\w.]+)", main_activity.read_text(encoding="utf-8"), re.M)
if not m:
    fail("MainActivity.kt 裡找不到 package 宣告")
template = (OVERLAY / "MainActivity.kt.tmpl").read_text(encoding="utf-8")
main_activity.write_text(template.replace("__PACKAGE__", m.group(1)), encoding="utf-8")
print(f"MainActivity -> {main_activity.relative_to(ROOT)} (package {m.group(1)})")

# 2. styles
styles = (OVERLAY / "styles.xml").read_text(encoding="utf-8")
for folder in ("values", "values-night"):
    target = ANDROID / "app/src/main/res" / folder / "styles.xml"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(styles, encoding="utf-8")
    print(f"styles -> {target.relative_to(ROOT)}")

# 3. AndroidManifest
manifest = ANDROID / "app/src/main/AndroidManifest.xml"
s = manifest.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in s:  # 手動檢查更新需要網路
    s = s.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )
if "USE_BIOMETRIC" not in s:
    s = s.replace(
        "<application",
        '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application',
        1,
    )
if re.search(r'<application[^>]*android:label="', s):
    s = re.sub(r'(<application[^>]*?android:label=")[^"]*(")', rf"\g<1>{APP_LABEL}\g<2>", s, count=1)
else:
    s = s.replace("<application", f'<application\n        android:label="{APP_LABEL}"', 1)
if re.search(r'<application[^>]*android:allowBackup="', s):
    s = re.sub(r'(<application[^>]*?android:allowBackup=")[^"]*(")', r"\g<1>false\g<2>", s, count=1)
else:
    s = s.replace("<application", '<application\n        android:allowBackup="false"', 1)
manifest.write_text(s, encoding="utf-8")
print("AndroidManifest patched")

# 4. minSdk
patched = False
for name in ("build.gradle.kts", "build.gradle"):
    gradle = ANDROID / "app" / name
    if gradle.exists():
        text = gradle.read_text(encoding="utf-8")
        new = text.replace("flutter.minSdkVersion", "24")
        if new != text:
            gradle.write_text(new, encoding="utf-8")
            patched = True
            print(f"minSdk=24 -> {gradle.relative_to(ROOT)}")
if not patched:
    print("minSdk: 沒有找到 flutter.minSdkVersion，保留範本預設值")

# 5. 所有外掛強制使用 compileSdk 36（file_picker 等外掛預設 34，會被 AndroidX 相依要求 36 擋下）
KTS = '''
// --- Mido筆記：統一外掛的 compileSdk ---
subprojects {
    if (!project.state.executed) {
        project.afterEvaluate {
            val ext = project.extensions.findByName("android")
            if (ext != null) {
                ext.withGroovyBuilder { "compileSdkVersion"(36) }
            }
        }
    }
}
'''
GROOVY = '''
// --- Mido筆記：統一外掛的 compileSdk ---
subprojects {
    if (!project.state.executed) {
        project.afterEvaluate {
            if (project.hasProperty('android')) {
                project.android.compileSdkVersion 36
            }
        }
    }
}
'''
for name, snippet in (("build.gradle.kts", KTS), ("build.gradle", GROOVY)):
    root_gradle = ANDROID / name
    if root_gradle.exists():
        text = root_gradle.read_text(encoding="utf-8")
        if "統一外掛的 compileSdk" not in text:
            root_gradle.write_text(text + snippet, encoding="utf-8")
        print(f"compileSdk=36 for plugins -> {root_gradle.relative_to(ROOT)}")
        break
else:
    fail("找不到 android/build.gradle(.kts)")
