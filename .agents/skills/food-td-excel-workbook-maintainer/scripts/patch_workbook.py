#!/usr/bin/env python3
"""Apply preconditioned cell updates to an .xlsx file with atomic replacement."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

from openpyxl import load_workbook
from openpyxl.utils.cell import coordinate_to_tuple


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path, help="UTF-8 JSON update payload")
    parser.add_argument("--dry-run", action="store_true", help="validate without saving")
    return parser.parse_args()


def _load_payload(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        payload = json.load(stream)
    if not isinstance(payload, dict):
        raise ValueError("payload root must be an object")
    return payload


def _resolve_workbook(raw_path: Any) -> Path:
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise ValueError("workbook must be a non-empty path string")
    workbook = Path(raw_path)
    if not workbook.is_absolute():
        workbook = Path.cwd() / workbook
    workbook = workbook.resolve()
    if workbook.suffix.lower() != ".xlsx":
        raise ValueError("only .xlsx workbooks are supported")
    if not workbook.is_file():
        raise FileNotFoundError(workbook)
    return workbook


def _short_repr(value: Any, limit: int = 160) -> str:
    rendered = ascii(value)
    if len(rendered) <= limit:
        return rendered
    return rendered[: limit - 3] + "..."


def _validate_updates(payload: dict[str, Any], sheet_names: list[str]) -> list[dict[str, Any]]:
    expected_sheets = payload.get("expected_sheets", [])
    if not isinstance(expected_sheets, list) or not all(isinstance(item, str) for item in expected_sheets):
        raise ValueError("expected_sheets must be a list of strings")
    missing = [name for name in expected_sheets if name not in sheet_names]
    if missing:
        raise ValueError(f"missing expected sheets: {missing}")

    updates = payload.get("updates")
    if not isinstance(updates, list) or not updates:
        raise ValueError("updates must be a non-empty list")

    seen: set[tuple[str, str]] = set()
    for index, update in enumerate(updates, start=1):
        if not isinstance(update, dict):
            raise ValueError(f"update {index} must be an object")
        for required in ("sheet", "cell", "expect", "value"):
            if required not in update:
                raise ValueError(f"update {index} missing {required!r}")
        sheet = update["sheet"]
        cell = update["cell"]
        if not isinstance(sheet, str) or sheet not in sheet_names:
            raise ValueError(f"update {index} has unknown sheet {sheet!r}")
        if not isinstance(cell, str):
            raise ValueError(f"update {index} cell must be a string")
        coordinate_to_tuple(cell)
        normalized_cell = cell.upper()
        target = (sheet, normalized_cell)
        if target in seen:
            raise ValueError(f"duplicate target {sheet}!{normalized_cell}")
        seen.add(target)
        kind = update.get("kind", "text")
        if kind not in {"text", "scalar", "formula"}:
            raise ValueError(f"update {index} has invalid kind {kind!r}")
        value = update["value"]
        if kind == "text" and not isinstance(value, str):
            raise ValueError(f"update {index} text value must be a string")
        if kind == "scalar" and value is not None and not isinstance(value, (bool, int, float)):
            raise ValueError(f"update {index} scalar value must be a number, boolean, or null")
        if kind == "formula" and (not isinstance(value, str) or not value.startswith("=")):
            raise ValueError(f"update {index} formula value must start with '='")
    return updates


def _apply_updates(workbook: Any, updates: list[dict[str, Any]]) -> None:
    mismatches: list[str] = []
    for update in updates:
        cell = workbook[update["sheet"]][update["cell"]]
        if cell.value != update["expect"]:
            mismatches.append(
                f"{ascii(update['sheet'])}!{update['cell']}: "
                f"expected {_short_repr(update['expect'])}, found {_short_repr(cell.value)}"
            )
    if mismatches:
        raise ValueError("precondition mismatch:\n" + "\n".join(mismatches))

    for update in updates:
        cell = workbook[update["sheet"]][update["cell"]]
        cell.value = update["value"]
        if update.get("kind", "text") == "text" and update["value"].startswith("="):
            cell.data_type = "s"


def _verify_saved(path: Path, expected_sheets: list[str], updates: list[dict[str, Any]]) -> None:
    with zipfile.ZipFile(path, "r") as archive:
        broken_member = archive.testzip()
        if broken_member is not None:
            raise ValueError(f"invalid workbook archive member: {broken_member}")
    workbook = load_workbook(path, data_only=False, read_only=True, keep_links=True)
    try:
        if workbook.sheetnames != expected_sheets:
            raise ValueError("sheet order changed during save")
        mismatches = []
        for update in updates:
            actual = workbook[update["sheet"]][update["cell"]].value
            if actual != update["value"]:
                mismatches.append(
                    f"{ascii(update['sheet'])}!{update['cell']}: saved {_short_repr(actual)}"
                )
        if mismatches:
            raise ValueError("saved value mismatch:\n" + "\n".join(mismatches))
    finally:
        workbook.close()


def main() -> int:
    args = _parse_args()
    payload = _load_payload(args.payload.resolve())
    workbook_path = _resolve_workbook(payload.get("workbook"))
    original_stat = workbook_path.stat()
    workbook = load_workbook(workbook_path, data_only=False, read_only=False, keep_links=True)
    temp_path: Path | None = None
    try:
        original_sheets = list(workbook.sheetnames)
        updates = _validate_updates(payload, original_sheets)
        _apply_updates(workbook, updates)
        if args.dry_run:
            print(json.dumps({"status": "dry-run-ok", "workbook": str(workbook_path), "updates": len(updates)}))
            return 0

        handle, raw_temp_path = tempfile.mkstemp(
            prefix=f".{workbook_path.stem}.", suffix=".xlsx", dir=workbook_path.parent
        )
        os.close(handle)
        temp_path = Path(raw_temp_path)
        workbook.save(temp_path)
        _verify_saved(temp_path, original_sheets, updates)

        current_stat = workbook_path.stat()
        if (current_stat.st_mtime_ns, current_stat.st_size) != (original_stat.st_mtime_ns, original_stat.st_size):
            raise RuntimeError("source workbook changed during update; refusing to replace it")
        os.replace(temp_path, workbook_path)
        temp_path = None
        _verify_saved(workbook_path, original_sheets, updates)
        print(json.dumps({"status": "saved", "workbook": str(workbook_path), "updates": len(updates)}))
        return 0
    finally:
        workbook.close()
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"status": "error", "error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
