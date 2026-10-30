#!/usr/bin/env python3
"""One-command local refresh for every time-based dashboard dataset.

The existing maintenance pipeline refreshes the original dashboard tabs. This
wrapper then merges those fresh data blocks into the exercise-enabled page and
refreshes the three daily exercise aggregates. Nothing is published or pushed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parent
DEFAULT_REPO = ROOT
DEFAULT_MAINTENANCE = Path(
    "/Users/ludishen/Documents/DINO AI/专题——体验课/体验课数据看板/维护工作区"
)
PROJECT = "dino-english-497507"
GIB = 1024**3
MIB = 1024**2
PER_QUERY_LIMIT = 20 * GIB
TOTAL_QUERY_LIMIT = 64 * GIB
EXERCISE_START = date(2026, 8, 1)
PLACEMENT_START = date(2026, 1, 1)
AFTERCLASS_SCAN_START = date(2026, 9, 14)
AFTERCLASS_START = date(2026, 9, 21)

EXERCISE_JOBS = (
    {
        "name": "exercise_profile_performance",
        "sql": ROOT / "bq_exercise_profile_performance.sql",
        "output": "exercise_profile_performance.csv",
        "fields": (
            "answer_date", "scene", "level", "question_type", "age_band",
            "ability_code", "users", "questions", "attempts", "once",
            "twice", "three", "four_plus", "avg_attempts", "p50", "p90",
        ),
    },
    {
        "name": "exercise_afterclass_daily",
        "sql": ROOT / "bq_exercise_afterclass_daily.sql",
        "output": "exercise_afterclass_daily.csv",
        "fields": (
            "answer_date", "scene", "users", "questions", "attempts", "once",
            "twice", "three", "four_plus", "avg_attempts", "p50", "p90",
        ),
    },
    {
        "name": "exercise_country_daily",
        "sql": ROOT / "bq_exercise_country_daily.sql",
        "output": "exercise_country_daily.csv",
        "fields": (
            "answer_date", "scene", "level", "country", "users", "questions",
            "attempts", "once", "twice", "three", "four_plus",
        ),
    },
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="一键更新看板所有时间维度数据（只更新本地，不部署）"
    )
    parser.add_argument("--resume", action="store_true", help="从上次中断的原看板刷新继续")
    parser.add_argument(
        "--exercise-only", action="store_true",
        help="只更新练习分析日粒度数据，不跑原看板整套任务",
    )
    parser.add_argument(
        "--validate-only", action="store_true",
        help="只校验当前文件，不查 BigQuery，不改文件",
    )
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO)
    parser.add_argument(
        "--maintenance-dir", type=Path,
        default=Path(os.environ.get("TRIAL_BOARD_MAINTENANCE", DEFAULT_MAINTENANCE)),
    )
    parser.add_argument(
        "--query-end", type=date.fromisoformat, default=datetime.now(timezone.utc).date(),
        help="查询截止 UTC 日，默认今天（YYYY-MM-DD）",
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_one(pattern: str, replacement, text: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"无法唯一定位 {label}")
    return result


def script_block(html: str, element_id: str) -> str:
    match = re.search(
        rf'(<script\s+type="text/plain"\s+id="{re.escape(element_id)}">)(.*?)(</script>)',
        html,
        re.S,
    )
    if not match:
        raise RuntimeError(f"缺少 HTML 数据块: {element_id}")
    return match.group(2)


def constant_value(html: str, name: str) -> str:
    match = re.search(rf'const\s+{re.escape(name)}\s*=\s*"([^"]+)";', html)
    if not match:
        raise RuntimeError(f"缺少 HTML 常量: {name}")
    return match.group(1)


def replace_constant(html: str, name: str, value: str) -> str:
    return replace_one(
        rf'const\s+{re.escape(name)}\s*=\s*"[^"]+";',
        f'const {name} = "{value}";',
        html,
        name,
    )


def merge_legacy_refresh(current_html: str, fresh_html: str) -> str:
    """Merge original-tab data without replacing the exercise-enabled UI."""
    merged = current_html
    for element_id in ("class-csv", "formal-class-csv"):
        content = script_block(fresh_html, element_id)
        merged = replace_one(
            rf'(<script\s+type="text/plain"\s+id="{element_id}">).*?(</script>)',
            lambda match, value=content: match.group(1) + value + match.group(2),
            merged,
            element_id,
        )
    for name in ("DATA_END", "FORMAL_DATA_END"):
        merged = replace_constant(merged, name, constant_value(fresh_html, name))

    fresh_presets = re.search(r'const\s+PRESETS\s*=\s*\[.*?\n\];', fresh_html, re.S)
    if not fresh_presets:
        raise RuntimeError("新产物中缺少 PRESETS")
    merged = replace_one(
        r'const\s+PRESETS\s*=\s*\[.*?\n\];', fresh_presets.group(), merged, "PRESETS"
    )
    return merged


def load_bigquery_client(maintenance: Path):
    try:
        from google.cloud import bigquery
    except ImportError as error:
        raise RuntimeError("缺少 google-cloud-bigquery，请在原维护环境中运行") from error

    auth_path = maintenance / "Data" / "bigquery_auth.py"
    if not auth_path.is_file():
        raise RuntimeError(f"找不到 BigQuery 登录配置: {auth_path}")
    spec = importlib.util.spec_from_file_location("trial_board_bigquery_auth", auth_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载 BigQuery 登录配置")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return bigquery, bigquery.Client(project=PROJECT, credentials=module.get_credentials())


def ensure_bigquery_runtime(maintenance: Path) -> None:
    """Re-run with the established maintenance venv when system Python is bare."""
    try:
        import google.cloud.bigquery  # noqa: F401
        return
    except ImportError:
        pass
    venv_python = maintenance / ".venv" / "bin" / "python"
    if not venv_python.is_file():
        raise RuntimeError(
            "缺少 google-cloud-bigquery，且找不到原维护环境的 .venv/bin/python"
        )
    print(f"切换到原维护 Python 环境: {venv_python}", flush=True)
    os.execv(str(venv_python), [str(venv_python), str(Path(__file__).resolve()), *sys.argv[1:]])


def query_parameters(bigquery, end_date: date, sql: str):
    values = {
        "start_date": EXERCISE_START,
        "end_date": end_date,
        "placement_start_date": PLACEMENT_START,
        "scan_start_date": AFTERCLASS_SCAN_START,
        "afterclass_start_date": AFTERCLASS_START,
    }
    required = set(re.findall(r"@([A-Za-z_][A-Za-z0-9_]*)", sql))
    unknown = required - values.keys()
    if unknown:
        raise RuntimeError(f"SQL 存在未定义参数: {sorted(unknown)}")
    return [
        bigquery.ScalarQueryParameter(name, "DATE", values[name])
        for name in sorted(required)
    ]


def reserve_bytes(estimate: int, referenced_table_count: int) -> int:
    return max(
        64 * MIB,
        math.ceil(estimate / MIB) * MIB + 32 * MIB * max(1, referenced_table_count),
    )


def query_exercise_data(maintenance: Path, end_date: date):
    bigquery, client = load_bigquery_client(maintenance)
    total_reserved = 0
    results = {}
    costs = []
    for job in EXERCISE_JOBS:
        sql = Path(job["sql"]).read_text(encoding="utf-8")
        parameters = query_parameters(bigquery, end_date, sql)
        probe_config = bigquery.QueryJobConfig(
            query_parameters=parameters, dry_run=True, use_query_cache=False
        )
        probe = client.query(sql, job_config=probe_config)
        if probe.statement_type != "SELECT" or probe.total_bytes_processed is None:
            raise RuntimeError(f'{job["name"]}: 只允许可估算的 SELECT')
        estimate = int(probe.total_bytes_processed)
        reserved = reserve_bytes(estimate, len(probe.referenced_tables or []))
        total_reserved += reserved
        print(
            f'QUERY {job["name"]}: estimate={estimate/GIB:.3f} GiB; '
            f'run_reserved={total_reserved/GIB:.3f}/{TOTAL_QUERY_LIMIT/GIB:.0f} GiB',
            flush=True,
        )
        if reserved > PER_QUERY_LIMIT or total_reserved > TOTAL_QUERY_LIMIT:
            raise RuntimeError("查询超过成本保护上限，已在执行前停止")
        config = bigquery.QueryJobConfig(
            query_parameters=parameters,
            maximum_bytes_billed=reserved,
            use_query_cache=True,
        )
        query_job = client.query(sql, job_config=config)
        rows = [dict(row.items()) for row in query_job.result(timeout=900)]
        results[job["name"]] = rows
        costs.append(
            {
                "name": job["name"],
                "estimated_bytes": estimate,
                "reserved_bytes": reserved,
                "processed_bytes": query_job.total_bytes_processed or 0,
                "billed_bytes": query_job.total_bytes_billed or 0,
                "cache_hit": bool(query_job.cache_hit),
                "job_id": query_job.job_id,
            }
        )
    return results, costs


def csv_value(value) -> str:
    if value is None:
        return ""
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def write_csv(path: Path, fields: Sequence[str], rows: Iterable[Mapping]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=fields, extrasaction="raise", lineterminator="\n"
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({field: csv_value(row.get(field)) for field in fields})


def validate_csv(path: Path, fields: Sequence[str]) -> dict:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != tuple(fields):
            raise RuntimeError(
                f"{path.name} 字段不符: {reader.fieldnames}; expected={list(fields)}"
            )
        rows = 0
        dates = []
        for row in reader:
            rows += 1
            if row.get("answer_date"):
                dates.append(date.fromisoformat(row["answer_date"]))
        if rows == 0:
            raise RuntimeError(f"{path.name} 没有数据")
    return {
        "rows": rows,
        "min_date": min(dates).isoformat() if dates else None,
        "max_date": max(dates).isoformat() if dates else None,
        "sha256": sha256(path),
    }


def validate_html(html: str, expected_exercise_end: str | None = None) -> dict:
    required = (
        'data-board="exercise"',
        'id="exercise-scene-wrap"',
        'id="class-csv"',
        'id="formal-class-csv"',
        "一次通过率",
        "const EXERCISE_DATA_END",
    )
    missing = [token for token in required if token not in html]
    if missing:
        raise RuntimeError(f"HTML 缺少必需内容: {missing}")
    if expected_exercise_end and constant_value(html, "EXERCISE_DATA_END") != expected_exercise_end:
        raise RuntimeError("HTML 的 EXERCISE_DATA_END 未更新")
    if "__CLASS_CSV__" in html or "__FORMAL_CLASS_CSV__" in html:
        raise RuntimeError("HTML 仍有未渲染占位符")
    return {
        "data_end": constant_value(html, "DATA_END"),
        "formal_data_end": constant_value(html, "FORMAL_DATA_END"),
        "exercise_data_end": constant_value(html, "EXERCISE_DATA_END"),
    }


def latest_legacy_html(maintenance: Path) -> Path:
    pointer = maintenance / "课程治理" / "outputs" / "dashboard-refresh" / "latest-run.json"
    if not pointer.is_file():
        raise RuntimeError(f"找不到原看板刷新指针: {pointer}")
    stage = Path(json.loads(pointer.read_text(encoding="utf-8"))["stage"]).resolve()
    if stage.parent != pointer.parent.resolve() or not (stage / "result.json").is_file():
        raise RuntimeError("原看板刷新未完成，或 stage 路径不合法")
    output = stage / "index.html"
    if not output.is_file():
        raise RuntimeError(f"原看板刷新产物不存在: {output}")
    return output


def run_legacy_refresh(maintenance: Path, resume: bool) -> Path:
    runner = maintenance / "本地试更新.py"
    if not runner.is_file():
        raise RuntimeError(f"找不到原看板刷新脚本: {runner}")
    command = [sys.executable, str(runner)]
    if resume:
        command.append("--resume")
    print("\n[1/4] 更新原看板全部时间数据", flush=True)
    try:
        subprocess.run(command, cwd=maintenance, check=True)
    except subprocess.CalledProcessError:
        # A large refresh can reach the run-wide guard when a later exporter
        # asks for an identical query that already completed earlier in the
        # same stage (currently trial/formal after-class events). Reuse that
        # immutable BigQuery job result, but only when both SQL and parameters
        # are byte-for-byte equivalent; all new queries retain the guard.
        print(
            "原链路未完成；尝试安全复用同一 stage 内的重复 BigQuery 结果后继续",
            flush=True,
        )
        resume_legacy_with_cached_queries(maintenance)
    return latest_legacy_html(maintenance)


def resume_legacy_with_cached_queries(maintenance: Path) -> None:
    from google.cloud import bigquery

    tools_dir = maintenance / "课程治理" / "tools"
    runner_path = maintenance / "本地试更新.py"
    sys.path.insert(0, str(tools_dir))
    try:
        pipeline = __import__("refresh_trial_dashboard_data")
        spec = importlib.util.spec_from_file_location("trial_board_guarded_runner", runner_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("无法加载原看板查询保护器")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        stage = Path(json.loads(pipeline.POINTER.read_text(encoding="utf-8"))["stage"])
        ledger = json.loads((stage / "query-costs.json").read_text(encoding="utf-8"))
        completed = {}
        for entry in ledger.get("queries", []):
            if entry.get("status") == "done" and entry.get("job_id"):
                completed.setdefault(entry["sql_sha256"], []).append(entry)

        original = bigquery.Client.query

        def query_signature(value) -> str:
            if isinstance(value, bigquery.QueryJobConfig):
                query = value.to_api_repr().get("query", {})
            else:
                query = value._properties.get("configuration", {}).get("query", {})
            comparable = {
                "queryParameters": query.get("queryParameters", []),
                "parameterMode": query.get("parameterMode"),
                "useLegacySql": query.get("useLegacySql", False),
            }
            return json.dumps(comparable, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

        def reuse_or_guard(client, query, job_config=None, **kwargs):
            digest = hashlib.sha256(query.encode()).hexdigest()
            requested = query_signature(job_config or bigquery.QueryJobConfig())
            for entry in reversed(completed.get(digest, [])):
                previous_job = client.get_job(entry["job_id"], location=entry.get("location"))
                if (
                    previous_job.state == "DONE"
                    and not previous_job.error_result
                    and query_signature(previous_job) == requested
                ):
                    print(
                        f'REUSE QUERY: job={entry["job_id"]} '
                        f'billed={entry.get("billed_bytes", 0)/GIB:.3f} GiB (no rescan)',
                        flush=True,
                    )
                    return previous_job
            return runner.guarded_query(
                original, pipeline, client, query, job_config=job_config, **kwargs
            )

        previous_argv = sys.argv[:]
        try:
            bigquery.Client.query = reuse_or_guard
            sys.argv = [str(runner_path), "--resume"]
            pipeline.main()
        finally:
            bigquery.Client.query = original
            sys.argv = previous_argv
    finally:
        if sys.path and sys.path[0] == str(tools_dir):
            sys.path.pop(0)


def copy_before(run_dir: Path, repo: Path) -> None:
    before = run_dir / "before"
    before.mkdir(parents=True)
    shutil.copy2(repo / "index.html", before / "index.html")
    for job in EXERCISE_JOBS:
        source = repo / "data" / str(job["output"])
        if source.is_file():
            shutil.copy2(source, before / source.name)


def validate_current(repo: Path) -> dict:
    html = (repo / "index.html").read_text(encoding="utf-8")
    report = {"html": validate_html(html), "files": {}}
    for job in EXERCISE_JOBS:
        path = repo / "data" / str(job["output"])
        report["files"][path.name] = validate_csv(path, job["fields"])
    return report


def main() -> None:
    args = parse_args()
    repo = args.repo.resolve()
    maintenance = args.maintenance_dir.expanduser().resolve()
    if not (repo / "index.html").is_file():
        raise SystemExit(f"看板仓库不正确: {repo}")
    if args.validate_only:
        print(json.dumps(validate_current(repo), ensure_ascii=False, indent=2))
        return
    ensure_bigquery_runtime(maintenance)

    previous_report = validate_current(repo)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run_dir = ROOT / ".refresh-runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    copy_before(run_dir, repo)
    merged_html = (repo / "index.html").read_text(encoding="utf-8")

    legacy_source = None
    if not args.exercise_only:
        legacy_source = run_legacy_refresh(maintenance, args.resume)
        merged_html = merge_legacy_refresh(
            merged_html, legacy_source.read_text(encoding="utf-8")
        )
    else:
        print("\n[1/4] 跳过原看板数据（--exercise-only）", flush=True)

    print("\n[2/4] 更新练习分析日粒度数据", flush=True)
    results, costs = query_exercise_data(maintenance, args.query_end)
    with tempfile.TemporaryDirectory(prefix="dashboard-refresh-", dir=ROOT) as temp_name:
        temp = Path(temp_name)
        csv_reports = {}
        max_dates = []
        for job in EXERCISE_JOBS:
            output = temp / str(job["output"])
            write_csv(output, job["fields"], results[job["name"]])
            report = validate_csv(output, job["fields"])
            csv_reports[output.name] = report
            if report["max_date"]:
                max_dates.append(report["max_date"])
            previous = previous_report["files"].get(output.name, {})
            if previous.get("max_date") and report.get("max_date") < previous["max_date"]:
                raise RuntimeError(
                    f'{output.name} 最大日期从 {previous["max_date"]} '
                    f'回退到 {report["max_date"]}，已停止覆盖'
                )
        if not max_dates:
            raise RuntimeError("练习分析没有返回任何日期")
        exercise_end = max(max_dates)
        merged_html = replace_constant(merged_html, "EXERCISE_DATA_END", exercise_end)
        html_report = validate_html(merged_html, exercise_end)
        candidate = temp / "index.html"
        candidate.write_text(merged_html, encoding="utf-8")

        print("\n[3/4] 校验并原子替换本地文件", flush=True)
        try:
            for job in EXERCISE_JOBS:
                destination = repo / "data" / str(job["output"])
                destination.parent.mkdir(parents=True, exist_ok=True)
                os.replace(temp / str(job["output"]), destination)
            os.replace(candidate, repo / "index.html")
            final_report = validate_current(repo)
        except BaseException:
            before = run_dir / "before"
            shutil.copy2(before / "index.html", repo / "index.html")
            for job in EXERCISE_JOBS:
                backup = before / str(job["output"])
                if backup.is_file():
                    shutil.copy2(backup, repo / "data" / str(job["output"]))
            raise
    manifest = {
        "run_id": run_id,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repo": str(repo),
        "legacy_source": str(legacy_source) if legacy_source else None,
        "query_end": args.query_end.isoformat(),
        "html": html_report,
        "csv": csv_reports,
        "query_costs": costs,
        "archery": {
            "status": "reused-static-catalog",
            "note": "Archery 题型定义是非时间维表；时间指标全部由 BigQuery 重算。",
        },
        "final_validation": final_report,
        "published": False,
    }
    (run_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("\n[4/4] 完成（未部署）", flush=True)
    print(
        json.dumps(
            {
                "exercise_data_end": exercise_end,
                "data_end": html_report["data_end"],
                "formal_data_end": html_report["formal_data_end"],
                "manifest": str(run_dir / "manifest.json"),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
