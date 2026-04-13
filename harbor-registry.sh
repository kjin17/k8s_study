#!/usr/bin/env bash
# =============================================================================
# Harbor & Trivy — 프라이빗 컨테이너 레지스트리 인터랙티브 실습 스크립트
# 포함 기능: Harbor 설치, 프로젝트 관리, Docker Push/Pull, Trivy 스캔,
#           Helm 차트 관리, 이미지 보안 설정, Harbor 삭제
# 설치 방식: Helm 3
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

LOG_FILE="harbor-registry-$(date +%Y%m%d-%H%M%S).log"

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

read_secret() {
  local prompt="$1" var="$2" default="${3:-}" val
  if [[ -n "$default" ]]; then
    echo -ne "  ${BOLD}${prompt}${NC} ${DIM}[기본값: ${default}]${NC}: "
  else
    echo -ne "  ${BOLD}${prompt}${NC}: "
  fi
  read -rs val
  echo ""
  printf -v "$var" '%s' "${val:-$default}"
}

show_result() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━━ 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}$*${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

show_yaml() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━ YAML / 설정 ━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}$1${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

INSTALLED=()
mark_installed() { INSTALLED+=("$1"); }

# 전역 Harbor 접속 정보 (메뉴 간 공유)
HARBOR_URL=""
HARBOR_USER="admin"
HARBOR_PASS=""
HARBOR_NS=""
HARBOR_INSECURE=""

# Harbor 접속 정보가 설정되었는지 확인
ensure_harbor_info() {
  if [[ -z "$HARBOR_URL" || -z "$HARBOR_PASS" ]]; then
    echo -e "\n${YELLOW}Harbor 접속 정보가 필요합니다.${NC}"
    read_val "Harbor 외부 URL (예: https://harbor.local:30003)" HARBOR_URL ""
    read_val "Harbor 관리자 사용자명" HARBOR_USER "admin"
    read_secret "Harbor 관리자 비밀번호" HARBOR_PASS "Harbor12345"
    read_val "Harbor Namespace" HARBOR_NS "harbor"
    if confirm "자체 서명 인증서 사용 (insecure 모드)?"; then
      HARBOR_INSECURE="-k"
    fi
  fi
}

# Harbor API 호출 헬퍼
harbor_api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local url="${HARBOR_URL}/api/v2.0${endpoint}"
  local args=(-s -u "${HARBOR_USER}:${HARBOR_PASS}" -H "Content-Type: application/json")
  [[ -n "$HARBOR_INSECURE" ]] && args+=(-k)

  if [[ -n "$data" ]]; then
    curl "${args[@]}" -X "$method" -d "$data" "$url" 2>/dev/null
  else
    curl "${args[@]}" -X "$method" "$url" 2>/dev/null
  fi
}

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
    warn "Helm 이 설치되어 있지 않습니다."
    if confirm "Helm 을 자동 설치하시겠습니까?"; then
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      success "Helm 설치 완료: $(helm version --short)"
    else
      fail "Helm 없이는 Harbor 를 설치할 수 없습니다."
    fi
  else
    success "Helm — $(helm version --short)"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    success "Docker — $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo '확인불가')"
  else
    warn "Docker CLI 가 설치되어 있지 않습니다. 이미지 Push/Pull 실습에 필요합니다."
  fi
}

# -----------------------------------------------------------------------------
# Helm 저장소 등록
# -----------------------------------------------------------------------------
add_helm_repos() {
  step "Helm 저장소 등록"
  helm repo add harbor https://helm.goharbor.io --force-update &>/dev/null && \
    log "  저장소 등록: harbor" || warn "  저장소 등록 실패: harbor"
  helm repo update &>/dev/null
  success "Helm 저장소 업데이트 완료"
}

# =============================================================================
# 1. Harbor 설치 (Helm)
# =============================================================================
addon_harbor() {
  clear
  box "1. Harbor 설치 — 프라이빗 컨테이너 레지스트리"

  echo -e "
${BOLD}Harbor란?${NC}
  CNCF 졸업(Graduated) 프로젝트로, Docker Distribution 위에
  ${CYAN}보안, 접근 제어, 취약점 스캔${NC} 등 엔터프라이즈 기능을 추가한
  프라이빗 컨테이너 이미지 레지스트리입니다.

${BOLD}아키텍처:${NC}
  ${DIM}┌─────────────────────── Harbor ──────────────────────────┐
  │  Nginx (Reverse Proxy)                                 │
  │     │                                                  │
  │  ┌──▼───────┐  ┌──────────┐  ┌────────────┐           │
  │  │   Core   │  │ Registry │  │ Job Service│           │
  │  │ (API/UI) │  │  (이미지) │  │ (복제/GC)  │           │
  │  └────┬─────┘  └──────────┘  └─────┬──────┘           │
  │       │                            │                   │
  │  ┌────▼─────┐  ┌────────┐   ┌─────▼──────┐           │
  │  │PostgreSQL│  │ Redis  │   │   Trivy    │           │
  │  │ (메타DB) │  │ (캐시) │   │ (취약점스캔)│           │
  │  └──────────┘  └────────┘   └────────────┘           │
  └───────────────────────────────────────────────────────┘${NC}

${BOLD}주요 기능:${NC}
  • 프로젝트별 RBAC (역할 기반 접근 제어)
  • Trivy 통합 취약점 스캔 (Push 시 자동 스캔)
  • 이미지 서명 (Cosign/Notation)
  • 레지스트리 간 복제 (Replication)
  • Garbage Collection, Retention Policy
  • Helm 차트 저장소 (OCI 지원)
"
  pause
  if ! confirm "Harbor 를 설치하시겠습니까?"; then return; fi

  read_val "설치 Namespace" HARBOR_NS "harbor"
  read_val "Helm Release 이름" HB_RELEASE "harbor"
  read_secret "관리자 비밀번호 (admin)" HARBOR_PASS "Harbor12345"

  echo -e "\n  ${BOLD}외부 노출 방식:${NC}"
  echo -e "    ${CYAN}1)${NC} NodePort   — 설정 간단, 포트 고정 (학습/테스트용)"
  echo -e "    ${CYAN}2)${NC} Ingress    — 도메인 기반 접근 (Ingress Controller 필요)"
  echo -e "    ${CYAN}3)${NC} LoadBalancer — 외부 IP 자동 할당 (클라우드/MetalLB)"
  echo -ne "  ${BOLD}선택 [1-3]:${NC} "
  read -r expose_choice

  local expose_type="nodePort"
  local expose_opts=""
  local ext_url=""

  case "${expose_choice:-1}" in
    1)
      expose_type="nodePort"
      read_val "HTTPS NodePort 번호" HB_NODEPORT "30003"
      expose_opts="--set expose.nodePort.ports.https.nodePort=${HB_NODEPORT}"
      read_val "외부 접근 URL" ext_url "https://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}' 2>/dev/null || echo 'harbor.local'):${HB_NODEPORT}"
      ;;
    2)
      expose_type="ingress"
      read_val "Harbor 도메인" HB_DOMAIN "harbor.local"
      read_val "Ingress Class 이름" HB_INGCLASS "nginx"
      expose_opts="--set expose.ingress.hosts.core=${HB_DOMAIN} --set expose.ingress.className=${HB_INGCLASS}"
      ext_url="https://${HB_DOMAIN}"
      ;;
    3)
      expose_type="loadBalancer"
      ext_url=""
      ;;
  esac

  echo -e "\n  ${BOLD}TLS 설정:${NC}"
  local tls_opts="--set expose.tls.auto.commonName=harbor.local"
  if confirm "  자체 서명 인증서를 자동 생성하시겠습니까? (학습용 권장)"; then
    tls_opts="--set expose.tls.auto.commonName=harbor.local"
    HARBOR_INSECURE="-k"
  else
    read_val "  TLS Secret 이름 (기존 Secret)" HB_TLS_SECRET "harbor-tls"
    tls_opts="--set expose.tls.certSource=secret --set expose.tls.secret.secretName=${HB_TLS_SECRET}"
  fi

  echo -e "\n  ${BOLD}스토리지 크기:${NC}"
  read_val "Registry PVC 크기" HB_REG_SIZE "50Gi"
  read_val "Database PVC 크기" HB_DB_SIZE "5Gi"
  read_val "Redis PVC 크기" HB_REDIS_SIZE "1Gi"
  read_val "Trivy PVC 크기" HB_TRIVY_SIZE "5Gi"

  # 설정 요약
  echo -e "\n${BOLD}${BLUE}──── 설치 구성 요약 ────${NC}"
  echo -e "  Namespace:     ${CYAN}${HARBOR_NS}${NC}"
  echo -e "  Release:       ${CYAN}${HB_RELEASE}${NC}"
  echo -e "  Expose 방식:   ${CYAN}${expose_type}${NC}"
  echo -e "  외부 URL:      ${CYAN}${ext_url}${NC}"
  echo -e "  Registry 크기: ${CYAN}${HB_REG_SIZE}${NC}"
  echo -e "  Database 크기: ${CYAN}${HB_DB_SIZE}${NC}"
  echo -e ""

  if ! confirm "위 설정으로 Harbor 를 설치하시겠습니까?"; then return; fi

  kubectl create namespace "$HARBOR_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  step "Harbor 설치 중 (3~8분 소요)..."
  # shellcheck disable=SC2086
  helm upgrade --install "$HB_RELEASE" harbor/harbor \
    --namespace "$HARBOR_NS" \
    --set expose.type="${expose_type}" \
    ${expose_opts} \
    ${tls_opts} \
    --set externalURL="${ext_url}" \
    --set harborAdminPassword="${HARBOR_PASS}" \
    --set persistence.persistentVolumeClaim.registry.size="${HB_REG_SIZE}" \
    --set persistence.persistentVolumeClaim.database.size="${HB_DB_SIZE}" \
    --set persistence.persistentVolumeClaim.redis.size="${HB_REDIS_SIZE}" \
    --set persistence.persistentVolumeClaim.trivy.size="${HB_TRIVY_SIZE}" \
    --set trivy.enabled=true \
    --wait --timeout 10m 2>&1 | tee -a "$LOG_FILE"

  HARBOR_URL="${ext_url}"
  HARBOR_USER="admin"
  mark_installed "Harbor (ns: ${HARBOR_NS}, url: ${ext_url})"
  success "Harbor 설치 완료!"
  show_result "$(kubectl get pods -n "$HARBOR_NS" 2>&1)"

  echo -e "${BOLD}접속 방법:${NC}"
  echo -e "  브라우저: ${CYAN}${ext_url}${NC}"
  echo -e "  사용자:   ${CYAN}admin${NC}"
  echo -e "  비밀번호: ${CYAN}(설정한 비밀번호)${NC}"
  echo ""
  echo -e "${BOLD}Docker 사용 준비:${NC}"
  if [[ -n "$HARBOR_INSECURE" ]]; then
    local harbor_host
    harbor_host=$(echo "$ext_url" | sed 's|https://||;s|http://||;s|/.*||')
    echo -e "  ${DIM}# 자체 서명 인증서 사용 시 Docker daemon 설정 필요${NC}"
    echo -e "  ${GREEN}sudo mkdir -p /etc/docker/certs.d/${harbor_host}${NC}"
    echo -e "  ${GREEN}kubectl get secret -n ${HARBOR_NS} ${HB_RELEASE}-ingress -o jsonpath='{.data.ca\\.crt}' | base64 -d > ca.crt${NC}"
    echo -e "  ${GREEN}sudo cp ca.crt /etc/docker/certs.d/${harbor_host}/ca.crt${NC}"
    echo -e ""
    echo -e "  ${DIM}# 또는 insecure registry 설정 (테스트용)${NC}"
    echo -e "  ${DIM}# /etc/docker/daemon.json 에 추가:${NC}"
    echo -e "  ${GREEN}{\"insecure-registries\": [\"${harbor_host}\"]}${NC}"
  fi
  echo ""
  echo -e "  ${GREEN}docker login ${ext_url}${NC}"
  tip "kubectl get svc -n ${HARBOR_NS}  # 서비스 목록 및 포트 확인"
  pause
}

# =============================================================================
# 2. Harbor 프로젝트 관리
# =============================================================================
addon_harbor_project() {
  clear
  box "2. Harbor 프로젝트 관리"

  echo -e "
${BOLD}Harbor 프로젝트란?${NC}
  이미지와 Helm 차트를 그룹으로 관리하는 단위입니다.
  프로젝트마다 ${CYAN}멤버 권한, 스캔 정책, 보관 정책${NC}을 독립 설정합니다.

${BOLD}프로젝트 구조 예시:${NC}
  ${DIM}harbor.example.com
  ├── library/          ← 기본 프로젝트 (Public)
  │   ├── nginx:1.25
  │   └── redis:7.0
  ├── backend/          ← 백엔드 팀 (Private)
  │   └── api-server:v2.1
  └── frontend/         ← 프론트엔드 팀 (Private)
      └── web-app:v3.0${NC}

${BOLD}프로젝트 접근 역할:${NC}
  • ${CYAN}Project Admin${NC}  — 설정 변경, 멤버 관리, Push/Pull
  • ${CYAN}Maintainer${NC}     — Push/Pull, 스캔, 태그 삭제
  • ${CYAN}Developer${NC}      — Push/Pull
  • ${CYAN}Guest${NC}          — Pull만 가능
"
  pause
  ensure_harbor_info

  # 현재 프로젝트 목록 조회
  step "현재 프로젝트 목록"
  local projects
  projects=$(harbor_api GET "/projects" 2>/dev/null || echo "[]")

  if echo "$projects" | python3 -m json.tool &>/dev/null 2>&1; then
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━ 프로젝트 목록 ━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "$projects" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(f'  {\"이름\":<20} {\"접근\":<10} {\"이미지 수\":<10}')
        print(f'  {\"-\"*20} {\"-\"*10} {\"-\"*10}')
        for p in data:
            name = p.get('name','')
            access = 'Public' if p.get('metadata',{}).get('public','false') == 'true' else 'Private'
            count = p.get('repo_count',0)
            print(f'  {name:<20} {access:<10} {count:<10}')
    else:
        print('  프로젝트 없음 또는 조회 실패')
except:
    print('  프로젝트 목록 조회 실패 (Harbor 접속 정보를 확인하세요)')
" 2>/dev/null || echo -e "  ${RED}프로젝트 목록 조회 실패${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  else
    warn "프로젝트 목록 조회 실패 — Harbor 접속 정보를 확인하세요."
    echo -e "  ${DIM}응답: ${projects}${NC}"
  fi

  if ! confirm "새 프로젝트를 생성하시겠습니까?"; then return; fi

  read_val "프로젝트 이름" PRJ_NAME ""
  if [[ -z "$PRJ_NAME" ]]; then warn "프로젝트 이름이 비어 있습니다."; return; fi

  local is_public="false"
  if confirm "Public 프로젝트로 생성하시겠습니까? (No → Private)"; then
    is_public="true"
  fi

  read_val "스토리지 할당량 (-1: 무제한)" PRJ_QUOTA "-1"

  step "프로젝트 생성: ${PRJ_NAME}"
  local result
  result=$(harbor_api POST "/projects" "{
    \"project_name\": \"${PRJ_NAME}\",
    \"metadata\": {\"public\": \"${is_public}\"},
    \"storage_limit\": ${PRJ_QUOTA}
  }" 2>&1)

  if [[ -z "$result" ]]; then
    success "프로젝트 '${PRJ_NAME}' 생성 완료!"
  else
    echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
  fi

  mark_installed "Harbor 프로젝트: ${PRJ_NAME}"

  local harbor_host
  harbor_host=$(echo "$HARBOR_URL" | sed 's|https://||;s|http://||;s|/.*||')
  echo -e "\n${BOLD}이미지 Push 방법:${NC}"
  echo -e "  ${GREEN}docker tag <이미지>:<태그> ${harbor_host}/${PRJ_NAME}/<이미지>:<태그>${NC}"
  echo -e "  ${GREEN}docker push ${harbor_host}/${PRJ_NAME}/<이미지>:<태그>${NC}"
  echo ""
  tip "Robot Account 생성: Harbor 웹 UI → 프로젝트 → Robot Accounts"
  pause
}

# =============================================================================
# 3. Docker 이미지 Push/Pull 실습
# =============================================================================
addon_docker_workflow() {
  clear
  box "3. Docker 이미지 Push/Pull 실습"

  echo -e "
${BOLD}워크플로우:${NC}
  ${DIM}┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ docker   │───→│ docker   │───→│ docker   │───→│ Harbor에  │
  │ pull     │    │ tag      │    │ push     │    │ 저장 완료  │
  │ (공개이미지)│    │ (주소변경) │    │ (업로드)  │    │          │
  └──────────┘    └──────────┘    └──────────┘    └──────────┘

                  ┌──────────┐
                  │ docker   │───→ Harbor에서 이미지를 가져옴
                  │ pull     │
                  │ (Harbor) │
                  └──────────┘${NC}
"
  pause

  if ! command -v docker &>/dev/null; then
    fail "Docker CLI 가 설치되어 있지 않습니다. Docker 설치 후 다시 시도하세요."
  fi

  ensure_harbor_info

  local harbor_host
  harbor_host=$(echo "$HARBOR_URL" | sed 's|https://||;s|http://||;s|/.*||')

  # Step 1: Docker Login
  step "1단계: Harbor 에 Docker 로그인"
  echo -e "  ${DIM}실행: docker login ${harbor_host}${NC}"
  if confirm "Harbor 에 Docker 로그인을 실행하시겠습니까?"; then
    echo "$HARBOR_PASS" | docker login "$harbor_host" -u "$HARBOR_USER" --password-stdin 2>&1 | tee -a "$LOG_FILE" && \
      success "Docker 로그인 성공!" || warn "로그인 실패 — 인증서 설정을 확인하세요."
  fi

  # Step 2: Pull sample image
  step "2단계: 샘플 이미지 Pull (nginx:alpine)"
  local sample_image="nginx:alpine"
  local harbor_image="${harbor_host}/library/nginx:alpine"

  echo -e "  ${DIM}실행: docker pull ${sample_image}${NC}"
  if confirm "nginx:alpine 이미지를 Pull 하시겠습니까?"; then
    docker pull "$sample_image" 2>&1 | tee -a "$LOG_FILE"
    success "이미지 Pull 완료!"
  fi

  # Step 3: Tag for Harbor
  step "3단계: Harbor 주소로 태그 변경"

  read_val "Harbor 프로젝트 이름" PUSH_PROJECT "library"
  harbor_image="${harbor_host}/${PUSH_PROJECT}/nginx:alpine"

  echo -e "\n  ${DIM}형식: <harbor-주소>/<프로젝트>/<이미지>:<태그>${NC}"
  echo -e "  ${GREEN}docker tag ${sample_image} ${harbor_image}${NC}"

  if confirm "태그를 변경하시겠습니까?"; then
    docker tag "$sample_image" "$harbor_image" 2>&1 | tee -a "$LOG_FILE"
    success "태그 변경 완료: ${harbor_image}"
  fi

  # Step 4: Push to Harbor
  step "4단계: Harbor 에 Push"
  echo -e "  ${GREEN}docker push ${harbor_image}${NC}"

  if confirm "이미지를 Harbor 에 Push 하시겠습니까?"; then
    docker push "$harbor_image" 2>&1 | tee -a "$LOG_FILE" && \
      success "이미지 Push 완료!" || warn "Push 실패 — 프로젝트 존재 여부, 권한, 인증서를 확인하세요."
  fi

  # Step 5: Verify via API
  step "5단계: Harbor API 로 이미지 확인"
  local repos
  repos=$(harbor_api GET "/projects/${PUSH_PROJECT}/repositories" 2>/dev/null || echo "")
  if [[ -n "$repos" ]]; then
    echo -e "${DIM}━━━━━━━━━━━━━━ ${PUSH_PROJECT} 프로젝트 이미지 목록 ━━━━━━━━━━━━━━${NC}"
    echo "$repos" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        for r in data:
            name = r.get('name','')
            count = r.get('artifact_count',0)
            print(f'  {name}  (artifacts: {count})')
except:
    print('  이미지 목록 조회 실패')
" 2>/dev/null || echo -e "  ${DIM}조회 실패${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi

  # Step 6: Pull back
  step "6단계: Harbor 에서 Pull (검증)"
  echo -e "  ${GREEN}docker pull ${harbor_image}${NC}"
  if confirm "Harbor 에서 이미지를 다시 Pull 하시겠습니까?"; then
    # 로컬 이미지 삭제 후 Pull
    docker rmi "$harbor_image" &>/dev/null || true
    docker pull "$harbor_image" 2>&1 | tee -a "$LOG_FILE" && \
      success "Harbor 에서 Pull 성공!" || warn "Pull 실패"
  fi

  mark_installed "Docker 워크플로우 실습 완료"

  echo -e "\n${BOLD}Kubernetes 에서 사용하려면:${NC}"
  echo -e "  ${GREEN}kubectl create secret docker-registry harbor-secret \\${NC}"
  echo -e "  ${GREEN}  --docker-server=${harbor_host} \\${NC}"
  echo -e "  ${GREEN}  --docker-username=${HARBOR_USER} \\${NC}"
  echo -e "  ${GREEN}  --docker-password=<비밀번호> -n default${NC}"
  echo ""
  show_yaml "apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: ${harbor_image}
  imagePullSecrets:
  - name: harbor-secret"

  tip "docker images | grep ${harbor_host}  # 로컬 Harbor 이미지 확인"
  pause
}

# =============================================================================
# 4. Trivy 취약점 스캔
# =============================================================================
addon_trivy_scan() {
  clear
  box "4. Trivy 취약점 스캔"

  echo -e "
${BOLD}Trivy란?${NC}
  Aqua Security 가 개발한 오픈소스 취약점 스캐너입니다.
  컨테이너 이미지, 파일시스템, K8s 클러스터의 보안 취약점을 검출합니다.

${BOLD}스캔 과정:${NC}
  ${DIM}┌──────────┐    ┌──────────────┐    ┌──────────────┐
  │ 컨테이너  │───→│ 패키지 분석   │───→│ CVE DB 조회  │
  │  이미지   │    │ (OS/언어별)   │    │ (NVD 등)     │
  └──────────┘    └──────────────┘    └──────┬───────┘
                                             │
                                      ┌──────▼───────┐
                                      │ 결과 리포트   │
                                      │ CRIT/HIGH/   │
                                      │ MED/LOW      │
                                      └──────────────┘${NC}

${BOLD}심각도 등급:${NC}
  ${RED}CRITICAL${NC}  — 원격 코드 실행 등 치명적 (CVSS 9.0~10.0)
  ${YELLOW}HIGH${NC}      — 권한 상승, 정보 유출 (CVSS 7.0~8.9)
  ${CYAN}MEDIUM${NC}    — 제한된 조건에서 악용 (CVSS 4.0~6.9)
  ${DIM}LOW${NC}       — 낮은 위험도 (CVSS 0.1~3.9)
"
  pause

  echo -e "\n  ${BOLD}스캔 방법 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Trivy CLI 로 로컬 이미지 스캔 (독립 실행)"
  echo -e "    ${CYAN}2)${NC} Harbor 통합 스캔 (Harbor API 사용)"
  echo -ne "  ${BOLD}선택 [1-2]:${NC} "
  read -r scan_choice

  case "${scan_choice:-1}" in
    1) trivy_cli_scan ;;
    2) trivy_harbor_scan ;;
    *) warn "잘못된 선택"; return ;;
  esac
}

trivy_cli_scan() {
  step "Trivy CLI 스캔"

  # Trivy 설치 확인
  if ! command -v trivy &>/dev/null; then
    warn "Trivy 가 설치되어 있지 않습니다."
    echo -e "\n  ${BOLD}설치 방법:${NC}"
    echo -e "    ${CYAN}1)${NC} Homebrew (macOS):  brew install trivy"
    echo -e "    ${CYAN}2)${NC} 스크립트 설치 (Linux)"
    echo -e "    ${CYAN}3)${NC} 설치하지 않고 돌아가기"
    echo -ne "  ${BOLD}선택 [1-3]:${NC} "
    read -r install_choice

    case "${install_choice:-3}" in
      1)
        step "Trivy 설치 중 (Homebrew)..."
        brew install trivy 2>&1 | tee -a "$LOG_FILE"
        ;;
      2)
        step "Trivy 설치 중 (스크립트)..."
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin 2>&1 | tee -a "$LOG_FILE"
        ;;
      *)
        return
        ;;
    esac
    success "Trivy 설치 완료: $(trivy version 2>/dev/null | head -1)"
  else
    success "Trivy — $(trivy version 2>/dev/null | head -1)"
  fi

  read_val "스캔할 이미지 (예: nginx:latest)" SCAN_IMAGE "nginx:latest"

  echo -e "\n  ${BOLD}심각도 필터:${NC}"
  echo -e "    ${CYAN}1)${NC} 모든 심각도"
  echo -e "    ${CYAN}2)${NC} CRITICAL, HIGH 만"
  echo -e "    ${CYAN}3)${NC} CRITICAL 만"
  echo -ne "  ${BOLD}선택 [1-3]:${NC} "
  read -r sev_choice

  local sev_flag=""
  case "${sev_choice:-1}" in
    2) sev_flag="--severity CRITICAL,HIGH" ;;
    3) sev_flag="--severity CRITICAL" ;;
  esac

  echo -e "\n  ${BOLD}출력 형식:${NC}"
  echo -e "    ${CYAN}1)${NC} 테이블 (터미널에서 보기 좋은 형식)"
  echo -e "    ${CYAN}2)${NC} JSON (CI/CD 연동용)"
  echo -ne "  ${BOLD}선택 [1-2]:${NC} "
  read -r fmt_choice

  local fmt_flag="--format table"
  local output_flag=""
  if [[ "${fmt_choice:-1}" == "2" ]]; then
    fmt_flag="--format json"
    read_val "출력 파일 경로" SCAN_OUTPUT "trivy-result.json"
    output_flag="--output ${SCAN_OUTPUT}"
  fi

  step "이미지 스캔 중: ${SCAN_IMAGE} ..."
  # shellcheck disable=SC2086
  trivy image ${sev_flag} ${fmt_flag} ${output_flag} "$SCAN_IMAGE" 2>&1 | tee -a "$LOG_FILE"

  mark_installed "Trivy CLI 스캔: ${SCAN_IMAGE}"
  success "스캔 완료!"

  if [[ -n "$output_flag" ]]; then
    echo -e "  결과 파일: ${CYAN}${SCAN_OUTPUT}${NC}"
  fi

  echo ""
  tip "trivy image --ignore-unfixed ${SCAN_IMAGE}  # 수정된 패치가 있는 취약점만 표시"
  tip "trivy fs ./  # 현재 디렉터리의 종속성 스캔"
  tip "trivy k8s --report summary  # 클러스터 전체 스캔"
  pause
}

trivy_harbor_scan() {
  step "Harbor 통합 스캔"
  ensure_harbor_info

  read_val "프로젝트 이름" SCAN_PROJECT "library"
  read_val "이미지 이름 (프로젝트 내)" SCAN_REPO "nginx"
  read_val "태그 또는 다이제스트" SCAN_TAG "latest"

  step "스캔 트리거: ${SCAN_PROJECT}/${SCAN_REPO}:${SCAN_TAG}"
  local scan_result
  scan_result=$(harbor_api POST "/projects/${SCAN_PROJECT}/repositories/${SCAN_REPO}/artifacts/${SCAN_TAG}/scan" 2>&1)

  if [[ -z "$scan_result" ]]; then
    success "스캔 시작됨! (비동기 — 완료까지 1~3분 소요)"
  else
    echo "$scan_result" | python3 -m json.tool 2>/dev/null || echo "$scan_result"
  fi

  if confirm "스캔 결과를 조회하시겠습니까? (스캔 완료 후)"; then
    echo -e "  ${DIM}스캔이 완료될 때까지 잠시 대기합니다...${NC}"
    local retry=0
    while [[ $retry -lt 12 ]]; do
      sleep 5
      local result
      result=$(harbor_api GET "/projects/${SCAN_PROJECT}/repositories/${SCAN_REPO}/artifacts/${SCAN_TAG}?with_scan_overview=true" 2>/dev/null)

      local scan_status
      scan_status=$(echo "$result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    overview = data.get('scan_overview', {})
    for key, val in overview.items():
        print(val.get('scan_status', 'Unknown'))
        break
    else:
        print('NotStarted')
except:
    print('Error')
" 2>/dev/null || echo "Error")

      if [[ "$scan_status" == "Success" ]]; then
        echo ""
        echo "$result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    overview = data.get('scan_overview', {})
    for key, val in overview.items():
        summary = val.get('summary', {}).get('summary', {})
        total = val.get('summary', {}).get('total', 0)
        print(f'  Total vulnerabilities: {total}')
        for sev, count in sorted(summary.items()):
            print(f'    {sev}: {count}')
        break
except Exception as e:
    print(f'  결과 파싱 실패: {e}')
" 2>/dev/null
        success "스캔 결과 조회 완료!"
        break
      elif [[ "$scan_status" == "Error" && $retry -gt 3 ]]; then
        warn "스캔 결과 조회 실패"
        break
      else
        echo -ne "  ${DIM}스캔 진행 중... (${retry}/12)${NC}\r"
      fi
      retry=$((retry + 1))
    done

    if [[ $retry -ge 12 ]]; then
      warn "스캔 시간 초과. Harbor 웹 UI 에서 결과를 확인하세요."
    fi
  fi

  mark_installed "Harbor 스캔: ${SCAN_PROJECT}/${SCAN_REPO}:${SCAN_TAG}"

  echo ""
  echo -e "${BOLD}웹 UI 에서 상세 결과 확인:${NC}"
  echo -e "  ${CYAN}${HARBOR_URL}${NC} → Projects → ${SCAN_PROJECT} → ${SCAN_REPO} → ${SCAN_TAG}"
  tip "Push 시 자동 스캔: 프로젝트 → Configuration → 'Automatically scan images on push' 활성화"
  pause
}

# =============================================================================
# 5. Helm 차트 관리
# =============================================================================
addon_helm_registry() {
  clear
  box "5. Helm 차트 관리 — Harbor OCI 저장소"

  echo -e "
${BOLD}Harbor를 Helm 차트 저장소로 사용하기${NC}
  Harbor 2.x 부터 ${CYAN}OCI (Open Container Initiative)${NC} 기반
  Helm 차트 저장을 지원합니다. 이미지와 동일한 방식으로 차트를 관리합니다.

${BOLD}OCI 방식 워크플로우:${NC}
  ${DIM}helm create my-chart
       ↓
  helm package my-chart/
       ↓ (my-chart-0.1.0.tgz)
  helm push my-chart-0.1.0.tgz oci://harbor.example.com/library
       ↓
  helm install my-release oci://harbor.example.com/library/my-chart --version 0.1.0${NC}

${BOLD}OCI vs ChartMuseum:${NC}
  ┌──────────────┬────────────────┬──────────────────┐
  │     항목     │  OCI (권장)     │  ChartMuseum     │
  ├──────────────┼────────────────┼──────────────────┤
  │ Helm 버전    │  3.8 이상       │  3.x             │
  │ 명령어       │  helm push/pull│  helm repo add   │
  │ 추세         │  표준화 진행    │  점차 deprecated  │
  └──────────────┴────────────────┴──────────────────┘
"
  pause
  ensure_harbor_info

  local harbor_host
  harbor_host=$(echo "$HARBOR_URL" | sed 's|https://||;s|http://||;s|/.*||')

  # Step 1: OCI 로그인
  step "1단계: Helm OCI 레지스트리 로그인"
  echo -e "  ${GREEN}helm registry login ${harbor_host}${NC}"
  if confirm "Helm 레지스트리에 로그인하시겠습니까?"; then
    echo "$HARBOR_PASS" | helm registry login "$harbor_host" -u "$HARBOR_USER" --password-stdin 2>&1 | tee -a "$LOG_FILE" && \
      success "Helm 레지스트리 로그인 성공!" || warn "로그인 실패 — 인증서 설정을 확인하세요."
  fi

  # Step 2: 샘플 차트 생성
  step "2단계: 샘플 Helm 차트 생성"
  local chart_dir="/tmp/harbor-helm-demo"
  local chart_name="demo-chart"

  if confirm "샘플 차트 '${chart_name}' 를 생성하시겠습니까?"; then
    rm -rf "${chart_dir}" &>/dev/null || true
    mkdir -p "${chart_dir}"
    cd "${chart_dir}"
    helm create "$chart_name" 2>&1 | tee -a "$LOG_FILE"
    success "차트 생성: ${chart_dir}/${chart_name}"
    echo ""
    echo -e "  ${DIM}차트 구조:${NC}"
    find "${chart_dir}/${chart_name}" -maxdepth 2 -print 2>/dev/null | head -20 | while read -r line; do
      echo -e "  ${DIM}${line}${NC}"
    done
  fi

  # Step 3: 패키징
  step "3단계: 차트 패키징"
  if confirm "차트를 패키징하시겠습니까?"; then
    cd "${chart_dir}"
    helm package "$chart_name" 2>&1 | tee -a "$LOG_FILE"
    local tgz_file
    tgz_file=$(ls ${chart_name}-*.tgz 2>/dev/null | head -1)
    if [[ -n "$tgz_file" ]]; then
      success "패키지 생성: ${tgz_file}"
    fi
  fi

  # Step 4: Push
  step "4단계: Harbor 에 차트 Push"
  read_val "대상 프로젝트" CHART_PROJECT "library"
  local tgz_file
  tgz_file=$(ls "${chart_dir}"/${chart_name}-*.tgz 2>/dev/null | head -1)

  if [[ -n "$tgz_file" ]]; then
    echo -e "  ${GREEN}helm push ${tgz_file} oci://${harbor_host}/${CHART_PROJECT}${NC}"
    if confirm "차트를 Harbor 에 Push 하시겠습니까?"; then
      local push_flags=""
      [[ -n "$HARBOR_INSECURE" ]] && push_flags="--insecure-skip-tls-verify"
      # shellcheck disable=SC2086
      helm push "$tgz_file" "oci://${harbor_host}/${CHART_PROJECT}" ${push_flags} 2>&1 | tee -a "$LOG_FILE" && \
        success "차트 Push 완료!" || warn "Push 실패"
    fi
  else
    warn "패키지 파일을 찾을 수 없습니다."
  fi

  # Step 5: Pull & Install
  step "5단계: Harbor 에서 차트 Pull / 설치"
  echo -e "  ${BOLD}Pull:${NC}"
  echo -e "  ${GREEN}helm pull oci://${harbor_host}/${CHART_PROJECT}/${chart_name} --version 0.1.0${NC}"
  echo ""
  echo -e "  ${BOLD}직접 설치:${NC}"
  echo -e "  ${GREEN}helm install my-release oci://${harbor_host}/${CHART_PROJECT}/${chart_name} --version 0.1.0${NC}"

  mark_installed "Helm 차트 관리 실습 완료"

  # 정리
  if confirm "임시 차트 디렉터리를 삭제하시겠습니까?"; then
    rm -rf "${chart_dir}"
    log "임시 디렉터리 삭제: ${chart_dir}"
  fi

  cd - &>/dev/null || true
  tip "helm registry logout ${harbor_host}  # 로그아웃"
  pause
}

# =============================================================================
# 6. 이미지 보안 설정
# =============================================================================
addon_security() {
  clear
  box "6. 이미지 보안 설정"

  echo -e "
${BOLD}Harbor 보안 기능 개요:${NC}
  ${DIM}┌─────────────────────────────────────────────────────────┐
  │                     보안 계층                             │
  │                                                          │
  │  1. 취약점 자동 스캔 — Push 시 Trivy 로 즉시 스캔         │
  │  2. 배포 차단 정책   — CRITICAL 이미지 Pull 차단           │
  │  3. CVE 허용 목록    — 특정 CVE 를 예외 처리               │
  │  4. 이미지 보관 정책 — 오래된 태그 자동 삭제               │
  │  5. 이미지 서명      — Cosign 기반 무결성 검증             │
  └─────────────────────────────────────────────────────────┘${NC}
"
  pause
  ensure_harbor_info

  echo -e "\n  ${BOLD}설정 항목 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Push 시 자동 스캔 활성화"
  echo -e "    ${CYAN}2)${NC} 취약 이미지 배포 차단 설정"
  echo -e "    ${CYAN}3)${NC} 프로젝트 보안 현황 조회"
  echo -e "    ${CYAN}4)${NC} 모두 돌아가기"
  echo -ne "  ${BOLD}선택 [1-4]:${NC} "
  read -r sec_choice

  case "${sec_choice:-4}" in
    1)
      step "Push 시 자동 스캔 활성화"
      read_val "프로젝트 이름" SEC_PROJECT "library"

      # 프로젝트 ID 조회
      local project_info
      project_info=$(harbor_api GET "/projects?name=${SEC_PROJECT}" 2>/dev/null)
      local project_id
      project_id=$(echo "$project_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(data[0].get('project_id', ''))
except:
    pass
" 2>/dev/null)

      if [[ -z "$project_id" ]]; then
        warn "프로젝트 '${SEC_PROJECT}' 를 찾을 수 없습니다."
        pause; return
      fi

      harbor_api PUT "/projects/${project_id}" "{\"metadata\":{\"auto_scan\":\"true\"}}" &>/dev/null
      success "프로젝트 '${SEC_PROJECT}' — Push 시 자동 스캔 활성화 완료!"
      mark_installed "보안 설정: ${SEC_PROJECT} 자동 스캔"
      ;;
    2)
      step "취약 이미지 배포 차단"
      read_val "프로젝트 이름" SEC_PROJECT "library"

      local project_info
      project_info=$(harbor_api GET "/projects?name=${SEC_PROJECT}" 2>/dev/null)
      local project_id
      project_id=$(echo "$project_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(data[0].get('project_id', ''))
except:
    pass
" 2>/dev/null)

      if [[ -z "$project_id" ]]; then
        warn "프로젝트 '${SEC_PROJECT}' 를 찾을 수 없습니다."
        pause; return
      fi

      echo -e "\n  ${BOLD}차단할 최소 심각도:${NC}"
      echo -e "    ${CYAN}1)${NC} Critical"
      echo -e "    ${CYAN}2)${NC} High"
      echo -e "    ${CYAN}3)${NC} Medium"
      echo -e "    ${CYAN}4)${NC} Low"
      echo -ne "  ${BOLD}선택 [1-4]:${NC} "
      read -r block_level

      local severity="critical"
      case "${block_level:-1}" in
        1) severity="critical" ;;
        2) severity="high" ;;
        3) severity="medium" ;;
        4) severity="low" ;;
      esac

      harbor_api PUT "/projects/${project_id}" \
        "{\"metadata\":{\"prevent_vul\":\"true\",\"severity\":\"${severity}\"}}" &>/dev/null
      success "프로젝트 '${SEC_PROJECT}' — ${severity} 이상 취약점이 있는 이미지 Pull 차단 설정 완료!"
      mark_installed "보안 설정: ${SEC_PROJECT} 배포 차단 (${severity})"
      ;;
    3)
      step "프로젝트 보안 현황 조회"
      read_val "프로젝트 이름" SEC_PROJECT "library"

      local project_info
      project_info=$(harbor_api GET "/projects?name=${SEC_PROJECT}" 2>/dev/null)

      echo "$project_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        p = data[0]
        meta = p.get('metadata', {})
        print(f'  프로젝트:     {p.get(\"name\",\"\")}')
        print(f'  접근 수준:    {\"Public\" if meta.get(\"public\",\"false\") == \"true\" else \"Private\"}')
        print(f'  자동 스캔:    {\"✔ 활성\" if meta.get(\"auto_scan\",\"false\") == \"true\" else \"✘ 비활성\"}')
        print(f'  배포 차단:    {\"✔ 활성\" if meta.get(\"prevent_vul\",\"false\") == \"true\" else \"✘ 비활성\"}')
        print(f'  차단 심각도:  {meta.get(\"severity\",\"미설정\")}')
        print(f'  이미지 수:    {p.get(\"repo_count\",0)}')
except Exception as e:
    print(f'  조회 실패: {e}')
" 2>/dev/null || warn "프로젝트 정보 조회 실패"
      ;;
    *)
      return
      ;;
  esac
  pause
}

# =============================================================================
# 7. Harbor 삭제
# =============================================================================
addon_harbor_uninstall() {
  clear
  box "7. Harbor 삭제"

  echo -e "
${RED}${BOLD}⚠  경고: Harbor 를 삭제하면 모든 이미지와 데이터가 삭제됩니다!${NC}

${BOLD}삭제 과정:${NC}
  ${DIM}1. Helm Release 삭제 (모든 Pod/Service/Deployment 제거)
  2. PVC 삭제 (영구 볼륨 데이터 삭제)
  3. Namespace 삭제
  4. Docker 인증 정보 정리${NC}
"

  if [[ -z "$HARBOR_NS" ]]; then
    read_val "Harbor Namespace" HARBOR_NS "harbor"
  fi

  echo -e "\n${BOLD}현재 Harbor 상태:${NC}"
  kubectl get pods -n "$HARBOR_NS" 2>/dev/null || echo -e "  ${DIM}Namespace '${HARBOR_NS}' 에 리소스 없음${NC}"

  echo ""
  if ! confirm "${RED}정말로 Harbor 를 삭제하시겠습니까? (되돌릴 수 없습니다)${NC}"; then
    log "삭제 취소"
    return
  fi

  # 이중 확인
  echo -ne "  ${RED}삭제 확인을 위해 Namespace 이름을 입력하세요:${NC} "
  read -r confirm_ns
  if [[ "$confirm_ns" != "$HARBOR_NS" ]]; then
    warn "입력이 일치하지 않습니다. 삭제를 취소합니다."
    return
  fi

  # Helm Release 삭제
  step "Helm Release 삭제"
  local releases
  releases=$(helm list -n "$HARBOR_NS" -q 2>/dev/null)
  for rel in $releases; do
    log "  삭제 중: ${rel}"
    helm uninstall "$rel" -n "$HARBOR_NS" 2>&1 | tee -a "$LOG_FILE" || true
  done
  success "Helm Release 삭제 완료"

  # PVC 삭제
  step "PVC 삭제"
  if confirm "PVC (영구 볼륨) 도 삭제하시겠습니까?"; then
    kubectl delete pvc --all -n "$HARBOR_NS" 2>&1 | tee -a "$LOG_FILE" || true
    success "PVC 삭제 완료"
  fi

  # Namespace 삭제
  step "Namespace 삭제"
  kubectl delete namespace "$HARBOR_NS" 2>&1 | tee -a "$LOG_FILE" || true
  success "Namespace '${HARBOR_NS}' 삭제 완료"

  # Docker 인증 정보 정리
  if command -v docker &>/dev/null; then
    step "Docker 인증 정보 정리"
    if [[ -n "$HARBOR_URL" ]]; then
      local harbor_host
      harbor_host=$(echo "$HARBOR_URL" | sed 's|https://||;s|http://||;s|/.*||')
      docker logout "$harbor_host" 2>/dev/null && \
        log "Docker 로그아웃: ${harbor_host}" || true
    fi
  fi

  # 전역 변수 초기화
  HARBOR_URL=""
  HARBOR_PASS=""

  success "Harbor 삭제 완료!"
  pause
}

# =============================================================================
# 메인 메뉴
# =============================================================================
main_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Harbor & Trivy — 프라이빗 레지스트리 실습 스크립트        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ -n "$HARBOR_URL" ]]; then
      echo -e "  ${DIM}Harbor URL: ${HARBOR_URL}${NC}"
      echo -e "  ${DIM}Namespace:  ${HARBOR_NS}${NC}"
      echo ""
    fi

    if [[ ${#INSTALLED[@]} -gt 0 ]]; then
      echo -e "  ${GREEN}완료된 항목: ${#INSTALLED[@]}개${NC}"
      echo ""
    fi

    echo -e "  ${BOLD}── 메뉴 ─────────────────────────────────────────────────${NC}"
    echo -e "    ${CYAN}1)${NC} Harbor 설치             — Helm 으로 프라이빗 레지스트리 배포"
    echo -e "    ${CYAN}2)${NC} Harbor 프로젝트 관리     — 프로젝트 생성/조회"
    echo -e "    ${CYAN}3)${NC} Docker Push/Pull 실습   — 이미지 업로드/다운로드 워크플로우"
    echo -e "    ${CYAN}4)${NC} Trivy 취약점 스캔       — CLI 스캔 또는 Harbor 통합 스캔"
    echo -e "    ${CYAN}5)${NC} Helm 차트 관리          — OCI 기반 차트 Push/Pull"
    echo -e "    ${CYAN}6)${NC} 이미지 보안 설정        — 자동 스캔, 배포 차단, 보안 현황"
    echo -e "    ${CYAN}7)${NC} Harbor 삭제             — 완전 삭제 (데이터 포함)"
    echo ""
    echo -e "    ${CYAN}q)${NC} 종료"
    echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -ne "  ${BOLD}선택 [1-7, q]:${NC} "
    read -r choice

    case "$choice" in
      1) addon_harbor ;;
      2) addon_harbor_project ;;
      3) addon_docker_workflow ;;
      4) addon_trivy_scan ;;
      5) addon_helm_registry ;;
      6) addon_security ;;
      7) addon_harbor_uninstall ;;
      q|Q)
        clear
        echo ""
        box "Harbor & Trivy 실습을 종료합니다"
        echo ""
        if [[ ${#INSTALLED[@]} -gt 0 ]]; then
          echo -e "  ${BOLD}이번 세션에서 수행한 항목:${NC}"
          for item in "${INSTALLED[@]}"; do
            echo -e "    ${GREEN}✔${NC} ${item}"
          done
          echo ""
        fi
        echo -e "  ${DIM}로그 파일: ${LOG_FILE}${NC}"
        echo -e "  ${DIM}교육 자료: harbor-registry.md${NC}"
        echo ""
        tip "harbor-registry.md 를 참고하여 심화 학습을 진행하세요."
        echo ""
        exit 0
        ;;
      *)
        warn "잘못된 선택입니다. 1~7 또는 q 를 입력하세요."
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
