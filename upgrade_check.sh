#!/usr/bin/env bash
# ============================================================
# Hermes 自动升级检查（cron no_agent 模式）
# stdout 非空 => 作为消息推送；空 => 静默
# 流程: fetch 上游 -> 算差距 -> 有差距则 pull --rebase（保留本地提交）
# 安全: flock 防并发; rebase 冲突自动 abort 恢复, 绝不 reset --hard
# ============================================================
set -u

LOCK_FILE=/tmp/hermes_upgrade_check.lock
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "⚠️ 升级检查已在运行，跳过本次"; exit 0; }

AGENT_REPO=/home/yuchen_wang/Hermes-Agent
SSH_URL_A=git@github.com:NousResearch/hermes-agent.git
SSH_URL_W=git@github.com:nesquena/hermes-webui.git
GIT_TIMEOUT=60  # git 命令超时（秒），国内网络保护

# ---------- 工具函数 ----------
run_git() { # 带超时执行 git
  timeout $GIT_TIMEOUT git "$@" 2>&1
}

fetch_repo() { # $1=仓库路径 $2=分支; 静默执行, 仅返回退出码
  local dir="$1" branch="$2"
  ( cd "$dir" && timeout $GIT_TIMEOUT git fetch origin "$branch" >/dev/null 2>&1 )
}

rebase_abort_if_stuck() { # $1=仓库路径; rebase 中途失败时恢复
  local dir="$1"
  if [ -d "$dir/.git/rebase-merge" ] || [ -d "$dir/.git/rebase-apply" ]; then
    ( cd "$dir" && run_git rebase --abort >/dev/null 2>&1 )
    echo "⚠️ $dir rebase 冲突已自动回滚，请手动处理"
  fi
}

# ---------- 主流程 ----------
OUT=""
FETCH_FAIL=0

# 1. 拉取上游（失败不致命，继续算差距）
fetch_repo "$AGENT_REPO" main   || { echo "❌ HermesAgent fetch 失败（SSH 不通？）"; FETCH_FAIL=1; }
fetch_repo "$AGENT_REPO/hermes-webui" master || { echo "❌ hermes-webui fetch 失败"; FETCH_FAIL=1; }
if [ $FETCH_FAIL -eq 1 ]; then
  echo ""
  echo "可检查: ssh -T git@github.com"
  exit 0
fi

# 2. 计算差距
BEHIND_A=$(cd "$AGENT_REPO" && run_git rev-list --count HEAD..origin/main)
AHEAD_A=$(cd "$AGENT_REPO" && run_git rev-list --count origin/main..HEAD)
BEHIND_W=$(cd "$AGENT_REPO/hermes-webui" && run_git rev-list --count HEAD..origin/master)
AHEAD_W=$(cd "$AGENT_REPO/hermes-webui" && run_git rev-list --count origin/master..HEAD)

# 3. 无差距 => 静默（空 stdout 不推送）
if [ "${BEHIND_A:-0}" = "0" ] && [ "${BEHIND_W:-0}" = "0" ]; then
  exit 0
fi

# 4. 有差距 => 执行升级
OUT="🔄 Hermes 升级检查发现更新
| 项目 | 差距 |
|------|------|
| HermesAgent | behind ${BEHIND_A} / ahead ${AHEAD_A} |
| hermes-webui | behind ${BEHIND_W} / ahead ${AHEAD_W} |"

UPGRADE_OK=1
if [ "${BEHIND_A:-0}" != "0" ]; then
  OUT="$OUT

📦 升级 HermesAgent:"
  OUT="$OUT
$(cd "$AGENT_REPO" && run_git log HEAD..origin/main --oneline | head -8)"
  if ( cd "$AGENT_REPO" && run_git pull --rebase origin main >/dev/null 2>&1 ); then
    OUT="$OUT
✅ Agent 升级成功 → $(cd "$AGENT_REPO" && run_git rev-parse --short HEAD)"
  else
    rebase_abort_if_stuck "$AGENT_REPO"
    OUT="$OUT
❌ Agent 升级失败（已回滚，保持原状）"
    UPGRADE_OK=0
  fi
fi

if [ "${BEHIND_W:-0}" != "0" ]; then
  OUT="$OUT

📦 升级 hermes-webui:"
  OUT="$OUT
$(cd "$AGENT_REPO/hermes-webui" && run_git log HEAD..origin/master --oneline | head -5)"
  if ( cd "$AGENT_REPO/hermes-webui" && run_git pull --rebase origin master >/dev/null 2>&1 ); then
    OUT="$OUT
✅ WebUI 升级成功 → $(cd "$AGENT_REPO/hermes-webui" && run_git rev-parse --short HEAD)"
    # 更新父仓库子模块引用
    ( cd "$AGENT_REPO" && run_git add hermes-webui && run_git commit -m "chore: update hermes-webui submodule" >/dev/null 2>&1 )
  else
    rebase_abort_if_stuck "$AGENT_REPO/hermes-webui"
    OUT="$OUT
❌ WebUI 升级失败（已回滚，保持原状）"
    UPGRADE_OK=0
  fi
fi

# 5. 最终状态
OUT="$OUT

📌 当前: Agent $(cd "$AGENT_REPO" && run_git rev-parse --short HEAD) / WebUI $(cd "$AGENT_REPO/hermes-webui" && run_git rev-parse --short HEAD)"

if [ $UPGRADE_OK -eq 1 ]; then
  OUT="$OUT

⚠️ 需重启 Gateway/WebUI 才能生效新代码"
fi

echo "$OUT"
exit 0
