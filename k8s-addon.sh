#!/usr/bin/env bash
# =============================================================================
# Kubernetes Addon Installer — 자주 쓰는 오픈소스 인터랙티브 설치 스크립트
# 포함 애드온: Prometheus·Grafana, Velero+MinIO, Istio,
#             Elasticsearch+Kibana, Fluent Bit, Kyverno, OPA Gatekeeper
# 설치 방식  : Helm 3 (일부 kubectl apply 병용)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 색상 / 출력 헬퍼
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()     { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
step()    { echo -e "\n${BOLD}${BLUE}▶  $*${NC}" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}${BOLD}✔  $*${NC}" | tee -a "$LOG_FILE"; }
tip()     { echo -e "${MAGENTA}${BOLD}💡 TIP:${NC} ${MAGENTA}$*${NC}"; }
fail()    { echo -e "${RED}${BOLD}✘  $*${NC}" | tee -a "$LOG_FILE"; exit 1; }

LOG_FILE="k8s-addon-$(date +%Y%m%d-%H%M%S).log"

box() {
  local text="$1"
  local len=${#text}
  local line; printf -v line '%*s' "$((len + 4))" ''
  echo -e "${CYAN}${BOLD}┌${line// /─}┐${NC}"
  echo -e "${CYAN}${BOLD}│  ${text}  │${NC}"
  echo -e "${CYAN}${BOLD}└${line// /─}┘${NC}"
}

pause() {
  echo -ne "\n${DIM}[ 계속하려면 Enter 키를 누르세요 ]${NC}"
  read -r
}

confirm() {
  echo -ne "${YELLOW}${BOLD}$1 [y/N]: ${NC}"
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

read_val() {
  local prompt="$1" var="$2" default="${3:-}" val
  if [[ -n "$default" ]]; then
    echo -ne "  ${BOLD}${prompt}${NC} ${DIM}[기본값: ${default}]${NC}: "
  else
    echo -ne "  ${BOLD}${prompt}${NC}: "
  fi
  read -r val
  printf -v "$var" '%s' "${val:-$default}"
}

show_result() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━━ 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}$*${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

INSTALLED=()
mark_installed() { INSTALLED+=("$1"); }

# -----------------------------------------------------------------------------
# 사전 조건 확인
# -----------------------------------------------------------------------------
check_deps() {
  step "사전 조건 확인"

  # kubectl
  if ! command -v kubectl &>/dev/null; then
    fail "kubectl 이 설치되어 있지 않습니다."
  fi
  if ! kubectl cluster-info &>/dev/null; then
    fail "Kubernetes 클러스터에 연결할 수 없습니다. kubeconfig 를 확인하세요."
  fi
  success "kubectl — 클러스터 연결 정상"

  # Helm
  if ! command -v helm &>/dev/null; then
    warn "Helm 이 설치되어 있지 않습니다. 자동 설치를 시도합니다..."
    if confirm "Helm 을 자동 설치하시겠습니까?"; then
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      success "Helm 설치 완료: $(helm version --short)"
    else
      fail "Helm 없이는 대부분의 애드온을 설치할 수 없습니다."
    fi
  else
    success "Helm — $(helm version --short)"
  fi
}

# -----------------------------------------------------------------------------
# Helm 저장소 등록
# -----------------------------------------------------------------------------
add_helm_repos() {
  step "Helm 저장소 등록"
  local repos=(
    "prometheus-community https://prometheus-community.github.io/helm-charts"
    "grafana              https://grafana.github.io/helm-charts"
    "vmware-tanzu         https://vmware-tanzu.github.io/helm-charts"
    "bitnami              https://charts.bitnami.com/bitnami"
    "elastic              https://helm.elastic.co"
    "fluent               https://fluent.github.io/helm-charts"
    "kyverno              https://kyverno.github.io/kyverno"
    "gatekeeper           https://open-policy-agent.github.io/gatekeeper/charts"
    "istio                https://istio-release.storage.googleapis.com/charts"
  )
  for entry in "${repos[@]}"; do
    local name url
    name=$(echo "$entry" | awk '{print $1}')
    url=$(echo  "$entry" | awk '{print $2}')
    helm repo add "$name" "$url" --force-update &>/dev/null && \
      log "  저장소 등록: $name" || warn "  저장소 등록 실패 (이미 있거나 네트워크 오류): $name"
  done
  helm repo update &>/dev/null
  success "Helm 저장소 업데이트 완료"
}

# =============================================================================
# 1. Prometheus + Grafana (kube-prometheus-stack)
# =============================================================================
addon_prometheus_grafana() {
  clear
  box "1. Prometheus + Grafana — 모니터링 & 시각화"

  echo -e "
${BOLD}구성 요소 (kube-prometheus-stack):${NC}
  ${DIM}┌──────────────────────────────────────────────────────────┐
  │  Prometheus Operator   — CRD로 Prometheus 인스턴스 관리  │
  │  Prometheus            — 메트릭 수집 및 저장 (TSDB)      │
  │  Alertmanager          — 알림 라우팅 (Slack, Email 등)   │
  │  Grafana               — 대시보드 시각화                  │
  │  node-exporter         — 노드 시스템 메트릭 수집          │
  │  kube-state-metrics    — K8s 오브젝트 상태 메트릭         │
  └──────────────────────────────────────────────────────────┘${NC}

${BOLD}데이터 흐름:${NC}
  ${DIM}K8s 컴포넌트 / 앱 → Prometheus (수집·저장) → Grafana (시각화)
                                          ↓
                                   Alertmanager (알림)${NC}

${BOLD}Prometheus 쿼리 언어:${NC} PromQL
  예) ${CYAN}rate(http_requests_total[5m])${NC}  — 초당 요청 수
      ${CYAN}container_memory_usage_bytes${NC}  — 컨테이너 메모리 사용량
"
  pause
  if ! confirm "kube-prometheus-stack 을 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        PG_NS      "monitoring"
  read_val "Helm Release 이름"     PG_RELEASE "kube-prom"
  read_val "Grafana 관리자 비밀번호" PG_PASS    "admin123!"
  read_val "Prometheus 데이터 보관 기간" PG_RETENTION "15d"
  read_val "Prometheus PVC 크기"   PG_STORAGE "20Gi"

  echo -e "\n  ${BOLD}Grafana Ingress 설정:${NC}"
  local ingress_flag=""
  if confirm "  Grafana Ingress 를 활성화하시겠습니까?"; then
    read_val "  Grafana 도메인 (예: grafana.example.com)" PG_DOMAIN "grafana.local"
    ingress_flag="--set grafana.ingress.enabled=true \
      --set grafana.ingress.hosts[0]=${PG_DOMAIN} \
      --set grafana.ingress.ingressClassName=nginx"
  fi

  kubectl create namespace "$PG_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "kube-prometheus-stack 설치 중 (2~5분 소요)..."
  # shellcheck disable=SC2086
  helm upgrade --install "$PG_RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$PG_NS" \
    --set grafana.adminPassword="$PG_PASS" \
    --set prometheus.prometheusSpec.retention="$PG_RETENTION" \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="$PG_STORAGE" \
    --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage="5Gi" \
    $ingress_flag \
    --wait --timeout 8m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "Prometheus+Grafana (ns: ${PG_NS})"
  success "kube-prometheus-stack 설치 완료!"
  show_result "$(kubectl get pods -n "$PG_NS" 2>&1)"

  echo -e "${BOLD}접속 방법:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/${PG_RELEASE}-grafana 3000:80 -n ${PG_NS}${NC}"
  echo -e "  브라우저: http://localhost:3000  (admin / ${PG_PASS})"
  echo ""
  echo -e "  ${GREEN}kubectl port-forward svc/${PG_RELEASE}-kube-prom-prometheus 9090:9090 -n ${PG_NS}${NC}"
  echo -e "  브라우저: http://localhost:9090"
  tip "kubectl get prometheusrule -n ${PG_NS}   # 알림 규칙 목록"
  pause
}

# =============================================================================
# 2. Velero + MinIO — 백업 & 복구
# =============================================================================
addon_velero_minio() {
  clear
  box "2. Velero + MinIO — 클러스터 백업 & 복구"

  echo -e "
${BOLD}Velero란?${NC}
  Kubernetes 클러스터의 ${CYAN}리소스와 영구 볼륨을 백업/복구${NC}하는 도구입니다.
  재해 복구, 클러스터 마이그레이션, 네임스페이스 복제에 활용합니다.

${BOLD}MinIO란?${NC}
  S3 호환 ${CYAN}오브젝트 스토리지${NC}로, 클러스터 내에서 Velero 의
  백업 저장소(BackupStorageLocation) 역할을 합니다.

${BOLD}아키텍처:${NC}
  ${DIM}kubectl velero backup create my-backup
         ↓
  Velero Server (K8s 리소스 직렬화 + PV 스냅샷)
         ↓
  MinIO (S3 호환 오브젝트 스토리지)
         ↓  [복구 시 역방향]
  kubectl velero restore create --from-backup my-backup${NC}

${BOLD}주요 개념:${NC}
  • ${CYAN}BackupStorageLocation (BSL)${NC} — 백업 파일 저장 위치
  • ${CYAN}VolumeSnapshotLocation (VSL)${NC} — PV 스냅샷 저장 위치
  • ${CYAN}Schedule${NC}                  — 정기 백업 스케줄
"
  pause
  if ! confirm "Velero + MinIO 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"          VEL_NS       "velero"
  read_val "MinIO 관리자 사용자"      MINIO_USER   "minio-admin"
  read_val "MinIO 관리자 비밀번호"    MINIO_PASS   "minio-secret123"
  read_val "Velero 버킷 이름"        MINIO_BUCKET "velero-backups"
  read_val "MinIO PVC 크기"          MINIO_SIZE   "20Gi"

  kubectl create namespace "$VEL_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  # ── MinIO 설치 ────────────────────────────────────────────────────────────
  step "MinIO 설치 중..."
  helm upgrade --install minio bitnami/minio \
    --namespace "$VEL_NS" \
    --set auth.rootUser="$MINIO_USER" \
    --set auth.rootPassword="$MINIO_PASS" \
    --set defaultBuckets="$MINIO_BUCKET" \
    --set persistence.size="$MINIO_SIZE" \
    --set service.type=ClusterIP \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  success "MinIO 설치 완료"

  # MinIO ClusterIP 확인
  local minio_svc="minio.${VEL_NS}.svc.cluster.local"

  # ── Velero credentials 파일 생성 ─────────────────────────────────────────
  local cred_file; cred_file=$(mktemp /tmp/velero-creds-XXXXXX)
  cat > "$cred_file" <<EOF
[default]
aws_access_key_id=${MINIO_USER}
aws_secret_access_key=${MINIO_PASS}
EOF

  # ── Velero 설치 ───────────────────────────────────────────────────────────
  step "Velero 설치 중..."
  helm upgrade --install velero vmware-tanzu/velero \
    --namespace "$VEL_NS" \
    --set-file credentials.secretContents.cloud="$cred_file" \
    --set configuration.backupStorageLocation[0].name=default \
    --set configuration.backupStorageLocation[0].provider=aws \
    --set configuration.backupStorageLocation[0].bucket="$MINIO_BUCKET" \
    --set configuration.backupStorageLocation[0].config.region=minio \
    --set configuration.backupStorageLocation[0].config.s3ForcePathStyle=true \
    --set configuration.backupStorageLocation[0].config.s3Url="http://${minio_svc}:9000" \
    --set configuration.volumeSnapshotLocation[0].name=default \
    --set configuration.volumeSnapshotLocation[0].provider=aws \
    --set configuration.volumeSnapshotLocation[0].config.region=minio \
    --set initContainers[0].name=velero-plugin-for-aws \
    --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
    --set initContainers[0].volumeMounts[0].mountPath=/target \
    --set initContainers[0].volumeMounts[0].name=plugins \
    --set deployNodeAgent=true \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  rm -f "$cred_file"
  mark_installed "Velero+MinIO (ns: ${VEL_NS})"
  success "Velero + MinIO 설치 완료!"
  show_result "$(kubectl get pods -n "$VEL_NS" 2>&1)"

  echo -e "${BOLD}사용 방법:${NC}"
  echo -e "  # 전체 네임스페이스 백업"
  echo -e "  ${GREEN}velero backup create full-backup --wait${NC}"
  echo -e "  # 특정 네임스페이스 백업"
  echo -e "  ${GREEN}velero backup create ns-backup --include-namespaces default --wait${NC}"
  echo -e "  # 백업 목록 확인"
  echo -e "  ${GREEN}velero backup get${NC}"
  echo -e "  # 복구"
  echo -e "  ${GREEN}velero restore create --from-backup full-backup --wait${NC}"
  echo ""
  echo -e "  ${BOLD}MinIO 콘솔 접속:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/minio 9001:9001 -n ${VEL_NS}${NC}"
  echo -e "  브라우저: http://localhost:9001  (${MINIO_USER} / ${MINIO_PASS})"
  tip "velero CLI 설치: https://velero.io/docs/latest/basic-install/#install-the-cli"
  pause
}

# =============================================================================
# 3. Istio — 서비스 메시
# =============================================================================
addon_istio() {
  clear
  box "3. Istio — 서비스 메시 (Service Mesh)"

  echo -e "
${BOLD}Istio란?${NC}
  마이크로서비스 간 통신을 ${CYAN}애플리케이션 코드 변경 없이${NC} 제어하는
  서비스 메시(Service Mesh) 플랫폼입니다.

${BOLD}사이드카 패턴:${NC}
  ${DIM}┌──────────────────── Pod ─────────────────────┐
  │  ┌──────────────┐      ┌───────────────────┐ │
  │  │  App Container│ ←→  │ Envoy Proxy (사이드카)│ │
  │  └──────────────┘      └───────────────────┘ │
  └──────────────────────────────────────────────┘
  모든 인바운드/아웃바운드 트래픽이 Envoy 를 통과${NC}

${BOLD}주요 기능:${NC}
  • ${CYAN}트래픽 관리${NC}  — 카나리 배포, A/B 테스트, 서킷 브레이커
  • ${CYAN}보안${NC}        — mTLS 자동 암호화, 인증/인가 정책
  • ${CYAN}관찰성${NC}      — 분산 추적(Jaeger), 메트릭, 액세스 로그

${BOLD}구성 요소:${NC}
  ${DIM}istiod (컨트롤 플레인): Pilot + Citadel + Galley 통합
  istio-ingressgateway: 클러스터 진입점 (외부 트래픽)
  Envoy 사이드카: 각 Pod에 자동 주입 (데이터 플레인)${NC}
"
  pause
  if ! confirm "Istio 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"       ISTIO_NS      "istio-system"
  read_val "Istio 버전"           ISTIO_VERSION "1.21.0"

  echo -e "\n  ${BOLD}설치 프로파일 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} default   — istiod + ingress gateway (권장)"
  echo -e "    ${CYAN}2)${NC} minimal   — istiod 만 설치 (경량)"
  echo -e "    ${CYAN}3)${NC} demo      — 모든 기능 포함 (학습용, 리소스 많음)"
  echo -ne "    선택 [1-3]: "
  read -r istio_profile_choice
  case "$istio_profile_choice" in
    2) ISTIO_PROFILE="minimal" ;;
    3) ISTIO_PROFILE="demo" ;;
    *) ISTIO_PROFILE="default" ;;
  esac

  kubectl create namespace "$ISTIO_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  # ── Helm 으로 Istio 설치 ──────────────────────────────────────────────────
  step "Istio base (CRD) 설치 중..."
  helm upgrade --install istio-base istio/base \
    --namespace "$ISTIO_NS" \
    --set defaultRevision=default \
    --version "$ISTIO_VERSION" \
    --wait 2>&1 | tee -a "$LOG_FILE"

  step "istiod (컨트롤 플레인) 설치 중..."
  helm upgrade --install istiod istio/istiod \
    --namespace "$ISTIO_NS" \
    --version "$ISTIO_VERSION" \
    --wait 2>&1 | tee -a "$LOG_FILE"

  if [[ "$ISTIO_PROFILE" != "minimal" ]]; then
    step "Istio Ingress Gateway 설치 중..."
    kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    helm upgrade --install istio-ingressgateway istio/gateway \
      --namespace istio-ingress \
      --version "$ISTIO_VERSION" \
      --wait 2>&1 | tee -a "$LOG_FILE"
  fi

  # Kiali (서비스 메시 시각화) 선택 설치
  if confirm "  Kiali (Istio 시각화 대시보드) 도 함께 설치하시겠습니까?"; then
    step "Kiali 설치 중..."
    helm upgrade --install kiali-operator kiali/kiali-operator \
      --namespace "$ISTIO_NS" \
      --set cr.create=true \
      --set cr.namespace="$ISTIO_NS" 2>&1 | tee -a "$LOG_FILE" || \
      warn "Kiali 설치 실패. 수동으로 설치하세요: https://kiali.io/docs/installation/helm"
  fi

  mark_installed "Istio (ns: ${ISTIO_NS}, profile: ${ISTIO_PROFILE})"
  success "Istio 설치 완료!"
  show_result "$(kubectl get pods -n "$ISTIO_NS" 2>&1)"

  echo -e "${BOLD}사이드카 자동 주입 활성화:${NC}"
  echo -e "  ${GREEN}kubectl label namespace <your-ns> istio-injection=enabled${NC}"
  echo ""
  echo -e "${BOLD}Kiali 대시보드 접속:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/kiali 20001:20001 -n ${ISTIO_NS}${NC}"
  echo -e "  브라우저: http://localhost:20001"
  tip "istioctl analyze   # 설정 유효성 검사 (istioctl CLI 필요)"
  pause
}

# =============================================================================
# 4. Elasticsearch + Kibana (ECK Operator)
# =============================================================================
addon_elastic() {
  clear
  box "4. Elasticsearch + Kibana — 로그 저장 & 검색 시각화"

  echo -e "
${BOLD}ECK (Elastic Cloud on Kubernetes)란?${NC}
  Elastic 공식 Kubernetes Operator 로, Elasticsearch 와 Kibana 를
  ${CYAN}선언적으로 배포·운영${NC}합니다.

${BOLD}ELK/EFK 스택 전체 구조:${NC}
  ${DIM}애플리케이션 로그
         ↓
  Fluent Bit (수집·파싱)
         ↓
  Elasticsearch (저장·색인·검색)  ←─ Kibana (시각화·검색 UI)
         ↓
  Kibana Dashboards / Alerts${NC}

${BOLD}Elasticsearch 주요 개념:${NC}
  • ${CYAN}Index${NC}    — 데이터 저장 단위 (DB 의 테이블과 유사)
  • ${CYAN}Shard${NC}    — Index 를 분산 저장하는 조각
  • ${CYAN}Replica${NC}  — Shard 복제본 (고가용성)
  • ${CYAN}ILM${NC}      — Index Lifecycle Management (자동 롤오버/삭제)
"
  pause
  if ! confirm "Elasticsearch + Kibana (ECK) 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        ES_NS       "elastic-system"
  read_val "Elasticsearch 클러스터 이름" ES_NAME "elasticsearch"
  read_val "Elasticsearch 노드 수" ES_NODES    "1"
  read_val "Elasticsearch PVC 크기 (노드당)" ES_STORAGE "30Gi"
  read_val "Kibana 이름"           KB_NAME     "kibana"

  kubectl create namespace "$ES_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  # ── ECK Operator 설치 ─────────────────────────────────────────────────────
  step "ECK Operator (CRD + 컨트롤러) 설치 중..."
  helm upgrade --install elastic-operator elastic/eck-operator \
    --namespace elastic-system \
    --create-namespace \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"
  success "ECK Operator 설치 완료"

  # ── Elasticsearch CR 배포 ──────────────────────────────────────────────────
  step "Elasticsearch 클러스터 배포 중..."
  kubectl apply -f - <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${ES_NAME}
  namespace: ${ES_NS}
spec:
  version: 8.13.0
  nodeSets:
  - name: default
    count: ${ES_NODES}
    config:
      node.store.allow_mmap: false
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 1Gi
              cpu: 500m
            limits:
              memory: 2Gi
              cpu: "1"
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: ${ES_STORAGE}
EOF

  # ── Kibana CR 배포 ────────────────────────────────────────────────────────
  step "Kibana 배포 중..."
  kubectl apply -f - <<EOF
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: ${KB_NAME}
  namespace: ${ES_NS}
spec:
  version: 8.13.0
  count: 1
  elasticsearchRef:
    name: ${ES_NAME}
  podTemplate:
    spec:
      containers:
      - name: kibana
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: 500m
EOF

  mark_installed "Elasticsearch+Kibana (ns: ${ES_NS})"
  success "Elasticsearch + Kibana 배포 완료! (Pod 기동까지 3~5분 소요)"
  show_result "$(kubectl get elasticsearch,kibana -n "$ES_NS" 2>&1)"

  echo -e "${BOLD}초기 비밀번호 확인:${NC}"
  echo -e "  ${GREEN}kubectl get secret ${ES_NAME}-es-elastic-user -n ${ES_NS} -o go-template='{{.data.elastic | base64decode}}'${NC}"
  echo ""
  echo -e "${BOLD}Kibana 접속:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/${KB_NAME}-kb-http 5601:5601 -n ${ES_NS}${NC}"
  echo -e "  브라우저: https://localhost:5601  (elastic / <위 비밀번호>)"
  tip "kubectl get elasticsearch -n ${ES_NS}   # 클러스터 health 상태 확인"
  pause
}

# =============================================================================
# 5. Fluent Bit — 경량 로그 수집
# =============================================================================
addon_fluentbit() {
  clear
  box "5. Fluent Bit — 경량 로그 수집 & 전달"

  echo -e "
${BOLD}Fluent Bit이란?${NC}
  노드의 컨테이너 로그를 수집하여 ${CYAN}Elasticsearch, Kafka, S3${NC} 등
  다양한 백엔드로 전달하는 ${CYAN}초경량(~650KB) 로그 프로세서${NC}입니다.

${BOLD}Fluentd vs Fluent Bit:${NC}
  ${DIM}┌───────────────┬──────────────────────────────────────────────┐
  │ Fluentd       │ 풍부한 플러그인, 무거움 (~40MB)                │
  │ Fluent Bit    │ 경량, 빠름, Edge/IoT 환경에 적합 (~650KB)     │
  └───────────────┴──────────────────────────────────────────────┘${NC}

${BOLD}파이프라인 구조:${NC}
  ${DIM}[Input]           [Filter]             [Output]
  tail (파일 읽기) → parser (JSON 파싱) → Elasticsearch
  systemd          → modify (필드 추가) → Kafka
  tcp              → grep (필터링)      → S3 / CloudWatch${NC}

${BOLD}DaemonSet 으로 배포:${NC}
  모든 노드에 하나씩 배포되어 해당 노드의 /var/log/containers/ 를 감시합니다.
"
  pause
  if ! confirm "Fluent Bit 을 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        FB_NS      "logging"
  read_val "Helm Release 이름"     FB_RELEASE "fluent-bit"

  echo -e "\n  ${BOLD}로그 출력 대상 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Elasticsearch (권장)"
  echo -e "    ${CYAN}2)${NC} stdout (디버그용)"
  echo -e "    ${CYAN}3)${NC} 커스텀 설정"
  echo -ne "    선택 [1-3]: "
  read -r fb_output_choice

  local fb_output_values=""
  case "$fb_output_choice" in
    1)
      read_val "  Elasticsearch 호스트" ES_HOST "elasticsearch-es-http.elastic-system.svc.cluster.local"
      read_val "  Elasticsearch 포트"   ES_PORT "9200"
      read_val "  Elasticsearch 인덱스" ES_INDEX "kubernetes-logs"
      read_val "  Elasticsearch 사용자" ES_USER "elastic"
      read_val "  Elasticsearch 비밀번호" ES_PASS ""
      fb_output_values="--set config.outputs=\"[OUTPUT]\\n    Name es\\n    Match *\\n    Host ${ES_HOST}\\n    Port ${ES_PORT}\\n    Index ${ES_INDEX}\\n    Suppress_Type_Name On\\n    HTTP_User ${ES_USER}\\n    HTTP_Passwd ${ES_PASS}\\n    tls On\\n    tls.verify Off\""
      ;;
    *) fb_output_values="" ;;
  esac

  kubectl create namespace "$FB_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Fluent Bit 설치 중..."
  # shellcheck disable=SC2086
  helm upgrade --install "$FB_RELEASE" fluent/fluent-bit \
    --namespace "$FB_NS" \
    --set resources.requests.memory=64Mi \
    --set resources.requests.cpu=50m \
    --set resources.limits.memory=128Mi \
    --set resources.limits.cpu=200m \
    --set tolerations[0].key=node-role.kubernetes.io/control-plane \
    --set tolerations[0].operator=Exists \
    --set tolerations[0].effect=NoSchedule \
    $fb_output_values \
    --wait --timeout 3m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "Fluent Bit (ns: ${FB_NS})"
  success "Fluent Bit 설치 완료!"
  show_result "$(kubectl get daemonset -n "$FB_NS" 2>&1)"
  tip "kubectl logs -l app.kubernetes.io/name=fluent-bit -n ${FB_NS} --tail=20   # 수집 로그 확인"
  pause
}

# =============================================================================
# 6. Kyverno — Kubernetes 정책 엔진
# =============================================================================
addon_kyverno() {
  clear
  box "6. Kyverno — Kubernetes-Native 정책 엔진"

  echo -e "
${BOLD}Kyverno란?${NC}
  Kubernetes ${CYAN}CRD 로 정의된 정책${NC}으로 리소스를 검증(Validate),
  변조(Mutate), 생성(Generate)하는 정책 엔진입니다.

${BOLD}OPA Gatekeeper 와의 차이:${NC}
  ${DIM}┌────────────────┬─────────────────────────────────────────────┐
  │ Kyverno        │ YAML 로 정책 작성, K8s 네이티브, 쉬운 학습   │
  │ OPA Gatekeeper │ Rego 언어로 작성, 강력한 표현력, 복잡한 정책  │
  └────────────────┴─────────────────────────────────────────────────┘${NC}

${BOLD}동작 방식 (Admission Webhook):${NC}
  ${DIM}kubectl apply → kube-apiserver → Kyverno Webhook
                                      ├── Validate: 정책 위반 시 거부
                                      ├── Mutate:  자동 필드 수정·추가
                                      └── Generate: 관련 리소스 자동 생성${NC}

${BOLD}정책 예시:${NC}
  • 모든 Pod 에 ${CYAN}리소스 limits 필수 지정${NC}
  • ${CYAN}latest 태그 이미지 사용 금지${NC}
  • 모든 Deployment 에 ${CYAN}특정 레이블 강제${NC}
  • Namespace 생성 시 ${CYAN}NetworkPolicy 자동 생성${NC}
"
  pause
  if ! confirm "Kyverno 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"    KY_NS      "kyverno"
  read_val "Helm Release 이름" KY_RELEASE "kyverno"
  read_val "Kyverno 복제본 수" KY_REPLICAS "1"

  kubectl create namespace "$KY_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Kyverno 설치 중..."
  helm upgrade --install "$KY_RELEASE" kyverno/kyverno \
    --namespace "$KY_NS" \
    --set replicaCount="$KY_REPLICAS" \
    --set resources.requests.memory=128Mi \
    --set resources.requests.cpu=100m \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  success "Kyverno 설치 완료!"

  # 샘플 정책 선택 설치
  if confirm "  샘플 정책을 설치하시겠습니까? (학습 권장)"; then
    step "샘플 정책 적용 중..."

    # 정책 1: latest 태그 금지
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  annotations:
    policies.kyverno.io/title: 'latest 이미지 태그 금지'
    policies.kyverno.io/description: 'latest 태그 이미지 사용을 금지합니다. 명시적 버전 태그를 사용하세요.'
spec:
  validationFailureAction: Audit   # Enforce 로 변경 시 실제 차단
  rules:
  - name: require-image-tag
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "이미지 태그를 명시해야 합니다 (latest 태그 금지)"
      pattern:
        spec:
          containers:
          - image: "!*:latest"
EOF

    # 정책 2: 리소스 limits 강제
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
  annotations:
    policies.kyverno.io/title: 'CPU/Memory Limits 필수'
    policies.kyverno.io/description: '모든 컨테이너에 resources.limits 설정을 강제합니다.'
spec:
  validationFailureAction: Audit
  rules:
  - name: check-resource-limits
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "모든 컨테이너에 resources.limits.memory 와 cpu 를 설정해야 합니다."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
EOF

    success "샘플 정책 2개 설치 완료 (Audit 모드 — 위반 감지만 하고 차단하지 않음)"
    tip "spec.validationFailureAction: Enforce 로 변경하면 실제 차단됩니다"
  fi

  mark_installed "Kyverno (ns: ${KY_NS})"
  show_result "$(kubectl get pods -n "$KY_NS" 2>&1)"
  tip "kubectl get clusterpolicy   # 적용된 정책 목록"
  tip "kubectl get policyreport -A # 정책 검사 결과 리포트"
  pause
}

# =============================================================================
# 7. OPA Gatekeeper — 정책 기반 접근 제어
# =============================================================================
addon_opa_gatekeeper() {
  clear
  box "7. OPA Gatekeeper — 정책 기반 접근 제어 (Rego)"

  echo -e "
${BOLD}OPA Gatekeeper란?${NC}
  ${CYAN}Rego 언어${NC}로 작성된 정책으로 Kubernetes 리소스를 검증하는
  Admission Controller 입니다. OPA(Open Policy Agent) 의 K8s 통합판입니다.

${BOLD}핵심 개념:${NC}
  ${DIM}┌──────────────────────────────────────────────────────────┐
  │  ConstraintTemplate  — 정책 템플릿 (Rego 코드 포함)      │
  │  Constraint          — 템플릿의 인스턴스 (실제 적용 대상)  │
  └──────────────────────────────────────────────────────────┘${NC}

${BOLD}동작 흐름:${NC}
  ${DIM}ConstraintTemplate (Rego 정책 정의)
         ↓ 적용
  Constraint (어느 리소스에 적용할지)
         ↓
  kubectl apply 시 Gatekeeper 가 검증 → 위반 시 거부${NC}

${BOLD}Rego 정책 예시:${NC}
  ${DIM}package k8srequiredlabels
  violation[{\"msg\": msg}] {
    provided := {label | input.review.object.metadata.labels[label]}
    required := {label | label := input.parameters.labels[_]}
    missing := required - provided
    msg := sprintf(\"레이블 누락: %v\", [missing])
  }${NC}
"
  pause
  if ! confirm "OPA Gatekeeper 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"    GK_NS      "gatekeeper-system"
  read_val "Helm Release 이름" GK_RELEASE "gatekeeper"
  read_val "Audit 간격 (초)"   GK_AUDIT   "60"

  kubectl create namespace "$GK_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "OPA Gatekeeper 설치 중..."
  helm upgrade --install "$GK_RELEASE" gatekeeper/gatekeeper \
    --namespace "$GK_NS" \
    --set auditInterval="$GK_AUDIT" \
    --set resources.requests.memory=256Mi \
    --set resources.requests.cpu=100m \
    --set resources.limits.memory=512Mi \
    --set resources.limits.cpu=500m \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  success "OPA Gatekeeper 설치 완료!"

  # 샘플 정책 설치
  if confirm "  샘플 ConstraintTemplate + Constraint 를 설치하시겠습니까?"; then
    step "필수 레이블 정책 적용 중..."

    kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8srequiredlabels
      violation[{"msg": msg, "details": {"missing_labels": missing}}] {
        provided := {label | input.review.object.metadata.labels[label]}
        required := {label | label := input.parameters.labels[_]}
        missing := required - provided
        count(missing) > 0
        msg := sprintf("필수 레이블 누락: %v", [missing])
      }
EOF

    kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: ns-must-have-env-label
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Namespace"]
    excludedNamespaces:
    - kube-system
    - kube-public
    - gatekeeper-system
  parameters:
    labels: ["env"]   # Namespace 생성 시 env 레이블 필수
EOF

    success "샘플 정책 설치 완료!"
    echo -e "  테스트: ${GREEN}kubectl create ns test-no-label${NC} → 거부됨"
    echo -e "  테스트: ${GREEN}kubectl create ns test-with-label --dry-run=server -o yaml${NC}"
    echo -e "  성공:   ${GREEN}kubectl create ns test-ok -l env=dev${NC}"
  fi

  mark_installed "OPA Gatekeeper (ns: ${GK_NS})"
  show_result "$(kubectl get pods -n "$GK_NS" 2>&1)"
  tip "kubectl get constraints -A                # 적용된 정책 목록"
  tip "kubectl get constrainttemplate            # 정책 템플릿 목록"
  pause
}

# =============================================================================
# 번들: Observability Stack
# =============================================================================
bundle_observability() {
  clear
  box "번들: Observability Stack (모니터링 + 로깅)"
  echo -e "
  ${BOLD}포함 컴포넌트:${NC}
    ${CYAN}1)${NC} kube-prometheus-stack  — Prometheus + Grafana + AlertManager
    ${CYAN}2)${NC} Fluent Bit             — 로그 수집 (DaemonSet)
    ${CYAN}3)${NC} Elasticsearch + Kibana — 로그 저장 + 시각화

  ${DIM}모든 컴포넌트를 순서대로 설치합니다.${NC}
"
  if ! confirm "Observability Stack 을 설치하시겠습니까?"; then return; fi
  addon_prometheus_grafana
  addon_elastic
  addon_fluentbit
}

# =============================================================================
# 번들: Policy & Governance Stack
# =============================================================================
bundle_policy() {
  clear
  box "번들: Policy & Governance Stack"
  echo -e "
  ${BOLD}포함 컴포넌트:${NC}
    ${CYAN}1)${NC} Kyverno        — K8s-Native 정책 엔진 (YAML 기반)
    ${CYAN}2)${NC} OPA Gatekeeper — Rego 기반 강력한 정책 엔진
"
  if ! confirm "Policy Stack 을 설치하시겠습니까?"; then return; fi
  addon_kyverno
  addon_opa_gatekeeper
}

# =============================================================================
# 설치 현황 및 정리
# =============================================================================
show_status() {
  clear
  box "클러스터 애드온 현황"
  echo ""
  echo -e "${BOLD}이번 세션 설치 목록:${NC}"
  if [[ ${#INSTALLED[@]} -eq 0 ]]; then
    echo "  아직 설치된 항목이 없습니다."
  else
    for item in "${INSTALLED[@]}"; do
      echo -e "  ${GREEN}✔${NC}  $item"
    done
  fi
  echo ""
  echo -e "${BOLD}네임스페이스별 Pod 상태:${NC}"
  for ns in monitoring logging elastic-system velero istio-system kyverno gatekeeper-system; do
    local pods
    pods=$(kubectl get pods -n "$ns" 2>/dev/null | grep -v "^NAME" | wc -l | tr -d ' ')
    if (( pods > 0 )); then
      echo -e "  ${CYAN}${ns}${NC}: ${pods} pods"
    fi
  done
  echo ""
  pause
}

# =============================================================================
# 메인 메뉴
# =============================================================================
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Kubernetes Addon Installer                        ║"
  echo "║     자주 쓰는 오픈소스를 인터랙티브하게 설치합니다           ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

main_menu() {
  while true; do
    print_banner
    echo -e "  ${BOLD}── 개별 애드온 설치 ──────────────────────────────────────${NC}"
    echo -e "  ${CYAN} 1)${NC} Prometheus + Grafana   — 메트릭 수집 & 시각화 (kube-prometheus-stack)"
    echo -e "  ${CYAN} 2)${NC} Velero + MinIO         — 클러스터 백업 & 복구"
    echo -e "  ${CYAN} 3)${NC} Istio                  — 서비스 메시 (트래픽 관리, mTLS)"
    echo -e "  ${CYAN} 4)${NC} Elasticsearch + Kibana — 로그 저장 & 검색 시각화 (ECK)"
    echo -e "  ${CYAN} 5)${NC} Fluent Bit             — 경량 로그 수집 DaemonSet"
    echo -e "  ${CYAN} 6)${NC} Kyverno               — K8s-Native 정책 엔진"
    echo -e "  ${CYAN} 7)${NC} OPA Gatekeeper        — Rego 기반 정책 접근 제어"
    echo ""
    echo -e "  ${BOLD}── 번들 설치 (여러 컴포넌트 한 번에) ──────────────────────${NC}"
    echo -e "  ${YELLOW} 8)${NC} Observability Stack   — Prometheus + Grafana + ES + Fluent Bit"
    echo -e "  ${YELLOW} 9)${NC} Policy Stack          — Kyverno + OPA Gatekeeper"
    echo ""
    echo -e "  ${BOLD}── 기타 ──────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW} s)${NC} 설치 현황 확인"
    echo -e "  ${RED}  q)${NC} 종료"
    echo ""
    if [[ ${#INSTALLED[@]} -gt 0 ]]; then
      echo -e "  ${DIM}설치 완료: ${INSTALLED[*]}${NC}"
      echo ""
    fi
    echo -ne "  ${BOLD}메뉴 선택:${NC} "
    read -r choice

    case "$choice" in
      1) addon_prometheus_grafana ;;
      2) addon_velero_minio ;;
      3) addon_istio ;;
      4) addon_elastic ;;
      5) addon_fluentbit ;;
      6) addon_kyverno ;;
      7) addon_opa_gatekeeper ;;
      8) bundle_observability ;;
      9) bundle_policy ;;
      s|S) show_status ;;
      q|Q)
        echo ""
        show_status
        echo -e "${GREEN}${BOLD}Addon 설치를 마칩니다.${NC}"
        echo -e "로그 파일: ${LOG_FILE}"
        echo ""
        exit 0
        ;;
      *)
        warn "잘못된 선택입니다. 다시 입력하세요."
        sleep 1
        ;;
    esac
  done
}

# =============================================================================
# 실행
# =============================================================================
check_deps
add_helm_repos
main_menu
