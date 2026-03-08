#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/root/.openclaw/logs/hourly_restart.jsonl"
REASON="hourly_60m_session_reset"
MAX_RETRIES=1
RETRY_DELAY_SEC=20
SESSION_KEY="agent:main:main"
MEMORY_HELPER="/root/bin/consolidate_daily_memory.mjs"
USER_TIMEZONE="America/Buenos_Aires"
export OPENCLAW_MEMORY_HELPER="$MEMORY_HELPER"
export OPENCLAW_MEMORY_TIMEZONE="$USER_TIMEZONE"

python3 - "$LOG_FILE" "$REASON" "$MAX_RETRIES" "$RETRY_DELAY_SEC" "$SESSION_KEY" <<'PY'
import datetime
import json
import os
import subprocess
import sys
import time
import uuid

log_file, reason, max_retries, retry_delay_sec, session_key = (
    sys.argv[1],
    sys.argv[2],
    int(sys.argv[3]),
    int(sys.argv[4]),
    sys.argv[5],
)
os.makedirs(os.path.dirname(log_file), exist_ok=True)


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).astimezone().isoformat()


def get_gateway_pid():
    try:
        out = subprocess.check_output(["pgrep", "-f", "openclaw-gateway"], text=True).strip().splitlines()
    except Exception:
        return None
    if not out:
        return None
    first = out[0].strip()
    return int(first) if first.isdigit() else None


def get_uptime_sec(pid):
    if pid is None:
        return None
    try:
        out = subprocess.check_output(["ps", "-o", "etimes=", "-p", str(pid)], text=True).strip()
        return int(out) if out else None
    except Exception:
        return None


def get_session_snapshot():
    path = "/root/.openclaw/agents/main/sessions/sessions.json"
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None, {"total": None, "input": None, "output": None}

    entry = data.get(session_key) or {}
    session_id = entry.get("sessionId")
    token_window = {
        "total": entry.get("totalTokens"),
        "input": entry.get("inputTokens"),
        "output": entry.get("outputTokens"),
    }
    return session_id, token_window


def write_log(event, **fields):
    rec = {
        "ts": now_iso(),
        "event": event,
        "reason": reason,
        **fields,
    }
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

def consolidate_memory(agent_id, session_key_value, workspace_dir, sessions_dir):
    helper = os.environ.get("OPENCLAW_MEMORY_HELPER", "/root/bin/consolidate_daily_memory.mjs")
    if not os.path.exists(helper):
        write_log(
            "memory_consolidation_skipped",
            agent_id=agent_id,
            session_key=session_key_value,
            helper=helper,
            detail="helper_missing",
        )
        return

    cmd = [
        "node",
        helper,
        "--agent-id",
        agent_id,
        "--session-key",
        session_key_value,
        "--workspace",
        workspace_dir,
        "--sessions-dir",
        sessions_dir,
        "--timezone",
        os.environ.get("OPENCLAW_MEMORY_TIMEZONE", "America/Buenos_Aires"),
        "--timestamp",
        now_iso(),
        "--json",
    ]

    try:
        cp = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except Exception as exc:
        write_log(
            "memory_consolidation_failed",
            agent_id=agent_id,
            session_key=session_key_value,
            detail=str(exc),
        )
        return

    if cp.returncode != 0:
        write_log(
            "memory_consolidation_failed",
            agent_id=agent_id,
            session_key=session_key_value,
            detail=f"rc={cp.returncode}",
            stderr=cp.stderr.strip()[:500],
        )
        return

    try:
        payload = json.loads(cp.stdout or "{}")
    except Exception:
        payload = {"raw": (cp.stdout or "")[:500]}

    status = payload.get("status", "unknown")
    write_log(
        f"memory_consolidation_{status}",
        agent_id=agent_id,
        session_key=session_key_value,
        session_file=payload.get("sessionFile"),
        memory_file=payload.get("memoryFile"),
        relevant_messages=payload.get("relevantMessages"),
        sections=payload.get("sections"),
        detail=payload.get("reason"),
    )


def resolve_romualdo_session_key():
    path = "/root/.openclaw/agents/romualdo/sessions/sessions.json"
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None

    candidates = []
    for key, value in (data or {}).items():
        if not isinstance(key, str) or not key.startswith("agent:romualdo:"):
            continue
        updated = value.get("updatedAt") if isinstance(value, dict) else 0
        candidates.append((int(updated or 0), key))

    if not candidates:
        return None
    candidates.sort(reverse=True)
    return candidates[0][1]


def reset_romualdo(log_file, reason):
    agent_id = "romualdo"
    session_key_rom = resolve_romualdo_session_key()
    if not session_key_rom:
        write_log(
            "restart_failed",
            agent_id=agent_id,
            session_key=None,
            reset_attempt=0,
            reset_failed=True,
            reason="session_key_not_found",
        )
        return

    consolidate_memory(agent_id, session_key_rom, "/root/openclaw-romualdo", "/root/.openclaw/agents/romualdo/sessions")

    attempt = 0
    write_log(
        "restart_attempt",
        agent_id=agent_id,
        session_key=session_key_rom,
        reset_attempt=attempt,
    )
    try:
        params = json.dumps({"key": session_key_rom}, ensure_ascii=False)
        cp = subprocess.run(
            ["openclaw", "gateway", "call", "sessions.reset", "--params", params, "--json"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if cp.returncode != 0:
            raise RuntimeError(f"gateway_call_failed rc={cp.returncode} stderr={cp.stderr.strip()[:500]}")
        write_log(
            "restart_success",
            agent_id=agent_id,
            session_key=session_key_rom,
            reset_attempt=attempt,
            reset_success=True,
        )
    except Exception as e:
        write_log(
            "restart_failed",
            agent_id=agent_id,
            session_key=session_key_rom,
            reset_attempt=attempt,
            reset_failed=True,
            reason=str(e),
        )


run_id = str(uuid.uuid4())
attempt = 0

consolidate_memory("main", session_key, "/root/clawd", "/root/.openclaw/agents/main/sessions")

while True:
    pid_before = get_gateway_pid()
    uptime_before = get_uptime_sec(pid_before)
    session_id_before, token_before = get_session_snapshot()

    write_log(
        "restart_attempt",
        run_id=run_id,
        attempt=attempt,
        uptime_sec=uptime_before,
        pid_before=pid_before,
        session_id_before=session_id_before,
        token_window_before=token_before,
    )

    try:
        params = json.dumps({"key": session_key}, ensure_ascii=False)
        cp = subprocess.run(
            ["openclaw", "gateway", "call", "sessions.reset", "--params", params, "--json"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if cp.returncode != 0:
            raise RuntimeError(f"gateway_call_failed rc={cp.returncode} stderr={cp.stderr.strip()[:500]}")

        payload = {}
        try:
            payload = json.loads(cp.stdout)
        except Exception:
            payload = {"raw": cp.stdout[:500]}

        pid_after = get_gateway_pid()
        uptime_after = get_uptime_sec(pid_after)
        session_id_after, token_after = get_session_snapshot()

        write_log(
            "restart_success",
            run_id=run_id,
            attempt=attempt,
            uptime_sec=uptime_after,
            pid_before=pid_before,
            pid_after=pid_after,
            session_id_before=session_id_before,
            session_id_after=session_id_after,
            token_window_before=token_before,
            token_window_after=token_after,
            gateway_ok=payload.get("ok"),
        )
        reset_romualdo(log_file, reason)
        sys.exit(0)
    except Exception as e:
        pid_after = get_gateway_pid()
        uptime_after = get_uptime_sec(pid_after)
        session_id_after, token_after = get_session_snapshot()

        write_log(
            "restart_failed",
            run_id=run_id,
            attempt=attempt,
            error=str(e),
            uptime_sec=uptime_after,
            pid_before=pid_before,
            pid_after=pid_after,
            session_id_before=session_id_before,
            session_id_after=session_id_after,
            token_window_before=token_before,
            token_window_after=token_after,
        )

        if attempt >= max_retries:
            sys.exit(1)

        attempt += 1
        time.sleep(retry_delay_sec)
PY

