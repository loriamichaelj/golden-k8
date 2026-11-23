#!/usr/bin/env bash
# Observability checks and access for the environment in build/.
#
#   scripts/observability.sh check   Grafana served via the Gateway with a working
#                                    admin login, every Prometheus target up, and
#                                    monitoring memory under the profile budget
#   scripts/observability.sh login   print the Grafana URL and admin credentials
#
# Every call is pinned to the cluster in build/contract.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
action="${1:?usage: observability.sh check|login}"

fail() { printf 'observability: %s\n' "$*" >&2; exit 1; }
info() { printf 'observability: %s\n' "$*" >&2; }

[ -f "$BUILD/contract.json" ] || fail "no build/contract.json (run: make infra-up ENV=...)"
[ -f "$BUILD/config.json" ] || fail "no build/config.json (run: make config ENV=...)"

kc() {
  kubectl --kubeconfig "$(yq -r '.kubeconfig_path' "$BUILD/contract.json")" \
    --context "$(yq -r '.kube_context' "$BUILD/contract.json")" "$@"
}

profile="$(yq -r '.spec.observability.profile' "$BUILD/config.json")"
exposed="$(yq -r '.spec.observability.expose.enabled' "$BUILD/config.json")"
host="$(yq -r '.spec.observability.expose.host' "$BUILD/config.json")"
provider="$(yq -r '.provider' "$BUILD/contract.json")"
# On kind the Gateway listens on 127.0.0.1:<hostHttpPort>.
port="$(yq -r '.spec.cluster.providerOverrides.hostHttpPort // 80' "$BUILD/config.json")"
url="http://$host$([ "$port" = 80 ] || printf ':%s' "$port")"

admin_secret() { kc -n monitoring get secret grafana-admin -o "jsonpath={.data.$1}" | base64 -d; }

# Grafana through the shared Gateway. Credentials go through curl's config on
# stdin, so they never appear in the process list or in logs.
grafana() { # <path> [auth] → HTTP status
  local path="$1" auth="${2:-}"
  {
    [ -z "$auth" ] || printf 'user = "%s:%s"\n' "$(admin_secret admin-user)" "$(admin_secret admin-password)"
  } | curl -s -o /dev/null -w '%{http_code}' -K - --max-time 5 \
        -H "Host: $host" "http://127.0.0.1:$port$path" || true
}

# PromQL through the API server proxy (no port-forward, nothing exposed).
promql() { # <query> → JSON result vector
  kc get --raw "/api/v1/namespaces/monitoring/services/http:prometheus-operated:9090/proxy/api/v1/query?query=$(Q="$1" yq -n 'strenv(Q) | @uri')" \
    | yq -p json -o json '.data.result'
}

retry() { # <seconds> <description> <command...>: retry every 5s until it succeeds
  local deadline=$((SECONDS + $1)) what="$2"; shift 2
  until "$@"; do
    [ "$SECONDS" -lt "$deadline" ] || fail "timed out: $what"
    sleep 5
  done
}

case "$action" in
  login)
    if [ "$exposed" = true ]; then
      printf 'url:      %s\n' "$url"
    else
      printf 'url:      http://127.0.0.1:3000 (run: kubectl -n monitoring port-forward svc/grafana 3000:80)\n'
    fi
    printf 'user:     %s\npassword: %s\n' "$(admin_secret admin-user)" "$(admin_secret admin-password)"
    ;;

  check)
    case "$provider" in
      local | existing) ;;
      *) fail "check runs against clusters on this machine only (provider: $provider)" ;;
    esac

    if [ "$exposed" = true ]; then
      grafana_healthy() { [ "$(grafana /api/health)" = 200 ]; }
      retry 120 "Grafana /api/health via the Gateway ($host)" grafana_healthy
      [ "$(grafana /api/user)" = 401 ] || fail "Grafana answers /api/user without credentials"
      [ "$(grafana /api/user auth)" = 200 ] || fail "Grafana admin login failed"
      info "ok  Grafana via the Gateway at $url, admin login works"
    fi

    targets_up() {
      local total down
      total="$(promql 'count(up)' | yq '.[0].value[1] // 0')"
      down="$(promql 'up == 0' | yq -r '[.[].metric.job] | unique | join(", ")')"
      [ "$total" -gt 0 ] && [ -z "$down" ] || { info "waiting for targets (up: $total, down: ${down:-none})"; return 1; }
      info "ok  Prometheus: all $total targets up"
    }
    retry 180 "every Prometheus target up" targets_up

    case "$profile" in
      lite) budget_mb=1500 ;;
      *) budget_mb=4000 ;;
    esac
    mem_mb() { # <namespace> → working-set memory in MB
      promql "sum(container_memory_working_set_bytes{metrics_path=\"/metrics/resource\",namespace=\"$1\",container!=\"\"})" \
        | yq -r '.[0].value[1] // "0"' | awk '{ printf "%d\n", $1 / 1000000 }'
    }
    have_memory() { [ "$(mem_mb monitoring)" -gt 0 ]; }
    retry 120 "container memory metrics for namespace monitoring" have_memory
    used="$(mem_mb monitoring)"
    info "    memory: monitoring ${used} MB, envoy-gateway-system $(mem_mb envoy-gateway-system) MB (working set)"
    [ "$used" -lt "$budget_mb" ] || fail "monitoring uses ${used} MB, over the $profile budget of ${budget_mb} MB"
    info "ok  observability memory ${used} MB < ${budget_mb} MB ($profile)"

    mkdir -p "$BUILD/summary"
    {
      printf '### Observability (%s)\n\n| Check | Result |\n|---|---|\n' "$profile"
      [ "$exposed" != true ] || printf '| Grafana through the Gateway | ✅ %s, admin login works |\n' "$url"
      printf '| Prometheus targets | ✅ all %s up |\n' "$(promql 'count(up)' | yq '.[0].value[1]')"
      printf '| Memory, monitoring namespace | ✅ %s MB (budget %s MB) |\n' "$used" "$budget_mb"
      printf '| Memory, envoy-gateway-system | %s MB |\n' "$(mem_mb envoy-gateway-system)"
    } > "$BUILD/summary/observability.md"
    ;;

  *) fail "unknown action: $action (check|login)" ;;
esac
