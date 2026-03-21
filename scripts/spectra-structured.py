#!/usr/bin/env python3
"""Typed helper for SPECTRA structured parsing, metrics, and status generation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


TASK_HEADER_RE = re.compile(r"^## Task ([0-9]{3}): (.+)$")
TASK_CHECKBOX_RE = re.compile(r"^- \[([ xX!])\] ([0-9]{3}):")
AC_ITEM_RE = re.compile(r"^  - (.+)$")
RISK_RE = re.compile(r"^- Risk:\s*(high|medium|low)\s*$", re.IGNORECASE)
VERIFY_RE = re.compile(r"^- Verify:\s*`(.+)`\s*$")
MAX_ITER_RE = re.compile(r"^- Max(?:-|\s)iterations:\s*([0-9]+)")
SCOPE_RE = re.compile(r"^- Scope:\s*(code|infra|docs|config|multi-repo)\s*$", re.IGNORECASE)
FILES_RE = re.compile(r"^- Files:\s*(.+)$")
OWNERSHIP_RE = re.compile(r"^\s+- (owns|touches|reads):\s*(.+)$")
DEPENDENCIES_LINE_RE = re.compile(r"^- Dependencies:")
TASK_LIST_DEP_RE = re.compile(r"Task ([0-9]{3}).*depends on ([0-9]{3}(,\s*[0-9]{3})*)")
TASK_ALL_DEP_RE = re.compile(r"Task ([0-9]{3}).*depends on all")
HEADER_VALUE_RE = {
    "project": re.compile(r"^## Project:\s*(.+)$"),
    "level": re.compile(r"^## Level:\s*([0-9]+)$"),
    "generated": re.compile(r"^## Generated:\s*(.+)$"),
    "source": re.compile(r"^## Source:\s*(.+)$"),
}
STATUS_MARKERS = {"pending": " ", "complete": "x", "stuck": "!"}


@dataclass
class PlanTask:
    id: str
    title: str
    status: str = "pending"
    risk: str = "medium"
    verify: str = ""
    max_iterations: int = 5
    owns: list[str] = field(default_factory=list)
    touches: list[str] = field(default_factory=list)
    reads: list[str] = field(default_factory=list)
    deps: list[str] = field(default_factory=list)
    line_number: int = 0
    scope: str = ""
    files: str = ""
    ac: list[str] = field(default_factory=list)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> "PlanTask":
        required = ("id", "title", "status", "line_number")
        for key in required:
            value = payload.get(key)
            if value in (None, ""):
                raise ValueError(f"plan.json task missing required field: {key}")

        if not re.fullmatch(r"[0-9]{3}", str(payload["id"])):
            raise ValueError(f"invalid task id: {payload['id']}")
        if payload["status"] not in {"pending", "complete", "stuck"}:
            raise ValueError(f"invalid task status: {payload['status']}")

        risk = payload.get("risk", "medium")
        if risk not in {"low", "medium", "high"}:
            raise ValueError(f"invalid task risk: {risk}")

        max_iterations = int(payload.get("max_iterations", 5))
        if max_iterations <= 0:
            raise ValueError(f"invalid max_iterations: {max_iterations}")

        line_number = int(payload["line_number"])
        if line_number < 0:
            raise ValueError(f"invalid line_number: {line_number}")

        array_fields = ("owns", "touches", "reads", "deps", "ac")
        arrays: dict[str, list[str]] = {}
        for key in array_fields:
            value = payload.get(key, [])
            if not isinstance(value, list):
                raise ValueError(f"task field {key} must be an array")
            arrays[key] = [str(item) for item in value]

        return cls(
            id=str(payload["id"]),
            title=str(payload["title"]),
            status=str(payload["status"]),
            risk=str(risk),
            verify=str(payload.get("verify", "")),
            max_iterations=max_iterations,
            owns=arrays["owns"],
            touches=arrays["touches"],
            reads=arrays["reads"],
            deps=arrays["deps"],
            line_number=line_number,
            scope=str(payload.get("scope", "")),
            files=str(payload.get("files", "")),
            ac=arrays["ac"],
        )


@dataclass
class PlanDocument:
    version: str
    source_hash: str
    project: str
    level: int
    generated: str
    source: str
    tasks: list[PlanTask]

    def to_json_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["tasks"] = [asdict(task) for task in self.tasks]
        return payload


@dataclass
class MetricsRecord:
    timestamp: str
    project: str
    run_id: str
    task_id: str
    result: str
    iterations: int
    failure_type: str
    build_secs: int
    verify_secs: int


@dataclass
class StatusSnapshot:
    project: str
    level: str
    phase: str
    agent: str
    branch: str
    total: int
    done: int
    stuck: int
    remaining: int
    complete: bool
    complete_elapsed: str
    stuck_signal: str | None
    timestamp: str
    progress: str

    def to_json_dict(self) -> dict[str, Any]:
        return {
            "project": self.project,
            "level": _maybe_int(self.level),
            "phase": self.phase,
            "agent": self.agent,
            "branch": self.branch,
            "tasks": {
                "total": self.total,
                "done": self.done,
                "stuck": self.stuck,
                "remaining": self.remaining,
            },
            "complete": self.complete,
            "complete_elapsed": self.complete_elapsed or None,
            "stuck_signal": self.stuck_signal,
            "progress": self.progress,
            "timestamp": self.timestamp,
        }


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _maybe_int(value: str) -> Any:
    return int(value) if value.isdigit() else value


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def parse_simple_yaml(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.+?)\s*$", line)
        if not match:
            continue
        key, value = match.groups()
        values[key] = value.strip().strip("'\"")
    return values


def plan_source_hash(plan_file: Path) -> str:
    return hashlib.sha256(plan_file.read_bytes()).hexdigest()


def parse_file_list(raw: str) -> list[str]:
    text = raw.strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    items = [item.strip() for item in text.split(",")]
    return [item for item in items if item]


def parse_plan_markdown(plan_file: Path) -> PlanDocument:
    lines = plan_file.read_text(encoding="utf-8").splitlines()
    header = {"project": "", "level": "1", "generated": "", "source": ""}
    tasks: list[PlanTask] = []

    for line in lines:
        matched_header = False
        for key, pattern in HEADER_VALUE_RE.items():
            match = pattern.match(line)
            if match:
                header[key] = match.group(1)
                matched_header = True
                break
        if matched_header:
            continue
        if TASK_HEADER_RE.match(line):
            break

    current: PlanTask | None = None
    in_ac = False
    for line_number, line in enumerate(lines, start=1):
        task_header = TASK_HEADER_RE.match(line)
        if task_header:
            current = PlanTask(id=task_header.group(1), title=task_header.group(2))
            tasks.append(current)
            in_ac = False
            continue

        if current is None:
            continue

        checkbox = TASK_CHECKBOX_RE.match(line)
        if checkbox and checkbox.group(2) == current.id:
            current.line_number = line_number
            current.status = {
                "x": "complete",
                "X": "complete",
                "!": "stuck",
                " ": "pending",
            }[checkbox.group(1)]
            continue

        risk = RISK_RE.match(line)
        if risk:
            current.risk = risk.group(1).lower()
            in_ac = False
            continue

        verify = VERIFY_RE.match(line)
        if verify:
            current.verify = verify.group(1)
            in_ac = False
            continue

        max_iter = MAX_ITER_RE.match(line)
        if max_iter:
            current.max_iterations = int(max_iter.group(1))
            in_ac = False
            continue

        scope = SCOPE_RE.match(line)
        if scope:
            current.scope = scope.group(1).lower()
            in_ac = False
            continue

        files = FILES_RE.match(line)
        if files:
            current.files = files.group(1)
            in_ac = False
            continue

        if line.startswith("- AC:"):
            in_ac = True
            continue

        ac_item = AC_ITEM_RE.match(line)
        if in_ac and ac_item:
            current.ac.append(ac_item.group(1))
            continue

        if in_ac and not line.startswith("  -"):
            in_ac = False

        ownership = OWNERSHIP_RE.match(line)
        if ownership:
            field_name, raw_value = ownership.groups()
            setattr(current, field_name, parse_file_list(raw_value))
            continue

        if DEPENDENCIES_LINE_RE.match(line):
            for dep_id in re.findall(r"[0-9]{3}", line):
                if dep_id != current.id and dep_id not in current.deps:
                    current.deps.append(dep_id)

    in_dep_section = False
    for line in lines:
        if line in {"## Dependency Graph", "## Parallelism Assessment"}:
            in_dep_section = True
            continue
        if in_dep_section and line.startswith("## ") and line not in {
            "## Dependency Graph",
            "## Parallelism Assessment",
        }:
            break
        if not in_dep_section:
            continue

        normalized = line.replace("→", "->")
        chain_match = re.search(r"([0-9]{3}(\s*->\s*[0-9]{3})+)", normalized)
        if chain_match:
            chain_ids = re.findall(r"[0-9]{3}", chain_match.group(1))
            for previous, current_id in zip(chain_ids, chain_ids[1:]):
                task = next((task for task in tasks if task.id == current_id), None)
                if task and previous not in task.deps:
                    task.deps.append(previous)

        all_dep_match = TASK_ALL_DEP_RE.search(line)
        if all_dep_match:
            target_id = all_dep_match.group(1)
            task = next((task for task in tasks if task.id == target_id), None)
            if task:
                task.deps = [candidate.id for candidate in tasks if candidate.id != target_id]
            continue

        explicit_dep_match = TASK_LIST_DEP_RE.search(line)
        if explicit_dep_match:
            target_id, dep_list = explicit_dep_match.group(1), explicit_dep_match.group(2)
            task = next((task for task in tasks if task.id == target_id), None)
            if task:
                for dep in [entry.strip() for entry in dep_list.split(",")]:
                    if dep and dep not in task.deps:
                        task.deps.append(dep)

    return PlanDocument(
        version="1.0",
        source_hash=plan_source_hash(plan_file),
        project=header["project"],
        level=int(header["level"] or "1"),
        generated=header["generated"],
        source=header["source"],
        tasks=tasks,
    )


def load_plan_json(plan_json: Path) -> PlanDocument:
    payload = json.loads(plan_json.read_text(encoding="utf-8"))
    version = payload.get("version", "")
    if version != "1.0":
        raise ValueError(f"unsupported plan.json version: {version}")

    tasks_payload = payload.get("tasks")
    if not isinstance(tasks_payload, list) or not tasks_payload:
        raise ValueError("plan.json missing tasks")

    return PlanDocument(
        version="1.0",
        source_hash=str(payload.get("source_hash", "")),
        project=str(payload.get("project", "")),
        level=int(payload.get("level", 1)),
        generated=str(payload.get("generated", "")),
        source=str(payload.get("source", "")),
        tasks=[PlanTask.from_json(task) for task in tasks_payload],
    )


def write_plan_json(plan_document: PlanDocument, output_file: Path) -> None:
    _write_text(output_file, json.dumps(plan_document.to_json_dict(), indent=2) + "\n")


def load_best_plan(plan_file: Path, plan_json: Path) -> tuple[PlanDocument, str]:
    if not plan_file.exists():
        raise FileNotFoundError(f"plan file not found: {plan_file}")

    md_hash = plan_source_hash(plan_file)
    if plan_json.exists():
        try:
            plan_doc = load_plan_json(plan_json)
            json_fresh = False
            if plan_doc.source_hash:
                json_fresh = plan_doc.source_hash == md_hash
            else:
                json_fresh = plan_json.stat().st_mtime > plan_file.stat().st_mtime

            if json_fresh:
                return plan_doc, "plan_json"

            print("  Warning: plan.json is stale (does not match plan.md), using markdown path", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001
            print(f"  Warning: plan.json parse failed ({exc}), falling back to markdown", file=sys.stderr)

    return parse_plan_markdown(plan_file), "plan_md"


def emit_plan_shell(plan_document: PlanDocument, source_name: str) -> str:
    lines = [
        f"PLAN_PARSE_SOURCE={shlex.quote(source_name)}",
        f"PLAN_PARSE_TASK_COUNT={len(plan_document.tasks)}",
        "TASK_IDS=()",
        "TASK_TITLES=()",
        "TASK_STATUS=()",
        "TASK_RISKS=()",
        "TASK_OWNS=()",
        "TASK_TOUCHES=()",
        "TASK_READS=()",
        "TASK_VERIFY=()",
        "TASK_MAX_ITER=()",
        "TASK_LINES=()",
        "TASK_DEPS=()",
    ]

    for task in plan_document.tasks:
        lines.extend(
            [
                f"TASK_IDS+=({shlex.quote(task.id)})",
                f"TASK_TITLES+=({shlex.quote(task.title)})",
                f"TASK_STATUS+=({shlex.quote(task.status)})",
                f"TASK_RISKS+=({shlex.quote(task.risk)})",
                f"TASK_OWNS+=({shlex.quote(','.join(task.owns))})",
                f"TASK_TOUCHES+=({shlex.quote(','.join(task.touches))})",
                f"TASK_READS+=({shlex.quote(','.join(task.reads))})",
                f"TASK_VERIFY+=({shlex.quote(task.verify)})",
                f"TASK_MAX_ITER+=({shlex.quote(str(task.max_iterations))})",
                f"TASK_LINES+=({shlex.quote(str(task.line_number))})",
                f"TASK_DEPS+=({shlex.quote(','.join(task.deps))})",
            ]
        )

    return "\n".join(lines) + "\n"


def set_plan_task_status(plan_file: Path, task_id: str, status: str, plan_json: Path | None) -> None:
    if status not in STATUS_MARKERS:
        raise ValueError(f"unsupported task status: {status}")
    if not plan_file.exists():
        raise FileNotFoundError(f"plan file not found: {plan_file}")

    marker = STATUS_MARKERS[status]
    lines = plan_file.read_text(encoding="utf-8").splitlines()
    updated = False
    checkbox_pattern = re.compile(rf"^(- \[)[ xX!](\] {re.escape(task_id)}:)")
    new_lines: list[str] = []
    for line in lines:
        if checkbox_pattern.search(line):
            line = checkbox_pattern.sub(rf"\1{marker}\2", line, count=1)
            updated = True
        new_lines.append(line)

    if not updated:
        raise ValueError(f"task checkbox not found for {task_id}")

    _write_text(plan_file, "\n".join(new_lines) + "\n")
    if plan_json is not None:
        write_plan_json(parse_plan_markdown(plan_file), plan_json)


def metrics_file_for(spectra_dir: Path) -> Path:
    return spectra_dir / "metrics" / "tasks.jsonl"


def read_metrics_records(spectra_dir: Path) -> list[MetricsRecord]:
    metrics_file = metrics_file_for(spectra_dir)
    if not metrics_file.exists() or not metrics_file.read_text(encoding="utf-8").strip():
        return []

    records: list[MetricsRecord] = []
    for line in metrics_file.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        records.append(
            MetricsRecord(
                timestamp=str(payload.get("timestamp", "")),
                project=str(payload.get("project", "")),
                run_id=str(payload.get("run_id", "")),
                task_id=str(payload.get("task_id", "")),
                result=str(payload.get("result", "")),
                iterations=int(payload.get("iterations", 1)),
                failure_type=str(payload.get("failure_type", "")),
                build_secs=int(payload.get("build_secs", 0)),
                verify_secs=int(payload.get("verify_secs", 0)),
            )
        )
    return records


def append_metric(
    spectra_dir: Path,
    task_id: str,
    result: str,
    iterations: int,
    failure_type: str,
    build_secs: int,
    verify_secs: int,
    run_id: str,
    project_name: str,
) -> None:
    metrics_file = metrics_file_for(spectra_dir)
    metrics_file.parent.mkdir(parents=True, exist_ok=True)
    sanitized_failure = failure_type.replace('"', "").replace("\\", "").replace(" ", "_")
    record = MetricsRecord(
        timestamp=utc_now(),
        project=project_name,
        run_id=run_id,
        task_id=task_id,
        result=result,
        iterations=iterations,
        failure_type=sanitized_failure,
        build_secs=build_secs,
        verify_secs=verify_secs,
    )
    with metrics_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(asdict(record), separators=(",", ":")) + "\n")


def aggregate_metrics_records(records: list[MetricsRecord]) -> dict[str, int]:
    if not records:
        return {
            "total_tasks": 0,
            "pass_rate": 0,
            "avg_iterations": 0,
            "avg_build_secs": 0,
            "avg_verify_secs": 0,
            "first_pass_rate": 0,
            "pass_count": 0,
            "fail_count": 0,
            "stuck_count": 0,
        }

    total = len(records)
    pass_count = sum(1 for record in records if record.result == "PASS")
    fail_count = sum(1 for record in records if record.result == "FAIL")
    stuck_count = sum(1 for record in records if record.result == "STUCK")
    first_pass = sum(1 for record in records if record.result == "PASS" and record.iterations == 1)

    return {
        "total_tasks": total,
        "pass_count": pass_count,
        "fail_count": fail_count,
        "stuck_count": stuck_count,
        "pass_rate": (pass_count * 100) // total,
        "first_pass_rate": (first_pass * 100) // total,
        "avg_iterations": sum(record.iterations for record in records) // total,
        "avg_build_secs": sum(record.build_secs for record in records) // total,
        "avg_verify_secs": sum(record.verify_secs for record in records) // total,
    }


def aggregate_to_kv(records: list[MetricsRecord]) -> str:
    payload = aggregate_metrics_records(records)
    order = [
        "total_tasks",
        "pass_count",
        "fail_count",
        "stuck_count",
        "pass_rate",
        "first_pass_rate",
        "avg_iterations",
        "avg_build_secs",
        "avg_verify_secs",
    ]
    return "\n".join(f"{key}={payload[key]}" for key in order) + "\n"


def suggest_profile(records: list[MetricsRecord]) -> str:
    if len(records) < 3:
        return "standard"

    recent = records[-10:]
    total = len(recent)
    pass_count = sum(1 for record in recent if record.result == "PASS")
    stuck_count = sum(1 for record in recent if record.result == "STUCK")
    retried_count = sum(1 for record in recent if record.iterations > 1)
    pass_pct = (pass_count * 100) // total
    stuck_pct = (stuck_count * 100) // total

    if pass_pct >= 90 and retried_count == 0:
        return "quick"
    if stuck_pct >= 20 or retried_count >= 3:
        return "thorough"
    return "standard"


def prior_failure_warning(records: list[MetricsRecord]) -> str:
    failures = [record for record in records if record.result in {"FAIL", "STUCK"} and record.failure_type]
    if not failures:
        return ""
    counts: dict[str, int] = {}
    for record in failures:
        counts[record.failure_type] = counts.get(record.failure_type, 0) + 1
    common_type = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0]
    return (
        f"WARNING: Prior runs had {len(failures)} failure(s), most common type: "
        f"{common_type}. Pay extra attention to {common_type} patterns."
    )


def generate_retrospective(records: list[MetricsRecord], run_id: str) -> str:
    run_records = [record for record in records if record.run_id == run_id]
    if not run_records:
        return "No metrics recorded for this run.\n"

    run_total = len(run_records)
    run_pass = sum(1 for record in run_records if record.result == "PASS")
    run_fail = sum(1 for record in run_records if record.result == "FAIL")
    run_stuck = sum(1 for record in run_records if record.result == "STUCK")
    run_retried = sum(1 for record in run_records if record.iterations > 1)

    lines = [
        "## Run Retrospective",
        "",
        f"- **Run ID:** {run_id}",
        f"- **Tasks:** {run_total} total, {run_pass} passed, {run_fail} failed, {run_stuck} stuck",
    ]
    if run_total > 0:
        first_pass_rate = (((run_pass - run_retried) * 100) // run_total) if run_pass > 0 else 0
        retry_rate = (run_retried * 100) // run_total
        lines.append(f"- **First-pass rate:** {first_pass_rate}%")
        lines.append(f"- **Retry rate:** {retry_rate}%")

    failure_types = [record.failure_type for record in run_records if record.failure_type]
    if failure_types:
        lines.extend(["", "### Failure Breakdown"])
        counts: dict[str, int] = {}
        for failure_type in failure_types:
            counts[failure_type] = counts.get(failure_type, 0) + 1
        for failure_type, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
            lines.append(f"- {failure_type}: {count}")

    lines.append("")
    return "\n".join(lines)


def parse_signal_value(content: str, key: str) -> str:
    match = re.search(rf"{re.escape(key)}:\s*(.+)", content)
    return match.group(1).strip() if match else ""


def git_branch(project_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(project_root), "branch", "--show-current"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return "unknown"
    if result.returncode != 0:
        return "unknown"
    branch = result.stdout.strip()
    return branch or "unknown"


def build_status_snapshot(project_root: Path) -> StatusSnapshot:
    spectra_dir = project_root / ".spectra"
    signals_dir = spectra_dir / "signals"
    project_yaml = parse_simple_yaml(spectra_dir / "project.yaml")
    project_name = project_yaml.get("name", "unknown")
    project_level = project_yaml.get("level", "unknown")

    plan_file = spectra_dir / "plan.md"
    plan_json = spectra_dir / "plan.json"
    total = done = stuck = 0
    if plan_file.exists():
        plan_doc, _ = load_best_plan(plan_file, plan_json)
        total = len(plan_doc.tasks)
        done = sum(1 for task in plan_doc.tasks if task.status == "complete")
        stuck = sum(1 for task in plan_doc.tasks if task.status == "stuck")
        if total == 0:
            lines = plan_file.read_text(encoding="utf-8").splitlines()
            total = sum(1 for line in lines if re.match(r"^- \[[ xX!]\] [0-9]{3}:", line))
            done = sum(1 for line in lines if re.match(r"^- \[[xX]\] [0-9]{3}:", line))
            stuck = sum(1 for line in lines if re.match(r"^- \[!\] [0-9]{3}:", line))
            if total == 0:
                total = sum(1 for line in lines if re.match(r"^- \[.\]", line))
                done = sum(1 for line in lines if re.match(r"^- \[[xX]\]", line))
                stuck = 0

    remaining = max(total - done - stuck, 0)
    phase = _read_text(signals_dir / "PHASE").strip() or "unknown"
    agent = _read_text(signals_dir / "AGENT").strip() or "unknown"
    complete_content = _read_text(signals_dir / "COMPLETE")
    stuck_content = _read_text(signals_dir / "STUCK")
    complete_elapsed = parse_signal_value(complete_content, "Elapsed")
    stuck_reason = parse_signal_value(stuck_content, "Reason") or None
    progress = f"{done}/{total} tasks ({stuck} stuck)"

    return StatusSnapshot(
        project=project_name,
        level=project_level,
        phase=phase,
        agent=agent,
        branch=git_branch(project_root),
        total=total,
        done=done,
        stuck=stuck,
        remaining=remaining,
        complete=(signals_dir / "COMPLETE").exists(),
        complete_elapsed=complete_elapsed,
        stuck_signal=stuck_reason,
        timestamp=utc_now(),
        progress=progress,
    )


def render_status_text(snapshot: StatusSnapshot) -> str:
    lines = [
        "",
        "  SPECTRA Status",
        "  ────────────────────────────────────",
        f"  Project:  {snapshot.project}",
        f"  Level:    {snapshot.level}",
        f"  Branch:   {snapshot.branch}",
        f"  Phase:    {snapshot.phase}",
        f"  Agent:    {snapshot.agent}",
        "  ────────────────────────────────────",
        f"  Tasks:    {snapshot.done}/{snapshot.total} complete",
        f"  Remaining: {snapshot.remaining}",
        f"  Stuck:    {snapshot.stuck}",
        f"  Progress: {snapshot.progress}",
    ]
    if snapshot.complete_elapsed:
        lines.extend(
            [
                "  ────────────────────────────────────",
                f"  COMPLETE (elapsed: {snapshot.complete_elapsed})",
            ]
        )
    elif snapshot.stuck_signal:
        lines.extend(
            [
                "  ────────────────────────────────────",
                f"  STUCK: {snapshot.stuck_signal}",
            ]
        )
    lines.append("")
    return "\n".join(lines)


def cmd_plan_extract(args: argparse.Namespace) -> int:
    plan_doc = parse_plan_markdown(Path(args.file))
    payload = json.dumps(plan_doc.to_json_dict(), indent=2) + "\n"
    if args.output:
        _write_text(Path(args.output), payload)
    else:
        sys.stdout.write(payload)

    if args.validate:
        target = Path(args.output) if args.output else None
        if target is not None:
            json.loads(target.read_text(encoding="utf-8"))
            print("JSON validation: PASS", file=sys.stderr)
        else:
            print("JSON validation: skipped (--validate requires --output)", file=sys.stderr)
    return 0


def cmd_plan_emit_shell(args: argparse.Namespace) -> int:
    plan_doc, source_name = load_best_plan(Path(args.plan_file), Path(args.plan_json))
    sys.stdout.write(emit_plan_shell(plan_doc, source_name))
    return 0


def cmd_plan_set_status(args: argparse.Namespace) -> int:
    set_plan_task_status(
        Path(args.plan_file),
        args.task_id,
        args.status,
        Path(args.plan_json) if args.plan_json else None,
    )
    return 0


def cmd_metrics_record(args: argparse.Namespace) -> int:
    project_name = Path.cwd().name
    append_metric(
        Path(args.spectra_dir),
        args.task_id,
        args.result,
        int(args.iterations),
        args.failure_type or "",
        int(args.build_secs),
        int(args.verify_secs),
        args.run_id,
        project_name,
    )
    return 0


def cmd_metrics_aggregate(args: argparse.Namespace) -> int:
    sys.stdout.write(aggregate_to_kv(read_metrics_records(Path(args.spectra_dir))))
    return 0


def cmd_metrics_read(args: argparse.Namespace) -> int:
    records = read_metrics_records(Path(args.spectra_dir))
    if args.max_lines > 0:
        records = records[-args.max_lines :]
    for record in records:
        sys.stdout.write(json.dumps(asdict(record), separators=(",", ":")) + "\n")
    return 0


def cmd_metrics_suggest_profile(args: argparse.Namespace) -> int:
    sys.stdout.write(suggest_profile(read_metrics_records(Path(args.spectra_dir))) + "\n")
    return 0


def cmd_metrics_retrospective(args: argparse.Namespace) -> int:
    sys.stdout.write(generate_retrospective(read_metrics_records(Path(args.spectra_dir)), args.run_id))
    return 0


def cmd_metrics_prior_failure(args: argparse.Namespace) -> int:
    warning = prior_failure_warning(read_metrics_records(Path(args.spectra_dir)))
    if warning:
        sys.stdout.write(warning + "\n")
    return 0


def cmd_status_snapshot(args: argparse.Namespace) -> int:
    snapshot = build_status_snapshot(Path(args.project_root))
    payload = json.dumps(snapshot.to_json_dict(), indent=2) + "\n"
    if args.output:
        _write_text(Path(args.output), payload)

    if args.format == "json":
        sys.stdout.write(payload)
    elif args.format == "text":
        sys.stdout.write(render_status_text(snapshot))
    else:
        sys.stdout.write(snapshot.progress + "\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="spectra-structured", add_help=True)
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan")
    plan_sub = plan_parser.add_subparsers(dest="plan_command", required=True)

    plan_extract = plan_sub.add_parser("extract")
    plan_extract.add_argument("--file", required=True)
    plan_extract.add_argument("--output")
    plan_extract.add_argument("--validate", action="store_true")
    plan_extract.set_defaults(func=cmd_plan_extract)

    plan_emit = plan_sub.add_parser("emit-shell")
    plan_emit.add_argument("--plan-file", required=True)
    plan_emit.add_argument("--plan-json", required=True)
    plan_emit.set_defaults(func=cmd_plan_emit_shell)

    plan_set_status = plan_sub.add_parser("set-status")
    plan_set_status.add_argument("--plan-file", required=True)
    plan_set_status.add_argument("--plan-json")
    plan_set_status.add_argument("--task-id", required=True)
    plan_set_status.add_argument("--status", choices=sorted(STATUS_MARKERS), required=True)
    plan_set_status.set_defaults(func=cmd_plan_set_status)

    metrics_parser = subparsers.add_parser("metrics")
    metrics_sub = metrics_parser.add_subparsers(dest="metrics_command", required=True)

    metrics_record = metrics_sub.add_parser("record")
    metrics_record.add_argument("--spectra-dir", required=True)
    metrics_record.add_argument("--task-id", required=True)
    metrics_record.add_argument("--result", required=True)
    metrics_record.add_argument("--iterations", required=True)
    metrics_record.add_argument("--failure-type", default="")
    metrics_record.add_argument("--build-secs", required=True)
    metrics_record.add_argument("--verify-secs", required=True)
    metrics_record.add_argument("--run-id", required=True)
    metrics_record.set_defaults(func=cmd_metrics_record)

    metrics_aggregate = metrics_sub.add_parser("aggregate")
    metrics_aggregate.add_argument("--spectra-dir", required=True)
    metrics_aggregate.set_defaults(func=cmd_metrics_aggregate)

    metrics_read = metrics_sub.add_parser("read")
    metrics_read.add_argument("--spectra-dir", required=True)
    metrics_read.add_argument("--max-lines", type=int, default=0)
    metrics_read.set_defaults(func=cmd_metrics_read)

    metrics_profile = metrics_sub.add_parser("suggest-profile")
    metrics_profile.add_argument("--spectra-dir", required=True)
    metrics_profile.set_defaults(func=cmd_metrics_suggest_profile)

    metrics_retro = metrics_sub.add_parser("retrospective")
    metrics_retro.add_argument("--spectra-dir", required=True)
    metrics_retro.add_argument("--run-id", required=True)
    metrics_retro.set_defaults(func=cmd_metrics_retrospective)

    metrics_prior = metrics_sub.add_parser("prior-failure")
    metrics_prior.add_argument("--spectra-dir", required=True)
    metrics_prior.add_argument("--task-id", required=False)
    metrics_prior.set_defaults(func=cmd_metrics_prior_failure)

    status_parser = subparsers.add_parser("status")
    status_sub = status_parser.add_subparsers(dest="status_command", required=True)

    status_snapshot = status_sub.add_parser("snapshot")
    status_snapshot.add_argument("--project-root", required=True)
    status_snapshot.add_argument("--format", choices=("json", "text", "progress"), default="json")
    status_snapshot.add_argument("--output")
    status_snapshot.set_defaults(func=cmd_status_snapshot)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except Exception as exc:  # noqa: BLE001
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
