#!/usr/bin/env python3
"""Run real Godot scenes and reject script errors even when Godot exits zero."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = {
    "layout": ("res://tools/selftest.gd", "SELFTEST ALL PASS"),
    "lifecycle": ("res://tools/lifecycle_test.gd", "ALL PASS"),
    "restart": ("res://tools/restart_test.gd", "RESTART TEST: ALL PASS"),
    "interaction": ("res://tools/interaction_restart_test.gd", "INTERACTION RESTART TEST: ALL PASS"),
    "campaign": ("res://tools/campaign_test.gd", "ALL PASS"),
    "generation": ("res://tools/generation_test.gd", "GENERATION TEST: ALL PASS"),
    "materials": ("res://tools/material_test.gd", "MATERIAL TEST: ALL PASS"),
    "entity": ("res://tools/entity_visual_test.gd", "ENTITY VISUAL RESULT 0 failures"),
    "props_audio": ("res://tools/prop_audio_test.gd", "PROP_AUDIO TEST: ALL PASS"),
    "pursuit": ("res://tools/pursuit_test.gd", "PURSUIT TEST: ALL PASS"),
    "volume_ui": ("res://tools/volume_ui_test.gd", "VOLUME_UI TEST: ALL PASS"),
    "crouch": ("res://tools/crouch_test.gd", "CROUCH TEST: ALL PASS"),
    "route_hint": ("res://tools/route_hint_test.gd", "ROUTE HINT TEST: ALL PASS"),
    "view_interaction": ("res://tools/view_interaction_test.gd", "VIEW INTERACTION TEST: ALL PASS"),
    "graphics_preset": ("res://tools/graphics_preset_test.gd", "GRAPHICS PRESET TEST: ALL PASS"),
    "upgrade": ("res://tools/upgrade_test.gd", "UPGRADE TEST: ALL PASS"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="Names: " + ", ".join(TESTS))
    args = parser.parse_args()
    names = args.tests or list(TESTS)
    unknown = set(names) - TESTS.keys()
    if unknown:
        parser.error("Unknown tests: " + ", ".join(sorted(unknown)))
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        parser.error("Godot missing; set GODOT to its executable")
    logs = Path(tempfile.mkdtemp(prefix="backrooms-regression-"))
    print(f"Logs: {logs}", flush=True)
    failed = 0
    results = []
    for name in names:
        script, marker = TESTS[name]
        try:
            run = subprocess.run(
                [godot, "--headless", "--path", str(ROOT), "--script", script],
                capture_output=True, text=True, timeout=180,
            )
            output = run.stdout + run.stderr
            errors = [line for line in output.splitlines() if any(
                token in line for token in ("SCRIPT ERROR:", "Parse Error:", "FAIL:", "FAIL [")
            )]
            passed = run.returncode == 0 and marker in output and not errors
            reason = f"exit={run.returncode}, script/assertion errors={len(errors)}, completion={marker in output}"
        except subprocess.TimeoutExpired as exc:
            def decode(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
            output = decode(exc.stdout) + decode(exc.stderr)
            passed, reason = False, "timed out after 180s"
        (logs / f"{name}.log").write_text(output)
        warnings = sum("WARNING:" in line or "RID allocations" in line for line in output.splitlines())
        print(f"{'PASS' if passed else 'FAIL'} {name}: {reason}; engine warnings={warnings}", flush=True)
        results.append(dict(test=name, passed=passed, reason=reason, warnings=warnings, log=str(logs / f"{name}.log")))
        if not passed:
            failed += 1
    report = dict(godot=str(Path(godot).resolve()), project=str(ROOT), failures=failed, results=results)
    (logs / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"REGRESSION: {len(names) - failed}/{len(names)} passed. See logs for engine warnings.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
