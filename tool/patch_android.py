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
if "RECORD_AUDIO" not in s:  # 錄音需要麥克風
    s = s.replace(
        "<application",
        '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application',
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

# 6. 圖片轉文字（Google ML Kit）：加入中文辨識模型（同時能辨識英文與數字），離線執行
MLKIT_KTS = '''
// --- Mido筆記：ML Kit 中文文字辨識模型 ---
dependencies {
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
'''
MLKIT_GROOVY = '''
// --- Mido筆記：ML Kit 中文文字辨識模型 ---
dependencies {
    implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'
}
'''
for name, snippet in (("build.gradle.kts", MLKIT_KTS), ("build.gradle", MLKIT_GROOVY)):
    app_gradle = ANDROID / "app" / name
    if app_gradle.exists():
        text = app_gradle.read_text(encoding="utf-8")
        if "text-recognition-chinese" not in text:
            app_gradle.write_text(text + snippet, encoding="utf-8")
        print(f"ML Kit chinese -> {app_gradle.relative_to(ROOT)}")
        break
else:
    fail("找不到 android/app/build.gradle(.kts)")

# 7. R8：ML Kit 外掛會參考日文／韓文／梵文模型的類別，我們只用中文模型，
#    告訴 R8 這些找不到的類別可以忽略（否則 release 建置會因 Missing class 失敗）。
rules = ANDROID / "app" / "proguard-rules.pro"
rules.write_text(
    "-dontwarn com.google.mlkit.vision.text.devanagari.**\n"
    "-dontwarn com.google.mlkit.vision.text.japanese.**\n"
    "-dontwarn com.google.mlkit.vision.text.korean.**\n"
    "-keep class com.google.mlkit.** { *; }\n"
    "-keep class com.google.android.gms.internal.mlkit_** { *; }\n"
    "-keep class com.google.android.gms.vision.** { *; }\n"
    "-keep class * implements com.google.firebase.components.ComponentRegistrar\n"
    "-keep class com.google.mlkit.common.internal.MlKitComponentDiscoveryService\n",
    encoding="utf-8",
)
PRO_KTS = '''
// --- Mido筆記：R8 忽略未使用的 ML Kit 語言模型 ---
android {
    buildTypes {
        release {
            proguardFiles("proguard-rules.pro")
            // ML Kit 靠反射／元件登錄運作，R8 縮減與混淆會讓辨識在 release 版崩潰，所以關閉
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
'''
PRO_GROOVY = '''
// --- Mido筆記：R8 忽略未使用的 ML Kit 語言模型 ---
android {
    buildTypes {
        release {
            proguardFiles 'proguard-rules.pro'
            minifyEnabled false
            shrinkResources false
        }
    }
}
'''
for name, snippet in (("build.gradle.kts", PRO_KTS), ("build.gradle", PRO_GROOVY)):
    app_gradle = ANDROID / "app" / name
    if app_gradle.exists():
        text = app_gradle.read_text(encoding="utf-8")
        if "忽略未使用的 ML Kit" not in text:
            app_gradle.write_text(text + snippet, encoding="utf-8")
        print(f"proguard rules -> {app_gradle.relative_to(ROOT)}")
        break

# 8. AI 文字辨識（PaddleOCR 模型 + ONNX Runtime，離線）
#    - Kotlin：AiOcr.kt（偵測 → 辨識），MainActivity 提供 "mido_notes/ocr" 通道
#    - 模型：從 rapidocr 的 wheel 取出 PP-OCRv6 small 偵測／辨識模型與字典，放進 assets/ai_ocr/
#      模型取不到也不會中斷建置，App 會自動隱藏 AI 辨識（改用 ML Kit）。
ORT_KTS = '''
// --- Mido筆記：ONNX Runtime（AI 文字辨識）---
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}
'''
ORT_GROOVY = '''
// --- Mido筆記：ONNX Runtime（AI 文字辨識）---
dependencies {
    implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.20.0'
}
'''
for name, snippet in (("build.gradle.kts", ORT_KTS), ("build.gradle", ORT_GROOVY)):
    app_gradle = ANDROID / "app" / name
    if app_gradle.exists():
        text = app_gradle.read_text(encoding="utf-8")
        if "onnxruntime-android" not in text:
            app_gradle.write_text(text + snippet, encoding="utf-8")
        print(f"onnxruntime-android -> {app_gradle.relative_to(ROOT)}")
        break

ai_kt = (OVERLAY / "AiOcr.kt.tmpl").read_text(encoding="utf-8").replace("__PACKAGE__", m.group(1))
(main_activity.parent / "AiOcr.kt").write_text(ai_kt, encoding="utf-8")
print("AiOcr.kt written")


def fetch_ai_models() -> bool:
    import glob
    import shutil
    import subprocess
    import tempfile
    import zipfile

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="ai_ocr_"))
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "download", "rapidocr==3.10.0", "--no-deps", "-d", str(tmp)])
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "onnxruntime"])
        except subprocess.CalledProcessError:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--break-system-packages", "onnxruntime"])
        wheels = glob.glob(str(tmp / "rapidocr-*.whl"))
        if not wheels:
            print("ai_ocr: rapidocr wheel not found", file=sys.stderr)
            return False
        out = ANDROID / "app" / "src" / "main" / "assets" / "ai_ocr"
        out.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(wheels[0]) as z:
            for src, dst in (
                ("rapidocr/models/PP-OCRv6_det_small.onnx", "det.onnx"),
                ("rapidocr/models/PP-OCRv6_rec_small.onnx", "rec.onnx"),
            ):
                with z.open(src) as f, open(out / dst, "wb") as g:
                    shutil.copyfileobj(f, g)
        # 用新的 python 行程讀字典：剛用 pip 裝好的套件，目前這個行程可能還看不到（user site 尚未在路徑上）
        code = (
            "import sys, onnxruntime as ort\n"
            "s = ort.InferenceSession(sys.argv[1], providers=['CPUExecutionProvider'])\n"
            "c = s.get_modelmeta().custom_metadata_map['character'].splitlines()\n"
            "open(sys.argv[2], 'w', encoding='utf-8').write('\\n'.join(c))\n"
            "print(len(c))\n"
        )
        subprocess.check_call([sys.executable, "-c", code, str(out / "rec.onnx"), str(out / "dict.txt")])
        print("ai_ocr: models ready")
        return True
    except Exception as e:  # noqa: BLE001
        print("ai_ocr: model setup failed, Android will use ML Kit only:", e, file=sys.stderr)
        shutil.rmtree(ANDROID / "app" / "src" / "main" / "assets" / "ai_ocr", ignore_errors=True)
        return False


fetch_ai_models()

# 9. 只打包 arm64-v8a（現在的手機幾乎都是 64 位元 ARM）。
#    其他架構（armeabi-v7a、x86、x86_64）的 Flutter 引擎、ML Kit、ONNX Runtime 函式庫全部不放，
#    安裝檔大約縮小一半，辨識模型與功能完全不變。
ABI_KTS = '''
// --- Mido筆記：只包含 arm64-v8a ---
android {
    defaultConfig {
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }
}
'''
ABI_GROOVY = '''
// --- Mido筆記：只包含 arm64-v8a ---
android {
    defaultConfig {
        ndk {
            abiFilters.clear()
            abiFilters.add('arm64-v8a')
        }
    }
}
'''
for name, snippet in (("build.gradle.kts", ABI_KTS), ("build.gradle", ABI_GROOVY)):
    app_gradle = ANDROID / "app" / name
    if app_gradle.exists():
        text = app_gradle.read_text(encoding="utf-8")
        if "只包含 arm64-v8a" not in text:
            app_gradle.write_text(text + snippet, encoding="utf-8")
        print(f"abiFilters arm64-v8a -> {app_gradle.relative_to(ROOT)}")
        break
