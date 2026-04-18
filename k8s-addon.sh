#!/usr/bin/env bash
# =============================================================================
# Kubernetes Addon Installer — 자주 쓰는 오픈소스 인터랙티브 설치 스크립트
# 포함 애드온: Prometheus·Grafana, Velero+MinIO, Istio,
#             Elasticsearch+Kibana, Fluent Bit, Kyverno, OPA Gatekeeper,
#             NGINX Ingress, Contour, Loki, cert-manager,
#             ArgoCD, FluxCD, Jenkins
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
    "ingress-nginx        https://kubernetes.github.io/ingress-nginx"
    "projectcontour       https://projectcontour.github.io/contour"
    "jetstack             https://charts.jetstack.io"
    "argo                 https://argoproj.github.io/argo-helm"
    "fluxcd-community     https://fluxcd-community.github.io/helm-charts"
    "jenkins              https://charts.jenkins.io"
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
# 8. NGINX Ingress Controller
# =============================================================================
addon_nginx_ingress() {
  clear
  box "8. NGINX Ingress Controller — L7 HTTP(S) 라우팅"

  echo -e "
${BOLD}NGINX Ingress Controller란?${NC}
  Kubernetes ${CYAN}Ingress 리소스${NC}를 읽어 NGINX 리버스 프록시로 변환하는
  가장 널리 쓰이는 Ingress Controller 입니다.

${BOLD}동작 방식:${NC}
  ${DIM}Client → LoadBalancer/NodePort → NGINX Pod
            ↓  (Ingress 규칙에 따라)
         svc-a (host: a.example.com)
         svc-b (host: b.example.com, path: /api)${NC}

${BOLD}주요 기능:${NC}
  • ${CYAN}Host / Path 기반 라우팅${NC}
  • ${CYAN}TLS 종단 (cert-manager 연동)${NC}
  • ${CYAN}Rate Limiting, Canary, CORS${NC}
  • ${CYAN}Prometheus 메트릭 내장${NC}
"
  pause
  if ! confirm "NGINX Ingress Controller 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        NI_NS      "ingress-nginx"
  read_val "Helm Release 이름"     NI_RELEASE "ingress-nginx"

  echo -e "\n  ${BOLD}Service 타입 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} LoadBalancer (클라우드/MetalLB 환경, 권장)"
  echo -e "    ${CYAN}2)${NC} NodePort     (베어메탈/학습용)"
  echo -ne "    선택 [1-2]: "
  read -r ni_svc_choice
  local ni_svc_type="LoadBalancer"
  local ni_extra=""
  if [[ "$ni_svc_choice" == "2" ]]; then
    ni_svc_type="NodePort"
    read_val "  HTTP NodePort"  NI_HTTP_NP  "30080"
    read_val "  HTTPS NodePort" NI_HTTPS_NP "30443"
    ni_extra="--set controller.service.nodePorts.http=${NI_HTTP_NP} --set controller.service.nodePorts.https=${NI_HTTPS_NP}"
  fi

  kubectl create namespace "$NI_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "NGINX Ingress Controller 설치 중..."
  # shellcheck disable=SC2086
  helm upgrade --install "$NI_RELEASE" ingress-nginx/ingress-nginx \
    --namespace "$NI_NS" \
    --set controller.service.type="$ni_svc_type" \
    --set controller.metrics.enabled=true \
    --set controller.admissionWebhooks.enabled=true \
    $ni_extra \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "NGINX Ingress (ns: ${NI_NS})"
  success "NGINX Ingress Controller 설치 완료!"
  show_result "$(kubectl get pods,svc -n "$NI_NS" 2>&1)"

  echo -e "${BOLD}Ingress 리소스 예시:${NC}"
  echo -e "  ${DIM}apiVersion: networking.k8s.io/v1"
  echo -e "  kind: Ingress"
  echo -e "  metadata:"
  echo -e "    name: demo"
  echo -e "    annotations:"
  echo -e "      nginx.ingress.kubernetes.io/rewrite-target: /"
  echo -e "  spec:"
  echo -e "    ingressClassName: nginx"
  echo -e "    rules:"
  echo -e "    - host: demo.example.com"
  echo -e "      http:"
  echo -e "        paths:"
  echo -e "        - path: /"
  echo -e "          pathType: Prefix"
  echo -e "          backend:"
  echo -e "            service:"
  echo -e "              name: demo-svc"
  echo -e "              port:"
  echo -e "                number: 80${NC}"
  tip "kubectl get ingressclass   # 사용 가능한 IngressClass 확인"
  pause
}

# =============================================================================
# 9. Contour — Envoy 기반 Ingress Controller
# =============================================================================
addon_contour() {
  clear
  box "9. Contour — Envoy 기반 Ingress Controller"

  echo -e "
${BOLD}Contour란?${NC}
  ${CYAN}Envoy 프록시${NC}를 데이터 플레인으로 사용하는 Ingress Controller 입니다.
  CNCF Graduated 프로젝트로, 표준 Ingress 및 자체 ${CYAN}HTTPProxy CRD${NC}를 지원합니다.

${BOLD}아키텍처:${NC}
  ${DIM}┌───────────────────────────────────────────┐
  │  Contour (컨트롤 플레인)                    │
  │    • Ingress / HTTPProxy 감시               │
  │    • Envoy 설정(xDS) 생성·배포               │
  └──────────────┬──────────────────────────────┘
                 ↓ xDS
  ┌──────────────────────────────────────────────┐
  │  Envoy (데이터 플레인)                         │
  │    • L7 라우팅, TLS, Rate Limit, Retry       │
  └──────────────────────────────────────────────┘${NC}

${BOLD}HTTPProxy vs Ingress:${NC}
  • ${CYAN}HTTPProxy${NC}: 멀티 팀 위임(delegation), 가중치 라우팅, 상세 TLS 설정
  • ${CYAN}Ingress${NC}: 표준 K8s 리소스, 제한적 기능
"
  pause
  if ! confirm "Contour 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        CT_NS      "projectcontour"
  read_val "Helm Release 이름"     CT_RELEASE "contour"

  echo -e "\n  ${BOLD}Envoy Service 타입 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} LoadBalancer (권장)"
  echo -e "    ${CYAN}2)${NC} NodePort"
  echo -ne "    선택 [1-2]: "
  read -r ct_svc_choice
  local ct_svc_type="LoadBalancer"
  [[ "$ct_svc_choice" == "2" ]] && ct_svc_type="NodePort"

  kubectl create namespace "$CT_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Contour + Envoy 설치 중..."
  helm upgrade --install "$CT_RELEASE" projectcontour/contour \
    --namespace "$CT_NS" \
    --set envoy.service.type="$ct_svc_type" \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "Contour (ns: ${CT_NS})"
  success "Contour 설치 완료!"
  show_result "$(kubectl get pods,svc -n "$CT_NS" 2>&1)"

  echo -e "${BOLD}HTTPProxy 리소스 예시:${NC}"
  echo -e "  ${DIM}apiVersion: projectcontour.io/v1"
  echo -e "  kind: HTTPProxy"
  echo -e "  metadata:"
  echo -e "    name: demo"
  echo -e "  spec:"
  echo -e "    virtualhost:"
  echo -e "      fqdn: demo.example.com"
  echo -e "    routes:"
  echo -e "    - conditions:"
  echo -e "      - prefix: /"
  echo -e "      services:"
  echo -e "      - name: demo-svc"
  echo -e "        port: 80${NC}"
  tip "kubectl get httpproxy -A   # HTTPProxy 리소스 목록"
  pause
}

# =============================================================================
# 10. Loki — 로그 집계 시스템
# =============================================================================
addon_loki() {
  clear
  box "10. Loki — 경량 로그 집계 시스템 (Grafana)"

  echo -e "
${BOLD}Loki란?${NC}
  Grafana Labs 에서 만든 ${CYAN}로그 집계 시스템${NC}으로,
  Prometheus 의 라벨 기반 접근 방식을 로그에 적용합니다.
  Elasticsearch 대비 ${CYAN}인덱싱 비용이 매우 낮습니다.${NC}

${BOLD}아키텍처:${NC}
  ${DIM}컨테이너 로그
       ↓
  Promtail / Fluent Bit (수집 에이전트)
       ↓
  Loki (라벨 인덱싱 + 청크 저장)
       ↓
  Grafana (LogQL 쿼리 + 시각화)${NC}

${BOLD}Elasticsearch vs Loki:${NC}
  ${DIM}┌─────────────────┬──────────────────────────────────────────────┐
  │ Elasticsearch   │ 풀텍스트 인덱싱, 풍부한 검색, 높은 리소스 비용  │
  │ Loki            │ 라벨만 인덱싱, 경량, Grafana 통합, 저비용      │
  └─────────────────┴──────────────────────────────────────────────┘${NC}

${BOLD}LogQL 쿼리 예시:${NC}
  ${CYAN}{namespace=\"default\"} |= \"error\"${NC}    — default NS에서 error 포함 로그
  ${CYAN}rate({app=\"nginx\"}[5m])${NC}             — nginx 앱 로그 발생률
"
  pause
  if ! confirm "Loki 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        LK_NS      "logging"
  read_val "Helm Release 이름"     LK_RELEASE "loki"
  read_val "Loki PVC 크기"         LK_STORAGE "10Gi"

  echo -e "\n  ${BOLD}배포 모드 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} SingleBinary (학습/소규모, 권장)"
  echo -e "    ${CYAN}2)${NC} SimpleScalable (운영 환경)"
  echo -ne "    선택 [1-2]: "
  read -r lk_mode_choice
  local lk_mode="SingleBinary"
  [[ "$lk_mode_choice" == "2" ]] && lk_mode="SimpleScalable"

  local install_promtail="false"
  if confirm "  Promtail (로그 수집 에이전트) 도 함께 설치하시겠습니까?"; then
    install_promtail="true"
  fi

  kubectl create namespace "$LK_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Loki 설치 중..."
  helm upgrade --install "$LK_RELEASE" grafana/loki \
    --namespace "$LK_NS" \
    --set deploymentMode="$lk_mode" \
    --set loki.auth_enabled=false \
    --set loki.commonConfig.replication_factor=1 \
    --set loki.storage.type=filesystem \
    --set singleBinary.replicas=1 \
    --set singleBinary.persistence.size="$LK_STORAGE" \
    --set read.replicas=0 \
    --set write.replicas=0 \
    --set backend.replicas=0 \
    --set gateway.enabled=false \
    --set chunksCache.enabled=false \
    --set resultsCache.enabled=false \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  if [[ "$install_promtail" == "true" ]]; then
    step "Promtail 설치 중..."
    helm upgrade --install promtail grafana/promtail \
      --namespace "$LK_NS" \
      --set config.clients[0].url="http://${LK_RELEASE}.${LK_NS}.svc.cluster.local:3100/loki/api/v1/push" \
      --wait --timeout 3m 2>&1 | tee -a "$LOG_FILE"
  fi

  mark_installed "Loki (ns: ${LK_NS})"
  success "Loki 설치 완료!"
  show_result "$(kubectl get pods -n "$LK_NS" 2>&1)"

  echo -e "${BOLD}Grafana 연동:${NC}"
  echo -e "  Grafana → Configuration → Data Sources → Add → Loki"
  echo -e "  URL: ${GREEN}http://${LK_RELEASE}.${LK_NS}.svc.cluster.local:3100${NC}"
  tip "logcli query '{namespace=\"default\"}' --addr=http://localhost:3100   # CLI 테스트"
  pause
}

# =============================================================================
# 11. cert-manager — 인증서 자동 관리
# =============================================================================
addon_cert_manager() {
  clear
  box "11. cert-manager — TLS 인증서 자동 발급·갱신"

  echo -e "
${BOLD}cert-manager란?${NC}
  Kubernetes 에서 ${CYAN}TLS 인증서를 자동으로 발급·갱신${NC}하는 컨트롤러입니다.
  Let's Encrypt, Vault, Venafi 등 다양한 CA와 연동됩니다.

${BOLD}핵심 CRD:${NC}
  ${DIM}┌──────────────────────────────────────────────────────────┐
  │  Issuer / ClusterIssuer  — 인증서 발급 기관 설정          │
  │  Certificate             — 인증서 요청 (자동 갱신)         │
  │  CertificateRequest      — 내부 발급 요청 오브젝트         │
  │  Order / Challenge       — ACME(Let's Encrypt) 검증 흐름  │
  └──────────────────────────────────────────────────────────┘${NC}

${BOLD}동작 흐름:${NC}
  ${DIM}Certificate CR 생성
       ↓
  cert-manager → ClusterIssuer (Let's Encrypt 등) 에 인증서 요청
       ↓
  ACME Challenge (HTTP-01 / DNS-01) 검증
       ↓
  TLS Secret 자동 생성 → Ingress 에서 참조
       ↓
  만료 30일 전 자동 갱신${NC}

${BOLD}Ingress 연동:${NC}
  Ingress annotation 으로 자동 인증서 발급:
  ${CYAN}cert-manager.io/cluster-issuer: letsencrypt-prod${NC}
"
  pause
  if ! confirm "cert-manager 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        CM_NS      "cert-manager"
  read_val "Helm Release 이름"     CM_RELEASE "cert-manager"

  kubectl create namespace "$CM_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "cert-manager 설치 중 (CRD 포함)..."
  helm upgrade --install "$CM_RELEASE" jetstack/cert-manager \
    --namespace "$CM_NS" \
    --set crds.enabled=true \
    --set prometheus.enabled=true \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  success "cert-manager 설치 완료!"

  # 셀프 사인드 ClusterIssuer 생성 (학습용)
  if confirm "  Self-Signed ClusterIssuer 를 생성하시겠습니까? (학습/테스트용)"; then
    step "Self-Signed ClusterIssuer 생성 중..."
    kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
    success "ClusterIssuer 'selfsigned-issuer' 생성 완료"
  fi

  # Let's Encrypt Staging Issuer (선택)
  if confirm "  Let's Encrypt Staging ClusterIssuer 도 생성하시겠습니까?"; then
    read_val "  이메일 주소 (Let's Encrypt 알림용)" CM_EMAIL "admin@example.com"
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${CM_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx
EOF
    success "ClusterIssuer 'letsencrypt-staging' 생성 완료"
  fi

  mark_installed "cert-manager (ns: ${CM_NS})"
  show_result "$(kubectl get pods -n "$CM_NS" 2>&1)"

  echo -e "${BOLD}인증서 발급 예시:${NC}"
  echo -e "  ${DIM}apiVersion: cert-manager.io/v1"
  echo -e "  kind: Certificate"
  echo -e "  metadata:"
  echo -e "    name: demo-tls"
  echo -e "  spec:"
  echo -e "    secretName: demo-tls-secret"
  echo -e "    issuerRef:"
  echo -e "      name: selfsigned-issuer"
  echo -e "      kind: ClusterIssuer"
  echo -e "    dnsNames:"
  echo -e "    - demo.example.com${NC}"
  tip "kubectl get certificate,clusterissuer -A   # 인증서 상태 확인"
  tip "cmctl status certificate <name>            # 상세 상태 (cmctl CLI)"
  pause
}

# =============================================================================
# 12. ArgoCD — GitOps CD 플랫폼
# =============================================================================
addon_argocd() {
  clear
  box "12. ArgoCD — GitOps 지속적 배포 (CD)"

  echo -e "
${BOLD}ArgoCD란?${NC}
  ${CYAN}Git 저장소를 단일 소스 오브 트루스(SSOT)${NC}로 사용하여
  Kubernetes 클러스터를 선언적으로 동기화하는 GitOps CD 플랫폼입니다.

${BOLD}GitOps 4대 원칙:${NC}
  ${DIM}1. 선언적 기술 (Declarative)
  2. 버전 관리 (Git = 단일 진실의 원천)
  3. 자동 적용 (Approved changes are applied automatically)
  4. 자동 복구 (Software agents ensure correctness)${NC}

${BOLD}아키텍처:${NC}
  ${DIM}Developer → Git push → Git Repository
                                  ↓ (3분 폴링 또는 Webhook)
                           ArgoCD Server
                           ├── Application Controller (동기화)
                           ├── Repo Server (매니페스트 렌더링)
                           └── Redis (캐시)
                                  ↓
                           Kubernetes Cluster (desired state 적용)${NC}

${BOLD}핵심 CRD:${NC}
  • ${CYAN}Application${NC}     — Git 소스 ↔ K8s 대상 매핑
  • ${CYAN}ApplicationSet${NC}  — 여러 Application 템플릿 생성 (멀티 환경)
  • ${CYAN}AppProject${NC}      — RBAC 및 소스/대상 제한
"
  pause
  if ! confirm "ArgoCD 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        ARGO_NS      "argocd"
  read_val "Helm Release 이름"     ARGO_RELEASE "argocd"

  echo -e "\n  ${BOLD}HA 모드 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} 단일 인스턴스 (학습/개발, 권장)"
  echo -e "    ${CYAN}2)${NC} HA 모드 (운영 환경)"
  echo -ne "    선택 [1-2]: "
  read -r argo_ha_choice
  local argo_ha_flags=""
  if [[ "$argo_ha_choice" == "2" ]]; then
    argo_ha_flags="--set controller.replicas=2 --set server.replicas=2 --set repoServer.replicas=2"
  fi

  echo -e "\n  ${BOLD}ArgoCD Server 노출 방식:${NC}"
  echo -e "    ${CYAN}1)${NC} ClusterIP (port-forward 사용, 기본)"
  echo -e "    ${CYAN}2)${NC} NodePort"
  echo -e "    ${CYAN}3)${NC} LoadBalancer"
  echo -ne "    선택 [1-3]: "
  read -r argo_svc_choice
  local argo_svc_type="ClusterIP"
  case "$argo_svc_choice" in
    2) argo_svc_type="NodePort" ;;
    3) argo_svc_type="LoadBalancer" ;;
  esac

  kubectl create namespace "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "ArgoCD 설치 중..."
  # shellcheck disable=SC2086
  helm upgrade --install "$ARGO_RELEASE" argo/argo-cd \
    --namespace "$ARGO_NS" \
    --set server.service.type="$argo_svc_type" \
    --set configs.params."server\.insecure"=true \
    $argo_ha_flags \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "ArgoCD (ns: ${ARGO_NS})"
  success "ArgoCD 설치 완료!"
  show_result "$(kubectl get pods -n "$ARGO_NS" 2>&1)"

  echo -e "${BOLD}초기 비밀번호 확인:${NC}"
  echo -e "  ${GREEN}kubectl -n ${ARGO_NS} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d${NC}"
  echo ""
  echo -e "${BOLD}접속 방법:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/${ARGO_RELEASE}-server 8080:80 -n ${ARGO_NS}${NC}"
  echo -e "  브라우저: http://localhost:8080  (admin / <위 비밀번호>)"
  echo ""
  echo -e "${BOLD}CLI 로그인:${NC}"
  echo -e "  ${GREEN}argocd login localhost:8080 --username admin --password <비밀번호> --insecure${NC}"
  tip "argocd app list   # 등록된 Application 목록"
  tip "argocd app sync <app-name>   # 수동 동기화"
  pause
}

# =============================================================================
# 13. FluxCD — GitOps Toolkit
# =============================================================================
addon_fluxcd() {
  clear
  box "13. FluxCD — GitOps Toolkit"

  echo -e "
${BOLD}FluxCD란?${NC}
  CNCF Graduated 프로젝트로, ${CYAN}Git 저장소와 Kubernetes 클러스터를
  자동으로 동기화${NC}하는 GitOps 도구입니다.

${BOLD}ArgoCD와의 차이:${NC}
  ${DIM}┌───────────────┬──────────────────────────────────────────────┐
  │ ArgoCD        │ 풍부한 UI, Application CRD, 중앙 집중 관리    │
  │ FluxCD        │ CLI 중심, 분산형, 작은 구성 요소 조합          │
  └───────────────┴──────────────────────────────────────────────┘${NC}

${BOLD}핵심 컴포넌트:${NC}
  ${DIM}Source Controller     — Git/Helm/OCI 소스 감시
  Kustomize Controller — Kustomization 적용
  Helm Controller      — HelmRelease CRD 처리
  Notification Controller — 이벤트 알림${NC}

${BOLD}동작 흐름:${NC}
  ${DIM}GitRepository CR → Source Controller (폴링/Webhook)
       ↓
  Kustomization CR → Kustomize Controller → kubectl apply
       또는
  HelmRelease CR → Helm Controller → helm upgrade --install${NC}
"
  pause
  if ! confirm "FluxCD 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace" FLUX_NS "flux-system"

  echo -e "\n  ${BOLD}설치 방법 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Helm Chart (권장)"
  echo -e "    ${CYAN}2)${NC} flux CLI bootstrap (Git 저장소 필요)"
  echo -ne "    선택 [1-2]: "
  read -r flux_method

  kubectl create namespace "$FLUX_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  if [[ "$flux_method" == "2" ]]; then
    # flux CLI 확인
    if ! command -v flux &>/dev/null; then
      warn "flux CLI 가 설치되어 있지 않습니다."
      echo -e "  설치 방법: ${GREEN}brew install fluxcd/tap/flux${NC}  (macOS)"
      echo -e "            ${GREEN}curl -s https://fluxcd.io/install.sh | sudo bash${NC}  (Linux)"
      if ! confirm "  Helm 방식으로 대체 설치하시겠습니까?"; then
        pause
        return
      fi
      # Helm 방식으로 폴백
    else
      step "flux 사전 검사..."
      flux check --pre 2>&1 | tee -a "$LOG_FILE"

      read_val "  GitHub Owner (user/org)"  FLUX_OWNER  ""
      read_val "  Repository 이름"           FLUX_REPO   "fleet-infra"
      read_val "  Branch"                    FLUX_BRANCH "main"
      read_val "  Path (클러스터 매니페스트 경로)" FLUX_PATH "clusters/lab"

      echo -e "\n  ${YELLOW}GITHUB_TOKEN 환경변수가 설정되어 있어야 합니다.${NC}"
      if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        warn "GITHUB_TOKEN 이 설정되지 않았습니다."
        echo -ne "  GitHub Personal Access Token 입력: "
        read -rs GITHUB_TOKEN
        echo ""
        export GITHUB_TOKEN
      fi

      step "flux bootstrap 실행 중..."
      flux bootstrap github \
        --owner="$FLUX_OWNER" \
        --repository="$FLUX_REPO" \
        --branch="$FLUX_BRANCH" \
        --path="$FLUX_PATH" \
        --personal 2>&1 | tee -a "$LOG_FILE"

      mark_installed "FluxCD (ns: ${FLUX_NS}, repo: ${FLUX_OWNER}/${FLUX_REPO})"
      success "FluxCD bootstrap 완료!"
      show_result "$(kubectl get pods -n "$FLUX_NS" 2>&1)"
      tip "flux get all -A   # 모든 Flux 리소스 상태"
      pause
      return
    fi
  fi

  # Helm 방식 설치
  step "FluxCD Helm Chart 설치 중..."
  helm upgrade --install flux-operator fluxcd-community/flux2 \
    --namespace "$FLUX_NS" \
    --wait --timeout 5m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "FluxCD (ns: ${FLUX_NS})"
  success "FluxCD 설치 완료!"
  show_result "$(kubectl get pods -n "$FLUX_NS" 2>&1)"

  echo -e "${BOLD}GitRepository 소스 예시:${NC}"
  echo -e "  ${DIM}apiVersion: source.toolkit.fluxcd.io/v1"
  echo -e "  kind: GitRepository"
  echo -e "  metadata:"
  echo -e "    name: my-app"
  echo -e "    namespace: ${FLUX_NS}"
  echo -e "  spec:"
  echo -e "    interval: 1m"
  echo -e "    url: https://github.com/<owner>/<repo>"
  echo -e "    ref:"
  echo -e "      branch: main${NC}"
  tip "flux get source git -A   # Git 소스 목록"
  tip "flux reconcile source git <name>   # 수동 동기화"
  pause
}

# =============================================================================
# 14. Jenkins — CI/CD 자동화
# =============================================================================
addon_jenkins() {
  clear
  box "14. Jenkins — CI/CD 자동화 서버"

  echo -e "
${BOLD}Jenkins란?${NC}
  오픈소스 ${CYAN}CI/CD 자동화 서버${NC}로, 빌드·테스트·배포를
  Pipeline as Code(Jenkinsfile) 로 정의합니다.

${BOLD}K8s 기반 Jenkins 아키텍처:${NC}
  ${DIM}┌─────────────────────────────────────────────┐
  │  Jenkins Controller (Master)                │
  │    • Pipeline 관리, UI, 스케줄링              │
  │    • StatefulSet (영구 데이터)                │
  └──────────────┬──────────────────────────────┘
                 ↓ 동적 Agent 생성
  ┌──────────────────────────────────────────────┐
  │  Jenkins Agent Pods (동적 생성/삭제)           │
  │    • 빌드마다 새 Pod 생성                      │
  │    • 빌드 후 자동 삭제 (리소스 효율)            │
  │    • kubernetes plugin 사용                   │
  └──────────────────────────────────────────────┘${NC}

${BOLD}Jenkinsfile (Declarative Pipeline):${NC}
  ${DIM}pipeline {
    agent { kubernetes { ... } }
    stages {
      stage('Build')  { steps { sh 'make build' } }
      stage('Test')   { steps { sh 'make test' } }
      stage('Deploy') { steps { sh 'kubectl apply -f ...' } }
    }
  }${NC}
"
  pause
  if ! confirm "Jenkins 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace"        JK_NS      "jenkins"
  read_val "Helm Release 이름"     JK_RELEASE "jenkins"
  read_val "관리자 비밀번호"        JK_PASS    "admin1234"
  read_val "Controller PVC 크기"   JK_STORAGE "10Gi"

  echo -e "\n  ${BOLD}Jenkins Service 타입 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} ClusterIP (port-forward 사용, 기본)"
  echo -e "    ${CYAN}2)${NC} NodePort"
  echo -e "    ${CYAN}3)${NC} LoadBalancer"
  echo -ne "    선택 [1-3]: "
  read -r jk_svc_choice
  local jk_svc_type="ClusterIP"
  local jk_extra=""
  case "$jk_svc_choice" in
    2)
      jk_svc_type="NodePort"
      read_val "  NodePort 번호" JK_NP "32080"
      jk_extra="--set controller.servicePort=8080 --set controller.nodePort=${JK_NP}"
      ;;
    3) jk_svc_type="LoadBalancer" ;;
  esac

  kubectl create namespace "$JK_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Jenkins 설치 중 (3~5분 소요)..."
  # shellcheck disable=SC2086
  helm upgrade --install "$JK_RELEASE" jenkins/jenkins \
    --namespace "$JK_NS" \
    --set controller.adminUser=admin \
    --set controller.adminPassword="$JK_PASS" \
    --set controller.serviceType="$jk_svc_type" \
    --set persistence.size="$JK_STORAGE" \
    --set agent.enabled=true \
    --set controller.installPlugins="{kubernetes:latest,workflow-aggregator:latest,git:latest,configuration-as-code:latest}" \
    $jk_extra \
    --wait --timeout 8m 2>&1 | tee -a "$LOG_FILE"

  mark_installed "Jenkins (ns: ${JK_NS})"
  success "Jenkins 설치 완료!"
  show_result "$(kubectl get pods,svc -n "$JK_NS" 2>&1)"

  echo -e "${BOLD}접속 방법:${NC}"
  echo -e "  ${GREEN}kubectl port-forward svc/${JK_RELEASE} 8080:8080 -n ${JK_NS}${NC}"
  echo -e "  브라우저: http://localhost:8080  (admin / ${JK_PASS})"
  echo ""
  echo -e "${BOLD}관리자 비밀번호 확인 (분실 시):${NC}"
  echo -e "  ${GREEN}kubectl exec -n ${JK_NS} svc/${JK_RELEASE} -- cat /run/secrets/additional/chart-admin-password${NC}"
  tip "Jenkins 설정 → Manage Jenkins → Cloud → Kubernetes 연동 확인"
  tip "Jenkinsfile 을 Git 에 넣고 Multibranch Pipeline 으로 자동 트리거"
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
# 애드온 정의 테이블 (이름, Helm Release, Namespace, 설명)
# =============================================================================
# 형식: "번호|이름|Helm릴리즈|네임스페이스|카테고리|설명"
ADDON_DEFS=(
  "1|Prometheus + Grafana|kube-prom|monitoring|모니터링|kube-prometheus-stack"
  "2|Velero + MinIO|velero,minio|velero|백업/복구|클러스터 백업 & 복구"
  "3|Istio|istio-base,istiod|istio-system|서비스 메시|트래픽 관리, mTLS"
  "4|Elasticsearch + Kibana|elastic-operator|elastic-system|로그 분석|ECK Operator"
  "5|Fluent Bit|fluent-bit|logging|로그 수집|DaemonSet 로그 수집"
  "6|Kyverno|kyverno|kyverno|정책 관리|K8s-Native 정책 엔진"
  "7|OPA Gatekeeper|gatekeeper|gatekeeper-system|정책 관리|Rego 기반 정책"
  "8|NGINX Ingress|ingress-nginx|ingress-nginx|인그레스|L7 HTTP(S) 라우팅"
  "9|Contour|contour|projectcontour|인그레스|Envoy 기반 Ingress"
  "10|Loki|loki|logging|로그 집계|Grafana 경량 로그"
  "11|cert-manager|cert-manager|cert-manager|인증서|TLS 인증서 자동 관리"
  "12|ArgoCD|argocd|argocd|GitOps CD|Git 기반 CD 플랫폼"
  "13|FluxCD|flux-operator|flux-system|GitOps CD|GitOps Toolkit"
  "14|Jenkins|jenkins|jenkins|CI/CD|CI/CD 자동화 서버"
)

# Helm release 가 설치되어 있는지 확인 (첫 번째 릴리즈 기준)
_is_helm_installed() {
  local releases="$1" ns="$2"
  local first_release="${releases%%,*}"
  helm status "$first_release" -n "$ns" &>/dev/null
}

# =============================================================================
# 설치 현황 확인
# =============================================================================
show_status() {
  clear
  box "클러스터 애드온 설치 현황"
  echo ""

  # 이번 세션 설치 목록
  if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    echo -e "${BOLD}이번 세션 설치:${NC}"
    for item in "${INSTALLED[@]}"; do
      echo -e "  ${GREEN}✔${NC}  $item"
    done
    echo ""
  fi

  # 전체 애드온 설치 상태
  echo -e "${BOLD}  #   애드온                  카테고리      상태         네임스페이스${NC}"
  echo -e "  ${DIM}─── ──────────────────────── ──────────── ──────────── ──────────────${NC}"

  for def in "${ADDON_DEFS[@]}"; do
    IFS='|' read -r num name releases ns category desc <<< "$def"
    local status_icon status_text pods_info=""

    if _is_helm_installed "$releases" "$ns"; then
      local total ready not_ready
      total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      ready=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running\|Completed" || true)
      not_ready=$((total - ready))

      if (( not_ready > 0 )); then
        status_icon="${YELLOW}⚠${NC}"
        status_text="${YELLOW}부분 실행${NC}"
        pods_info=" (${ready}/${total} pods)"
      else
        status_icon="${GREEN}✔${NC}"
        status_text="${GREEN}설치됨${NC}"
        pods_info=" (${total} pods)"
      fi
    else
      # Helm 이 아닌 방식으로 설치되었을 수 있으므로 Pod 존재 여부도 확인
      local pod_count
      pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if (( pod_count > 0 )); then
        status_icon="${YELLOW}?${NC}"
        status_text="${YELLOW}감지됨${NC}"
        pods_info=" (${pod_count} pods)"
      else
        status_icon="${DIM}✗${NC}"
        status_text="${DIM}미설치${NC}"
      fi
    fi

    printf "  %s %-2s  %-24s %-12s %b%-10s%b %s%s\n" \
      "$status_icon" "$num" "$name" "$category" "" "$status_text" "" "$ns" "$pods_info"
  done

  echo ""
  echo -e "  ${DIM}범례: ${GREEN}✔${NC}${DIM} 설치됨  ${YELLOW}⚠${NC}${DIM} 부분 실행  ${YELLOW}?${NC}${DIM} 감지됨(비-Helm)  ✗ 미설치${NC}"
  echo ""
  pause
}

# =============================================================================
# 애드온 삭제
# =============================================================================
uninstall_addon() {
  clear
  box "애드온 삭제 (Uninstall)"
  echo ""

  # 설치된 애드온만 목록 표시
  local has_installed=false
  echo -e "  ${BOLD}설치된 애드온 목록:${NC}"
  echo ""

  for def in "${ADDON_DEFS[@]}"; do
    IFS='|' read -r num name releases ns category desc <<< "$def"
    if _is_helm_installed "$releases" "$ns"; then
      local pod_count
      pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      echo -e "  ${CYAN}${num})${NC} ${name}  ${DIM}(ns: ${ns}, ${pod_count} pods)${NC}"
      has_installed=true
    fi
  done

  if [[ "$has_installed" == "false" ]]; then
    echo -e "  ${DIM}Helm 으로 설치된 애드온이 없습니다.${NC}"
    echo ""
    pause
    return
  fi

  echo ""
  echo -e "  ${RED}${BOLD}주의: 삭제 시 관련 데이터(PVC)는 기본적으로 유지됩니다.${NC}"
  echo -e "  ${DIM}PVC 까지 삭제하려면 삭제 후 별도로 kubectl delete pvc -n <ns> --all${NC}"
  echo ""
  echo -ne "  ${BOLD}삭제할 애드온 번호 (취소: Enter):${NC} "
  read -r del_choice

  [[ -z "$del_choice" ]] && return

  # 선택된 번호의 애드온 정보 찾기
  local found=false
  for def in "${ADDON_DEFS[@]}"; do
    IFS='|' read -r num name releases ns category desc <<< "$def"
    if [[ "$num" == "$del_choice" ]]; then
      found=true

      if ! _is_helm_installed "$releases" "$ns"; then
        warn "${name} 은(는) Helm 으로 설치되어 있지 않습니다."
        pause
        return
      fi

      echo ""
      echo -e "  ${RED}${BOLD}삭제 대상:${NC} ${name}"
      echo -e "  ${RED}${BOLD}네임스페이스:${NC} ${ns}"
      echo -e "  ${RED}${BOLD}Helm Release:${NC} ${releases}"
      echo ""

      if ! confirm "  정말 ${name} 을(를) 삭제하시겠습니까?"; then
        log "삭제 취소: ${name}"
        pause
        return
      fi

      # 애드온별 특수 삭제 처리
      case "$num" in
        2) # Velero + MinIO — 두 릴리즈 삭제
          step "Velero 삭제 중..."
          helm uninstall velero -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          step "MinIO 삭제 중..."
          helm uninstall minio -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        3) # Istio — base + istiod + gateway
          step "Istio Ingress Gateway 삭제 중..."
          helm uninstall istio-ingressgateway -n istio-ingress 2>&1 | tee -a "$LOG_FILE" || true
          step "istiod 삭제 중..."
          helm uninstall istiod -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          step "Istio base 삭제 중..."
          helm uninstall istio-base -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          # Kiali 삭제 시도
          helm uninstall kiali-operator -n "$ns" 2>/dev/null || true
          kubectl delete namespace istio-ingress --ignore-not-found 2>/dev/null || true
          ;;
        4) # Elasticsearch + Kibana — CR 먼저 삭제 후 Operator
          step "Elasticsearch/Kibana CR 삭제 중..."
          kubectl delete kibana --all -n "$ns" 2>/dev/null || true
          kubectl delete elasticsearch --all -n "$ns" 2>/dev/null || true
          step "ECK Operator 삭제 중..."
          helm uninstall elastic-operator -n elastic-system 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        10) # Loki + Promtail
          step "Promtail 삭제 중..."
          helm uninstall promtail -n "$ns" 2>/dev/null || true
          step "Loki 삭제 중..."
          helm uninstall loki -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        11) # cert-manager — ClusterIssuer 먼저 삭제
          step "ClusterIssuer 삭제 중..."
          kubectl delete clusterissuer --all 2>/dev/null || true
          step "cert-manager 삭제 중..."
          helm uninstall cert-manager -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        6) # Kyverno — ClusterPolicy 삭제
          step "ClusterPolicy 삭제 중..."
          kubectl delete clusterpolicy --all 2>/dev/null || true
          step "Kyverno 삭제 중..."
          helm uninstall kyverno -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        7) # OPA Gatekeeper — Constraint/ConstraintTemplate 삭제
          step "Constraint / ConstraintTemplate 삭제 중..."
          kubectl delete constraints --all 2>/dev/null || true
          kubectl delete constrainttemplate --all 2>/dev/null || true
          step "OPA Gatekeeper 삭제 중..."
          helm uninstall gatekeeper -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          ;;
        *) # 일반적인 단일 릴리즈 삭제
          IFS=',' read -ra rel_array <<< "$releases"
          for rel in "${rel_array[@]}"; do
            step "${rel} 삭제 중..."
            helm uninstall "$rel" -n "$ns" 2>&1 | tee -a "$LOG_FILE" || true
          done
          ;;
      esac

      # 네임스페이스 삭제 여부
      echo ""
      if confirm "  네임스페이스 '${ns}' 도 함께 삭제하시겠습니까?"; then
        step "네임스페이스 ${ns} 삭제 중..."
        kubectl delete namespace "$ns" --timeout=60s 2>&1 | tee -a "$LOG_FILE" || \
          warn "네임스페이스 삭제 시간 초과. 수동으로 확인하세요: kubectl delete ns ${ns}"
      fi

      success "${name} 삭제 완료!"
      show_result "$(kubectl get pods -n "$ns" 2>&1)"
      pause
      return
    fi
  done

  if [[ "$found" == "false" ]]; then
    warn "잘못된 번호입니다: ${del_choice}"
    pause
  fi
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
    echo -e "  ${CYAN}  1)${NC} Prometheus + Grafana   — 메트릭 수집 & 시각화 (kube-prometheus-stack)"
    echo -e "  ${CYAN}  2)${NC} Velero + MinIO         — 클러스터 백업 & 복구"
    echo -e "  ${CYAN}  3)${NC} Istio                  — 서비스 메시 (트래픽 관리, mTLS)"
    echo -e "  ${CYAN}  4)${NC} Elasticsearch + Kibana — 로그 저장 & 검색 시각화 (ECK)"
    echo -e "  ${CYAN}  5)${NC} Fluent Bit             — 경량 로그 수집 DaemonSet"
    echo -e "  ${CYAN}  6)${NC} Kyverno               — K8s-Native 정책 엔진"
    echo -e "  ${CYAN}  7)${NC} OPA Gatekeeper        — Rego 기반 정책 접근 제어"
    echo -e "  ${CYAN}  8)${NC} NGINX Ingress         — L7 HTTP(S) 라우팅"
    echo -e "  ${CYAN}  9)${NC} Contour               — Envoy 기반 Ingress Controller"
    echo -e "  ${CYAN} 10)${NC} Loki                  — 경량 로그 집계 (Grafana)"
    echo -e "  ${CYAN} 11)${NC} cert-manager          — TLS 인증서 자동 발급·갱신"
    echo -e "  ${CYAN} 12)${NC} ArgoCD                — GitOps CD 플랫폼"
    echo -e "  ${CYAN} 13)${NC} FluxCD                — GitOps Toolkit"
    echo -e "  ${CYAN} 14)${NC} Jenkins               — CI/CD 자동화 서버"
    echo ""
    echo -e "  ${BOLD}── 번들 설치 (여러 컴포넌트 한 번에) ──────────────────────${NC}"
    echo -e "  ${YELLOW} b1)${NC} Observability Stack   — Prometheus + Grafana + ES + Fluent Bit"
    echo -e "  ${YELLOW} b2)${NC} Policy Stack          — Kyverno + OPA Gatekeeper"
    echo ""
    echo -e "  ${BOLD}── 관리 ──────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}  s)${NC} 설치 현황 확인        — 전체 애드온 설치 상태 조회"
    echo -e "  ${RED}   d)${NC} 애드온 삭제            — 설치된 애드온 선택 삭제"
    echo -e "  ${RED}   q)${NC} 종료"
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
      8) addon_nginx_ingress ;;
      9) addon_contour ;;
      10) addon_loki ;;
      11) addon_cert_manager ;;
      12) addon_argocd ;;
      13) addon_fluxcd ;;
      14) addon_jenkins ;;
      b1|B1) bundle_observability ;;
      b2|B2) bundle_policy ;;
      s|S) show_status ;;
      d|D) uninstall_addon ;;
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
