# -*- coding: utf-8 -*-
"""Mido筆記 AI 文字辨識（RapidOCR / PaddleOCR 模型，ONNX，離線）。

用法：mido_ocr --image <圖片> --out <結果.json>
輸出 UTF-8 JSON：{"w":圖寬,"h":圖高,"lines":[{"x":,"y":,"w":,"h":,"text":,"score":}, ...]}
失敗時輸出 {"error":"..."} 並以代碼 1 結束。
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    def write(obj):
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)

    try:
        import cv2
        import numpy as np
        from rapidocr import RapidOCR

        # 用 imdecode 讀檔，路徑含中文也不會出問題
        data = np.fromfile(a.image, dtype=np.uint8)
        img = cv2.imdecode(data, cv2.IMREAD_COLOR)
        if img is None:
            write({"error": "cannot decode image"})
            return 1
        h, w = img.shape[:2]
        engine = RapidOCR()
        res = engine(img)
        lines = []
        boxes = getattr(res, "boxes", None)
        txts = getattr(res, "txts", None)
        scores = getattr(res, "scores", None)
        if boxes is not None and txts is not None:
            for i, (b, t) in enumerate(zip(boxes, txts)):
                xs = [float(p[0]) for p in b]
                ys = [float(p[1]) for p in b]
                x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
                s = float(scores[i]) if scores is not None else 1.0
                lines.append({"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "text": t, "score": s})
        write({"w": w, "h": h, "lines": lines})
        return 0
    except Exception as e:  # noqa: BLE001
        try:
            write({"error": "%s: %s" % (type(e).__name__, e)})
        except Exception:  # noqa: BLE001
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
