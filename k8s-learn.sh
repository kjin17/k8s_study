#!/usr/bin/env bash
# =============================================================================
# Kubernetes 오브젝트 학습 스크립트 (교육용 인터랙티브)
# 대상: Kubernetes 입문자
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

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
label()   { echo -e "${CYAN}${BOLD}$*${NC}"; }
step()    { echo -e "\n${BOLD}${BLUE}▶  $*${NC}"; }
success() { echo -e "${GREEN}${BOLD}✔  $*${NC}"; }
tip()     { echo -e "${MAGENTA}${BOLD}💡 TIP:${NC} ${MAGENTA}$*${NC}"; }

# 박스 출력
box() {
  local text="$1"
  local len=${#text}
  local line
  printf -v line '%*s' "$((len + 4))" ''
  echo -e "${CYAN}${BOLD}┌${line// /─}┐${NC}"
  echo -e "${CYAN}${BOLD}│  ${text}  │${NC}"
  echo -e "${CYAN}${BOLD}└${line// /─}┘${NC}"
}

# YAML 미리보기
show_yaml() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━ 생성될 YAML ━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}$1${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# kubectl 실행 결과 출력
kube_result() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━━ 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
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
  local prompt="$1"
  local var="$2"
  local default="${3:-}"
  local val

  if [[ -n "$default" ]]; then
    echo -ne "${BOLD}  $prompt${NC} ${DIM}[기본값: $default]${NC}: "
  else
    echo -ne "${BOLD}  $prompt${NC}: "
  fi
  read -r val
  printf -v "$var" '%s' "${val:-$default}"
}

# 세션 중 생성된 오브젝트 추적
SESSION_LOG=()
log_created() { SESSION_LOG+=("$1"); }

# -----------------------------------------------------------------------------
# kubectl 확인
# -----------------------------------------------------------------------------
check_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}${BOLD}오류: kubectl 명령어를 찾을 수 없습니다.${NC}"
    echo ""
    echo "kubectl이 설치되어 있고 kubeconfig가 설정된 환경에서 실행하세요."
    echo "  Master 노드에서 직접 실행하거나"
    echo "  로컬에서 ~/.kube/config 설정 후 실행하세요."
    exit 1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}${BOLD}오류: Kubernetes 클러스터에 연결할 수 없습니다.${NC}"
    echo "클러스터 상태 및 kubeconfig를 확인하세요."
    exit 1
  fi
}

# 기본 Namespace 변수 (전역)
CURRENT_NS="default"

# =============================================================================
# 1. Namespace
# =============================================================================
module_namespace() {
  clear
  box "1. Namespace — 클러스터 내 가상 분리 공간"

  echo -e "
${BOLD}Namespace란?${NC}
  하나의 쿠버네티스 클러스터를 여러 팀/프로젝트가 공유할 때
  서로 간섭하지 않도록 ${CYAN}논리적으로 분리${NC}하는 단위입니다.

${BOLD}구조 예시:${NC}
  ${DIM}┌─────────────────── Kubernetes Cluster ───────────────────┐
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
  │  │  default     │  │  dev         │  │  production  │   │
  │  │  (기본)       │  │  (개발팀)     │  │  (운영팀)     │   │
  │  └──────────────┘  └──────────────┘  └──────────────┘   │
  └──────────────────────────────────────────────────────────┘${NC}

${BOLD}핵심 특징:${NC}
  • 리소스 이름은 같은 Namespace 안에서만 유일하면 됩니다
  • ResourceQuota로 Namespace별 리소스 사용량 제한 가능
  • 기본 Namespace: ${CYAN}default, kube-system, kube-public${NC}

${BOLD}자주 쓰는 명령어:${NC}
  ${GREEN}kubectl get namespaces${NC}               # 목록 조회
  ${GREEN}kubectl create namespace <이름>${NC}       # 생성
  ${GREEN}kubectl config set-context --current --namespace=<이름>${NC}  # 기본 NS 변경
"
  pause

  step "현재 Namespace 목록"
  kube_result "$(kubectl get namespaces 2>&1)"

  if ! confirm "새 Namespace를 생성하시겠습니까?"; then return; fi

  read_val "Namespace 이름" NS_NAME "study"
  read_val "설명 (레이블용)" NS_LABEL "kubernetes-study"

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS_NAME}
  labels:
    purpose: ${NS_LABEL}
EOF
)
  show_yaml "$yaml"

  if confirm "위 Namespace를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    CURRENT_NS="$NS_NAME"
    log_created "Namespace/${NS_NAME}"
    success "Namespace '${NS_NAME}' 생성 완료! (이후 실습은 이 Namespace에서 진행)"
    kube_result "$(kubectl get namespace "$NS_NAME" -o wide 2>&1)"
    tip "kubectl get ns   # 생성된 Namespace 확인"
  fi
  pause
}

# =============================================================================
# 2. Pod
# =============================================================================
module_pod() {
  clear
  box "2. Pod — 쿠버네티스의 가장 작은 배포 단위"

  echo -e "
${BOLD}Pod란?${NC}
  쿠버네티스에서 컨테이너를 실행하는 ${CYAN}가장 기본적인 단위${NC}입니다.
  하나 이상의 컨테이너를 묶어서 같은 네트워크와 스토리지를 공유합니다.

${BOLD}구조:${NC}
  ${DIM}┌─────────────── Pod ────────────────┐
  │  ┌─────────────┐  ┌─────────────┐  │
  │  │  Container1 │  │  Container2 │  │  ← 같은 IP 공유
  │  │  (nginx)    │  │  (sidecar)  │  │
  │  └─────────────┘  └─────────────┘  │
  │         공유 스토리지 (Volume)        │
  └────────────────────────────────────┘${NC}

${BOLD}핵심 특징:${NC}
  • Pod는 ${RED}일시적(Ephemeral)${NC} — 죽으면 재생성되지 않음
  • 실무에서는 Pod를 직접 쓰기보단 ${CYAN}Deployment${NC}로 관리
  • 같은 Pod 안 컨테이너는 ${CYAN}localhost${NC}로 통신 가능

${BOLD}Pod 생명주기:${NC}
  ${DIM}Pending → Running → Succeeded/Failed${NC}
"
  pause

  step "현재 Pod 목록"
  kube_result "$(kubectl get pods -n "$CURRENT_NS" 2>&1)"

  if ! confirm "새 Pod를 생성하시겠습니까?"; then return; fi

  read_val "Pod 이름" POD_NAME "my-pod"
  echo -e "  ${BOLD}컨테이너 이미지 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} nginx:latest   (웹 서버)"
  echo -e "    ${CYAN}2)${NC} httpd:latest   (Apache)"
  echo -e "    ${CYAN}3)${NC} busybox:latest (경량 Linux)"
  echo -ne "    선택 [1-3]: "
  read -r img_choice
  case "$img_choice" in
    2) POD_IMAGE="httpd:latest";   POD_PORT=80 ;;
    3) POD_IMAGE="busybox:latest"; POD_PORT="" ;;
    *) POD_IMAGE="nginx:latest";   POD_PORT=80 ;;
  esac

  local port_section=""
  [[ -n "$POD_PORT" ]] && port_section="
        ports:
        - containerPort: ${POD_PORT}"

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${CURRENT_NS}
  labels:
    app: ${POD_NAME}
    managed-by: k8s-learn
spec:
  containers:
  - name: main
    image: ${POD_IMAGE}${port_section}
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF
)
  show_yaml "$yaml"

  if confirm "위 Pod를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "Pod/${CURRENT_NS}/${POD_NAME}"
    success "Pod '${POD_NAME}' 생성 완료!"
    echo ""
    info "Pod가 Running 상태가 될 때까지 대기 중..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" \
      -n "$CURRENT_NS" --timeout=60s 2>/dev/null || true
    kube_result "$(kubectl get pod "$POD_NAME" -n "$CURRENT_NS" -o wide 2>&1)"
    tip "kubectl describe pod ${POD_NAME} -n ${CURRENT_NS}   # 상세 정보"
    tip "kubectl logs ${POD_NAME} -n ${CURRENT_NS}           # 로그 확인"
    tip "kubectl exec -it ${POD_NAME} -n ${CURRENT_NS} -- /bin/sh   # 컨테이너 접속"
  fi
  pause
}

# =============================================================================
# 3. Deployment
# =============================================================================
module_deployment() {
  clear
  box "3. Deployment — Pod를 안정적으로 관리하는 컨트롤러"

  echo -e "
${BOLD}Deployment란?${NC}
  Pod의 ${CYAN}개수(replicas)를 유지${NC}하고, ${CYAN}롤링 업데이트${NC}와
  ${CYAN}롤백${NC}을 자동으로 처리해주는 오브젝트입니다.

${BOLD}Deployment → ReplicaSet → Pod 관계:${NC}
  ${DIM}Deployment
      └── ReplicaSet (버전 관리)
              ├── Pod-1  (Running)
              ├── Pod-2  (Running)
              └── Pod-3  (Running)${NC}

${BOLD}롤링 업데이트:${NC}
  ${DIM}구버전: [v1][v1][v1]
  업데이트: [v2][v1][v1] → [v2][v2][v1] → [v2][v2][v2]
  장애 없이 순차 교체!${NC}

${BOLD}핵심 특징:${NC}
  • ${CYAN}replicas${NC}  : 유지할 Pod 수 (노드 장애 시 자동 재생성)
  • ${CYAN}strategy${NC}  : RollingUpdate (무중단) / Recreate (전체 재시작)
  • ${CYAN}rollback${NC}  : kubectl rollout undo 로 이전 버전 복구
"
  pause

  if ! confirm "Deployment를 생성하시겠습니까?"; then return; fi

  read_val "Deployment 이름" DEPLOY_NAME "my-app"
  read_val "컨테이너 이미지" DEPLOY_IMAGE "nginx:1.25"
  read_val "복제본 수 (replicas)" DEPLOY_REPLICAS "3"
  read_val "컨테이너 포트" DEPLOY_PORT "80"

  local yaml
  yaml=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY_NAME}
  namespace: ${CURRENT_NS}
  labels:
    app: ${DEPLOY_NAME}
spec:
  replicas: ${DEPLOY_REPLICAS}
  selector:
    matchLabels:
      app: ${DEPLOY_NAME}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 업데이트 중 최대 초과 생성 Pod 수
      maxUnavailable: 0  # 업데이트 중 최대 중단 Pod 수
  template:
    metadata:
      labels:
        app: ${DEPLOY_NAME}
    spec:
      containers:
      - name: ${DEPLOY_NAME}
        image: ${DEPLOY_IMAGE}
        ports:
        - containerPort: ${DEPLOY_PORT}
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /
            port: ${DEPLOY_PORT}
          initialDelaySeconds: 5
          periodSeconds: 10
EOF
)
  show_yaml "$yaml"

  if confirm "위 Deployment를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "Deployment/${CURRENT_NS}/${DEPLOY_NAME}"
    success "Deployment '${DEPLOY_NAME}' 생성 완료!"
    info "Pod 기동 대기 중..."
    kubectl rollout status deployment/"$DEPLOY_NAME" \
      -n "$CURRENT_NS" --timeout=90s 2>/dev/null || true
    kube_result "$(kubectl get deployment "$DEPLOY_NAME" -n "$CURRENT_NS" 2>&1)
$(kubectl get pods -n "$CURRENT_NS" -l app="$DEPLOY_NAME" 2>&1)"
    tip "kubectl rollout history deployment/${DEPLOY_NAME} -n ${CURRENT_NS}   # 업데이트 이력"
    tip "kubectl rollout undo deployment/${DEPLOY_NAME} -n ${CURRENT_NS}      # 롤백"
    tip "kubectl scale deployment ${DEPLOY_NAME} --replicas=5 -n ${CURRENT_NS}  # 스케일"
  fi
  pause
}

# =============================================================================
# 4. Service
# =============================================================================
module_service() {
  clear
  box "4. Service — Pod에 안정적인 네트워크 엔드포인트 제공"

  echo -e "
${BOLD}Service란?${NC}
  Pod의 IP는 재시작마다 바뀌지만, Service는 ${CYAN}고정된 IP(ClusterIP)${NC}와
  DNS 이름을 제공하여 안정적으로 Pod에 접근할 수 있게 합니다.

${BOLD}Service 타입 비교:${NC}
  ${DIM}┌──────────────┬──────────────────────────────────────────┐
  │ ClusterIP    │ 클러스터 내부에서만 접근 가능 (기본값)      │
  │ NodePort     │ 모든 노드의 특정 포트로 외부 접근 가능      │
  │ LoadBalancer │ 클라우드 LB 생성, 외부 IP 자동 할당        │
  │ ExternalName │ 외부 DNS 이름으로 라우팅                   │
  └──────────────┴──────────────────────────────────────────────┘${NC}

${BOLD}ClusterIP 동작:${NC}
  ${DIM}클라이언트 → Service(고정IP:80) → [Pod1, Pod2, Pod3] (로드밸런싱)${NC}

${BOLD}NodePort 동작:${NC}
  ${DIM}외부 사용자 → NodeIP:30080 → Service → Pod${NC}
"
  pause

  if ! confirm "Service를 생성하시겠습니까?"; then return; fi

  read_val "Service 이름" SVC_NAME "my-service"
  read_val "대상 Deployment/Pod의 app 레이블" SVC_SELECTOR "my-app"
  read_val "서비스 포트" SVC_PORT "80"
  read_val "대상 컨테이너 포트" SVC_TARGET_PORT "80"

  echo -e "\n  ${BOLD}Service 타입 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} ClusterIP   — 클러스터 내부 전용"
  echo -e "    ${CYAN}2)${NC} NodePort    — 노드 포트로 외부 접근"
  echo -e "    ${CYAN}3)${NC} LoadBalancer — 클라우드 환경 외부 노출"
  echo -ne "    선택 [1-3]: "
  read -r svc_type_choice

  local SVC_TYPE nodeport_section=""
  case "$svc_type_choice" in
    2)
      SVC_TYPE="NodePort"
      read_val "NodePort 번호 (30000-32767)" NP_PORT "30080"
      nodeport_section="      nodePort: ${NP_PORT}"
      ;;
    3) SVC_TYPE="LoadBalancer" ;;
    *) SVC_TYPE="ClusterIP" ;;
  esac

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SVC_NAME}
  namespace: ${CURRENT_NS}
  labels:
    app: ${SVC_SELECTOR}
spec:
  type: ${SVC_TYPE}
  selector:
    app: ${SVC_SELECTOR}   # 이 레이블을 가진 Pod로 트래픽 전달
  ports:
  - protocol: TCP
    port: ${SVC_PORT}            # Service 포트
    targetPort: ${SVC_TARGET_PORT}  # Pod 컨테이너 포트
${nodeport_section}
EOF
)
  show_yaml "$yaml"

  if confirm "위 Service를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "Service/${CURRENT_NS}/${SVC_NAME}"
    success "Service '${SVC_NAME}' (${SVC_TYPE}) 생성 완료!"
    kube_result "$(kubectl get service "$SVC_NAME" -n "$CURRENT_NS" -o wide 2>&1)"
    if [[ "$SVC_TYPE" == "NodePort" ]]; then
      tip "노드 IP:${NP_PORT} 로 외부에서 접근 가능합니다"
    fi
    tip "kubectl describe svc ${SVC_NAME} -n ${CURRENT_NS}   # 엔드포인트 확인"
  fi
  pause
}

# =============================================================================
# 5. ConfigMap
# =============================================================================
module_configmap() {
  clear
  box "5. ConfigMap — 환경설정을 코드와 분리"

  echo -e "
${BOLD}ConfigMap이란?${NC}
  애플리케이션의 ${CYAN}설정 데이터(비밀 아님)${NC}를 Pod와 분리하여 관리합니다.
  이미지를 다시 빌드하지 않고도 설정을 변경할 수 있습니다.

${BOLD}사용 방법 두 가지:${NC}
  ${DIM}① 환경변수로 주입          ② 파일(볼륨)로 마운트
  ┌────────────────┐          ┌────────────────┐
  │ Pod            │          │ Pod            │
  │  env:          │          │  /etc/config/  │
  │   DB_HOST=...  │          │   app.conf     │
  └────────────────┘          └────────────────┘${NC}

${BOLD}핵심 특징:${NC}
  • Key-Value 또는 파일 형식 저장 가능
  • ${RED}민감 정보(비밀번호)는 Secret을 사용${NC}
  • 볼륨 마운트 시 ConfigMap 변경이 Pod에 자동 반영 (약간의 딜레이)
"
  pause

  if ! confirm "ConfigMap을 생성하시겠습니까?"; then return; fi

  read_val "ConfigMap 이름" CM_NAME "app-config"
  read_val "앱 환경 (예: dev/staging/prod)" CM_ENV "dev"
  read_val "로그 레벨 (예: INFO/DEBUG/WARN)" CM_LOG "INFO"
  read_val "최대 연결 수" CM_MAX_CONN "100"

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CM_NAME}
  namespace: ${CURRENT_NS}
data:
  # 단순 Key-Value
  APP_ENV: "${CM_ENV}"
  LOG_LEVEL: "${CM_LOG}"
  MAX_CONNECTIONS: "${CM_MAX_CONN}"

  # 파일 형식 (app.properties 파일로 마운트 가능)
  app.properties: |
    environment=${CM_ENV}
    log.level=${CM_LOG}
    max.connections=${CM_MAX_CONN}
    feature.flag.new-ui=false
EOF
)
  show_yaml "$yaml"

  if confirm "위 ConfigMap을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "ConfigMap/${CURRENT_NS}/${CM_NAME}"
    success "ConfigMap '${CM_NAME}' 생성 완료!"
    kube_result "$(kubectl get configmap "$CM_NAME" -n "$CURRENT_NS" -o yaml 2>&1)"
    tip "ConfigMap을 Pod에서 사용하려면 Deployment의 envFrom.configMapRef 또는 volumes.configMap 사용"
  fi
  pause
}

# =============================================================================
# 6. Secret
# =============================================================================
module_secret() {
  clear
  box "6. Secret — 민감한 정보를 안전하게 저장"

  echo -e "
${BOLD}Secret이란?${NC}
  비밀번호, API 키, TLS 인증서 같은 ${CYAN}민감한 데이터${NC}를
  Base64로 인코딩하여 저장합니다.

${BOLD}ConfigMap vs Secret:${NC}
  ${DIM}┌─────────────┬──────────────────────────────────────────┐
  │ ConfigMap   │ 일반 설정 (ENV, 로그 레벨, 포트 번호 등) │
  │ Secret      │ 민감 정보 (비밀번호, 토큰, 인증서)       │
  └─────────────┴──────────────────────────────────────────────┘${NC}

${BOLD}Secret 타입:${NC}
  • ${CYAN}Opaque${NC}          : 일반 사용자 정의 시크릿 (가장 많이 사용)
  • ${CYAN}kubernetes.io/tls${NC}: TLS 인증서
  • ${CYAN}kubernetes.io/dockerconfigjson${NC}: 프라이빗 레지스트리 인증

${BOLD}주의:${NC}
  Base64는 ${RED}암호화가 아닙니다${NC}! 실무에선 Vault, Sealed Secrets 등
  외부 시크릿 관리 도구를 함께 사용하는 것을 권장합니다.
"
  pause

  if ! confirm "Secret을 생성하시겠습니까?"; then return; fi

  read_val "Secret 이름" SEC_NAME "app-secret"
  read_val "DB 사용자명" SEC_DB_USER "admin"
  read_val "DB 비밀번호" SEC_DB_PASS "P@ssw0rd123"
  read_val "API 키" SEC_API_KEY "my-api-key-value"

  # Base64 인코딩
  local enc_user enc_pass enc_key
  enc_user=$(echo -n "$SEC_DB_USER" | base64)
  enc_pass=$(echo -n "$SEC_DB_PASS" | base64)
  enc_key=$(echo -n "$SEC_API_KEY"  | base64)

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SEC_NAME}
  namespace: ${CURRENT_NS}
type: Opaque
data:
  # 값은 모두 Base64 인코딩된 문자열
  db-username: ${enc_user}
  db-password: ${enc_pass}
  api-key: ${enc_key}
EOF
)
  show_yaml "$yaml"
  warn "실제 값: db-username=${SEC_DB_USER}, db-password=${SEC_DB_PASS}"
  warn "YAML에는 Base64 인코딩 값이 저장됩니다."

  if confirm "위 Secret을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "Secret/${CURRENT_NS}/${SEC_NAME}"
    success "Secret '${SEC_NAME}' 생성 완료!"
    kube_result "$(kubectl get secret "$SEC_NAME" -n "$CURRENT_NS" 2>&1)"
    tip "kubectl get secret ${SEC_NAME} -n ${CURRENT_NS} -o jsonpath='{.data.db-password}' | base64 -d"
    echo -e "    → 위 명령으로 실제 값 복호화 가능"
  fi
  pause
}

# =============================================================================
# 7. PersistentVolume / PVC
# =============================================================================
module_pvc() {
  clear
  box "7. PersistentVolume & PVC — 영구 스토리지"

  echo -e "
${BOLD}스토리지 개념 3단계:${NC}

  ${DIM}① PersistentVolume (PV)   — 관리자가 준비한 실제 스토리지
  ② PersistentVolumeClaim (PVC) — 사용자가 요청하는 스토리지 요구사항
  ③ Pod                         — PVC를 볼륨으로 마운트하여 사용

  관리자         사용자(개발자)      실제 사용
  ┌────┐         ┌────┐           ┌────┐
  │ PV │ ←바인딩→ │PVC │ ←마운트→ │Pod │
  └────┘         └────┘           └────┘${NC}

${BOLD}왜 이렇게 분리할까?${NC}
  • 개발자는 스토리지 인프라를 몰라도 됨
  • 관리자가 미리 다양한 PV를 준비해두고 필요 시 할당
  • StorageClass를 사용하면 PV를 ${CYAN}동적 프로비저닝${NC}으로 자동 생성

${BOLD}AccessMode 종류:${NC}
  ${DIM}• ReadWriteOnce (RWO)  : 1개 노드에서 읽기/쓰기
  • ReadOnlyMany  (ROX)  : 여러 노드에서 읽기만
  • ReadWriteMany (RWX)  : 여러 노드에서 읽기/쓰기 (NFS 등)${NC}
"
  pause

  if ! confirm "PersistentVolumeClaim을 생성하시겠습니까?"; then return; fi

  read_val "PVC 이름" PVC_NAME "my-storage"
  read_val "요청 스토리지 크기 (예: 1Gi)" PVC_SIZE "1Gi"

  echo -e "\n  ${BOLD}Access Mode 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} ReadWriteOnce  (RWO)"
  echo -e "    ${CYAN}2)${NC} ReadWriteMany  (RWX)"
  echo -e "    ${CYAN}3)${NC} ReadOnlyMany   (ROX)"
  echo -ne "    선택 [1-3]: "
  read -r acc_choice
  case "$acc_choice" in
    2) PVC_ACCESS="ReadWriteMany" ;;
    3) PVC_ACCESS="ReadOnlyMany" ;;
    *) PVC_ACCESS="ReadWriteOnce" ;;
  esac

  read_val "StorageClass 이름 (없으면 Enter — 기본 SC 사용)" PVC_SC ""
  local sc_line=""
  [[ -n "$PVC_SC" ]] && sc_line="  storageClassName: ${PVC_SC}"

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${CURRENT_NS}
spec:
  accessModes:
  - ${PVC_ACCESS}
  resources:
    requests:
      storage: ${PVC_SIZE}
${sc_line}
EOF
)
  show_yaml "$yaml"

  if confirm "위 PVC를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "PVC/${CURRENT_NS}/${PVC_NAME}"
    success "PVC '${PVC_NAME}' 생성 완료!"
    kube_result "$(kubectl get pvc "$PVC_NAME" -n "$CURRENT_NS" 2>&1)"
    tip "STATUS가 'Bound'이면 스토리지 할당 완료, 'Pending'이면 PV 또는 StorageClass 확인 필요"
  fi
  pause
}

# =============================================================================
# 8. StatefulSet
# =============================================================================
module_statefulset() {
  clear
  box "8. StatefulSet — 상태를 가진 애플리케이션 관리"

  echo -e "
${BOLD}StatefulSet이란?${NC}
  데이터베이스처럼 ${CYAN}고유한 ID와 영구 스토리지${NC}가 필요한
  상태 기반 애플리케이션을 관리합니다.

${BOLD}Deployment vs StatefulSet:${NC}
  ${DIM}┌──────────────────────────────────────────────────────────┐
  │           Deployment           │      StatefulSet        │
  ├──────────────────────────────────────────────────────────┤
  │ Pod 이름이 랜덤 (app-x7k2f)    │ 순서 보장 (app-0, app-1)│
  │ 스토리지 공유 가능              │ Pod마다 독립 PVC        │
  │ 무상태 앱 (웹서버, API)         │ 유상태 앱 (DB, Kafka)   │
  └──────────────────────────────────────────────────────────┘${NC}

${BOLD}핵심 특징:${NC}
  • Pod 이름: ${CYAN}<이름>-0, <이름>-1, <이름>-2 ...${NC} (순서 고정)
  • 순서대로 생성, 역순으로 삭제
  • Headless Service로 각 Pod에 직접 DNS 접근 가능
  • volumeClaimTemplates로 Pod마다 자동으로 PVC 생성
"
  pause

  if ! confirm "StatefulSet을 생성하시겠습니까?"; then return; fi

  read_val "StatefulSet 이름" SS_NAME "my-db"
  read_val "컨테이너 이미지" SS_IMAGE "nginx:1.25"
  read_val "복제본 수" SS_REPLICAS "3"
  read_val "스토리지 크기 (Pod당)" SS_STORAGE "500Mi"

  local yaml
  yaml=$(cat <<EOF
# Headless Service (StatefulSet 필수 요소)
apiVersion: v1
kind: Service
metadata:
  name: ${SS_NAME}-headless
  namespace: ${CURRENT_NS}
spec:
  clusterIP: None  # Headless: 고정 IP 없음, DNS로 각 Pod 직접 접근
  selector:
    app: ${SS_NAME}
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${SS_NAME}
  namespace: ${CURRENT_NS}
spec:
  serviceName: "${SS_NAME}-headless"
  replicas: ${SS_REPLICAS}
  selector:
    matchLabels:
      app: ${SS_NAME}
  template:
    metadata:
      labels:
        app: ${SS_NAME}
    spec:
      containers:
      - name: ${SS_NAME}
        image: ${SS_IMAGE}
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: ${SS_STORAGE}
EOF
)
  show_yaml "$yaml"
  info "Pod DNS: ${SS_NAME}-0.${SS_NAME}-headless.${CURRENT_NS}.svc.cluster.local"

  if confirm "위 StatefulSet을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "StatefulSet/${CURRENT_NS}/${SS_NAME}"
    success "StatefulSet '${SS_NAME}' 생성 완료!"
    sleep 3
    kube_result "$(kubectl get statefulset "$SS_NAME" -n "$CURRENT_NS" 2>&1)
$(kubectl get pods -n "$CURRENT_NS" -l app="$SS_NAME" 2>&1)"
    tip "각 Pod에 독립적인 PVC가 자동 생성됩니다: kubectl get pvc -n ${CURRENT_NS}"
  fi
  pause
}

# =============================================================================
# 9. DaemonSet
# =============================================================================
module_daemonset() {
  clear
  box "9. DaemonSet — 모든 노드에 하나씩 배포"

  echo -e "
${BOLD}DaemonSet이란?${NC}
  클러스터의 ${CYAN}모든 노드(또는 특정 노드)에 반드시 1개씩${NC}
  Pod를 실행시키는 오브젝트입니다.

${BOLD}동작 방식:${NC}
  ${DIM}노드 추가 → DaemonSet Pod 자동 배포
  노드 삭제 → DaemonSet Pod 자동 제거

  Node1: [fluentd Pod]
  Node2: [fluentd Pod]
  Node3: [fluentd Pod]  ← 자동 추가됨${NC}

${BOLD}주요 사용 사례:${NC}
  • ${CYAN}로그 수집${NC}    : Fluentd, Filebeat
  • ${CYAN}모니터링 에이전트${NC}: node-exporter, Datadog Agent
  • ${CYAN}네트워크 플러그인${NC}: Calico, Cilium
  • ${CYAN}스토리지 에이전트${NC}: Ceph, GlusterFS

${BOLD}kube-system에도 DaemonSet이 있습니다:${NC}
"
  kube_result "$(kubectl get daemonset -n kube-system 2>&1)"
  pause

  if ! confirm "DaemonSet을 생성하시겠습니까?"; then return; fi

  read_val "DaemonSet 이름" DS_NAME "log-collector"
  read_val "컨테이너 이미지" DS_IMAGE "busybox:latest"

  local yaml
  yaml=$(cat <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${DS_NAME}
  namespace: ${CURRENT_NS}
  labels:
    app: ${DS_NAME}
spec:
  selector:
    matchLabels:
      app: ${DS_NAME}
  template:
    metadata:
      labels:
        app: ${DS_NAME}
    spec:
      tolerations:
      # Master 노드에도 배포하려면 이 Toleration 추가
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: ${DS_NAME}
        image: ${DS_IMAGE}
        command: ["sh", "-c", "while true; do echo '[LOG] \$(hostname) - \$(date)'; sleep 10; done"]
        resources:
          limits:
            memory: "64Mi"
            cpu: "50m"
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log  # 노드의 실제 /var/log 마운트
EOF
)
  show_yaml "$yaml"

  if confirm "위 DaemonSet을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "DaemonSet/${CURRENT_NS}/${DS_NAME}"
    success "DaemonSet '${DS_NAME}' 생성 완료!"
    sleep 3
    kube_result "$(kubectl get daemonset "$DS_NAME" -n "$CURRENT_NS" 2>&1)
$(kubectl get pods -n "$CURRENT_NS" -l app="$DS_NAME" -o wide 2>&1)"
    tip "kubectl logs -l app=${DS_NAME} -n ${CURRENT_NS}   # 모든 노드 로그 한번에 확인"
  fi
  pause
}

# =============================================================================
# 10. Job / CronJob
# =============================================================================
module_job() {
  clear
  box "10. Job & CronJob — 일회성 및 주기적 작업 실행"

  echo -e "
${BOLD}Job이란?${NC}
  Pod를 실행하고 ${CYAN}작업 완료 후 종료${NC}되는 오브젝트입니다.
  Deployment와 달리 '완료'가 목표입니다.

${BOLD}CronJob이란?${NC}
  Linux crontab처럼 ${CYAN}정해진 스케줄에 따라 Job을 주기적으로${NC} 실행합니다.

${BOLD}비교:${NC}
  ${DIM}┌──────────┬───────────────────────────────────────────────┐
  │ Job      │ 한 번 실행 (배치 처리, 데이터 마이그레이션)    │
  │ CronJob  │ 반복 실행 (백업, 리포트 생성, 캐시 정리)      │
  └──────────┴───────────────────────────────────────────────┘${NC}

${BOLD}CronJob 스케줄 문법:${NC}
  ${DIM}┌────── 분 (0-59)
  │ ┌──── 시 (0-23)
  │ │ ┌── 일 (1-31)
  │ │ │ ┌ 월 (1-12)
  │ │ │ │ ┌ 요일 (0-7, 0과 7은 일요일)
  * * * * *
  예) 0 2 * * * = 매일 새벽 2시
      */5 * * * * = 5분마다${NC}
"
  pause

  echo -e "\n  ${BOLD}생성할 오브젝트 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Job      (일회성 작업)"
  echo -e "    ${CYAN}2)${NC} CronJob  (반복 작업)"
  echo -ne "    선택 [1-2]: "
  read -r job_choice

  if [[ "$job_choice" == "1" ]]; then
    # Job
    read_val "Job 이름" JOB_NAME "batch-job"
    read_val "실행할 명령 설명" JOB_DESC "데이터 처리"

    local yaml
    yaml=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${CURRENT_NS}
spec:
  completions: 1      # 완료해야 할 Pod 수
  parallelism: 1      # 동시에 실행할 Pod 수
  backoffLimit: 3     # 실패 시 재시도 횟수
  template:
    metadata:
      labels:
        job: ${JOB_NAME}
    spec:
      restartPolicy: Never  # Job은 반드시 Never 또는 OnFailure
      containers:
      - name: worker
        image: busybox:latest
        command: ["sh", "-c"]
        args:
        - |
          echo '=== Job 시작: ${JOB_DESC} ==='
          echo '처리 중...'
          sleep 5
          echo '=== Job 완료 ==='
EOF
)
    show_yaml "$yaml"
    if confirm "위 Job을 실행하시겠습니까?"; then
      echo "$yaml" | kubectl apply -f -
      log_created "Job/${CURRENT_NS}/${JOB_NAME}"
      success "Job '${JOB_NAME}' 시작!"
      info "Job 완료 대기 중..."
      kubectl wait --for=condition=complete job/"$JOB_NAME" \
        -n "$CURRENT_NS" --timeout=60s 2>/dev/null || true
      kube_result "$(kubectl get job "$JOB_NAME" -n "$CURRENT_NS" 2>&1)"
      local pod_name
      pod_name=$(kubectl get pods -n "$CURRENT_NS" -l job="$JOB_NAME" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
      if [[ -n "$pod_name" ]]; then
        echo ""
        info "Job 실행 로그:"
        kubectl logs "$pod_name" -n "$CURRENT_NS" 2>/dev/null || true
      fi
    fi

  else
    # CronJob
    read_val "CronJob 이름" CJ_NAME "scheduled-job"
    read_val "스케줄 (cron 형식)" CJ_SCHEDULE "*/2 * * * *"

    local yaml
    yaml=$(cat <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${CJ_NAME}
  namespace: ${CURRENT_NS}
spec:
  schedule: "${CJ_SCHEDULE}"
  concurrencyPolicy: Forbid      # 이전 Job 실행 중이면 새 Job 건너뜀
  successfulJobsHistoryLimit: 3  # 성공한 Job 보관 수
  failedJobsHistoryLimit: 1      # 실패한 Job 보관 수
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: task
            image: busybox:latest
            command: ["sh", "-c", "echo '정기 작업 실행: '\$(date)"]
EOF
)
    show_yaml "$yaml"
    if confirm "위 CronJob을 생성하시겠습니까?"; then
      echo "$yaml" | kubectl apply -f -
      log_created "CronJob/${CURRENT_NS}/${CJ_NAME}"
      success "CronJob '${CJ_NAME}' 생성 완료!"
      kube_result "$(kubectl get cronjob "$CJ_NAME" -n "$CURRENT_NS" 2>&1)"
      tip "kubectl get jobs -n ${CURRENT_NS} --watch   # 스케줄에 따라 Job 생성 확인"
    fi
  fi
  pause
}

# =============================================================================
# 11. HorizontalPodAutoscaler
# =============================================================================
module_hpa() {
  clear
  box "11. HorizontalPodAutoscaler — 부하에 따른 자동 스케일링"

  echo -e "
${BOLD}HPA란?${NC}
  CPU/메모리 사용률 등 메트릭 기준으로 ${CYAN}Pod 수를 자동으로
  늘리거나 줄이는${NC} 오브젝트입니다.

${BOLD}동작 방식:${NC}
  ${DIM}Metrics Server
       ↓ CPU 사용률 수집
  HPA Controller
       ↓ 목표 사용률 초과 시
  Deployment replicas 조정
       ↓
  [Pod][Pod] → [Pod][Pod][Pod][Pod]  (스케일 아웃)
  [Pod][Pod][Pod][Pod] → [Pod][Pod]  (스케일 인)${NC}

${BOLD}스케일링 공식:${NC}
  ${DIM}필요 replicas = ceil(현재 사용률 / 목표 사용률 × 현재 Pod 수)
  예) CPU 80% / 목표 50% × 2 Pod = 3.2 → 4 Pod로 스케일 아웃${NC}

${BOLD}주의:${NC}
  HPA 사용을 위해서는 ${CYAN}Metrics Server${NC}가 설치되어 있어야 합니다.
  또한 대상 Deployment의 Pod에 ${CYAN}resources.requests${NC} 설정이 필수입니다.
"
  pause

  info "Metrics Server 설치 여부 확인..."
  if ! kubectl top nodes &>/dev/null 2>&1; then
    warn "Metrics Server가 설치되어 있지 않습니다."
    warn "HPA는 생성되지만 메트릭 수집이 안 되면 동작하지 않습니다."
    echo ""
    tip "Metrics Server 설치: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  else
    success "Metrics Server 동작 중"
    kube_result "$(kubectl top nodes 2>&1)"
  fi

  if ! confirm "HPA를 생성하시겠습니까?"; then return; fi

  read_val "대상 Deployment 이름" HPA_TARGET "my-app"
  read_val "최소 Pod 수" HPA_MIN "2"
  read_val "최대 Pod 수" HPA_MAX "10"
  read_val "CPU 사용률 목표 (%)" HPA_CPU "50"

  local yaml
  yaml=$(cat <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${HPA_TARGET}-hpa
  namespace: ${CURRENT_NS}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${HPA_TARGET}
  minReplicas: ${HPA_MIN}
  maxReplicas: ${HPA_MAX}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: ${HPA_CPU}  # CPU ${HPA_CPU}% 초과 시 스케일 아웃
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # 메모리 80% 초과 시도 스케일 아웃
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30   # 스케일 아웃 안정화 대기 시간
    scaleDown:
      stabilizationWindowSeconds: 300  # 스케일 인 안정화 대기 시간 (5분)
EOF
)
  show_yaml "$yaml"

  if confirm "위 HPA를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f - 2>/dev/null || \
      warn "HPA 생성 실패. 대상 Deployment '${HPA_TARGET}'이 존재하는지 확인하세요."
    log_created "HPA/${CURRENT_NS}/${HPA_TARGET}-hpa"
    kube_result "$(kubectl get hpa -n "$CURRENT_NS" 2>&1)"
    tip "kubectl get hpa -n ${CURRENT_NS} --watch   # 실시간 스케일링 모니터링"
  fi
  pause
}

# =============================================================================
# 12. Ingress
# =============================================================================
module_ingress() {
  clear
  box "12. Ingress — HTTP(S) 트래픽 라우팅 규칙"

  echo -e "
${BOLD}Ingress란?${NC}
  클러스터 외부에서 들어오는 HTTP/HTTPS 요청을
  ${CYAN}URL 경로나 호스트명 기준으로 적절한 Service로 라우팅${NC}합니다.

${BOLD}NodePort/LoadBalancer와의 차이:${NC}
  ${DIM}NodePort    : 서비스마다 별도 포트 필요 (:30001, :30002 ...)
  LoadBalancer: 서비스마다 별도 외부 IP 필요 (비용 발생)
  Ingress     : 하나의 엔트리 포인트로 경로 기반 라우팅${NC}

${BOLD}Ingress 라우팅 예시:${NC}
  ${DIM}외부 요청
    ↓
  Ingress Controller (nginx, traefik 등)
    ├── /api/*    → api-service:8080
    ├── /web/*    → web-service:80
    └── /admin/*  → admin-service:3000${NC}

${BOLD}필수 구성 요소:${NC}
  Ingress 리소스를 실제로 처리하려면 ${CYAN}Ingress Controller${NC}가
  클러스터에 설치되어 있어야 합니다 (nginx-ingress, Traefik 등).
"
  pause

  info "Ingress Controller 확인..."
  kube_result "$(kubectl get pods -A | grep -iE 'ingress|traefik' 2>/dev/null || echo '설치된 Ingress Controller를 찾지 못했습니다.')"

  if ! confirm "Ingress를 생성하시겠습니까?"; then return; fi

  read_val "Ingress 이름" ING_NAME "my-ingress"
  read_val "도메인 (예: myapp.example.com)" ING_HOST "myapp.local"
  read_val "첫 번째 경로" ING_PATH1 "/api"
  read_val "첫 번째 경로의 Service 이름" ING_SVC1 "api-service"
  read_val "첫 번째 경로의 Service 포트" ING_PORT1 "8080"
  read_val "두 번째 경로" ING_PATH2 "/"
  read_val "두 번째 경로의 Service 이름" ING_SVC2 "web-service"
  read_val "두 번째 경로의 Service 포트" ING_PORT2 "80"

  local yaml
  yaml=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${ING_NAME}
  namespace: ${CURRENT_NS}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx   # 사용 중인 Ingress Controller 클래스명
  rules:
  - host: ${ING_HOST}
    http:
      paths:
      - path: ${ING_PATH1}
        pathType: Prefix
        backend:
          service:
            name: ${ING_SVC1}
            port:
              number: ${ING_PORT1}
      - path: ${ING_PATH2}
        pathType: Prefix
        backend:
          service:
            name: ${ING_SVC2}
            port:
              number: ${ING_PORT2}
EOF
)
  show_yaml "$yaml"

  if confirm "위 Ingress를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f - 2>/dev/null || \
      warn "Ingress 생성 실패. Ingress Controller 또는 API 버전을 확인하세요."
    log_created "Ingress/${CURRENT_NS}/${ING_NAME}"
    kube_result "$(kubectl get ingress -n "$CURRENT_NS" 2>&1)"
    tip "/etc/hosts 에 '< 노드IP >  ${ING_HOST}' 추가 후 curl http://${ING_HOST}${ING_PATH1} 로 테스트"
  fi
  pause
}

# =============================================================================
# 세션 요약
# =============================================================================
show_session_summary() {
  clear
  box "학습 세션 요약"
  echo ""
  if [[ ${#SESSION_LOG[@]} -eq 0 ]]; then
    echo -e "  이번 세션에서 생성된 오브젝트가 없습니다."
  else
    echo -e "  ${BOLD}이번 세션에서 생성된 오브젝트:${NC}"
    for item in "${SESSION_LOG[@]}"; do
      echo -e "  ${GREEN}✔${NC}  $item"
    done
    echo ""
    echo -e "  ${BOLD}전체 리소스 확인:${NC}"
    echo -e "  ${GREEN}kubectl get all -n ${CURRENT_NS}${NC}"
    echo ""
    echo -ne "  ${BOLD}생성된 리소스를 모두 삭제하시겠습니까?${NC} [y/N]: "
    read -r del_choice
    if [[ "$del_choice" =~ ^[Yy]$ ]]; then
      warn "Namespace '${CURRENT_NS}' 의 리소스를 정리합니다..."
      kubectl delete all --all -n "$CURRENT_NS" 2>/dev/null || true
      kubectl delete pvc --all -n "$CURRENT_NS" 2>/dev/null || true
      kubectl delete configmap --all -n "$CURRENT_NS" 2>/dev/null || true
      kubectl delete secret --all -n "$CURRENT_NS" 2>/dev/null || true
      kubectl delete ingress --all -n "$CURRENT_NS" 2>/dev/null || true
      kubectl delete hpa --all -n "$CURRENT_NS" 2>/dev/null || true
      success "리소스 정리 완료"
    fi
  fi
  echo ""
  pause
}

# =============================================================================
# 클러스터 현황
# =============================================================================
show_cluster_status() {
  clear
  box "클러스터 현재 상태"
  echo ""
  echo -e "${BOLD}노드 목록:${NC}"
  kubectl get nodes -o wide 2>&1
  echo ""
  echo -e "${BOLD}현재 Namespace [${CURRENT_NS}] 리소스:${NC}"
  kubectl get all -n "$CURRENT_NS" 2>&1
  echo ""
  echo -e "${BOLD}PVC / ConfigMap / Secret:${NC}"
  kubectl get pvc,configmap,secret -n "$CURRENT_NS" 2>&1 | grep -v "^NAME.*kubernetes.io" || true
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
    echo "║         Kubernetes 오브젝트 학습 — 인터랙티브 실습           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  현재 Namespace: ${CYAN}${BOLD}${CURRENT_NS}${NC}"
    echo -e "  생성 오브젝트:  ${GREEN}${#SESSION_LOG[@]}개${NC}"
    echo ""
    echo -e "  ${BOLD}── 학습 주제 ────────────────────────────────────────${NC}"
    echo -e "  ${CYAN} 1)${NC} Namespace          — 클러스터 내 가상 분리 공간"
    echo -e "  ${CYAN} 2)${NC} Pod                — 가장 작은 배포 단위"
    echo -e "  ${CYAN} 3)${NC} Deployment         — Pod 개수 유지 + 롤링 업데이트"
    echo -e "  ${CYAN} 4)${NC} Service            — 안정적인 네트워크 엔드포인트"
    echo -e "  ${CYAN} 5)${NC} ConfigMap          — 설정을 코드와 분리"
    echo -e "  ${CYAN} 6)${NC} Secret             — 민감한 정보 저장"
    echo -e "  ${CYAN} 7)${NC} PersistentVolumeClaim — 영구 스토리지 요청"
    echo -e "  ${CYAN} 8)${NC} StatefulSet        — 상태 기반 앱 관리 (DB 등)"
    echo -e "  ${CYAN} 9)${NC} DaemonSet          — 모든 노드에 1개씩 배포"
    echo -e "  ${CYAN}10)${NC} Job / CronJob       — 일회성 / 주기적 작업"
    echo -e "  ${CYAN}11)${NC} HorizontalPodAutoscaler — 자동 스케일링"
    echo -e "  ${CYAN}12)${NC} Ingress             — HTTP 라우팅 규칙"
    echo ""
    echo -e "  ${BOLD}── 기타 ──────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}s)${NC} 클러스터 현재 상태 확인"
    echo -e "  ${YELLOW}r)${NC} 이번 세션 요약 / 리소스 정리"
    echo -e "  ${RED}q)${NC} 종료"
    echo ""
    echo -ne "  ${BOLD}메뉴 선택:${NC} "
    read -r choice

    case "$choice" in
      1)  module_namespace ;;
      2)  module_pod ;;
      3)  module_deployment ;;
      4)  module_service ;;
      5)  module_configmap ;;
      6)  module_secret ;;
      7)  module_pvc ;;
      8)  module_statefulset ;;
      9)  module_daemonset ;;
      10) module_job ;;
      11) module_hpa ;;
      12) module_ingress ;;
      s|S) show_cluster_status ;;
      r|R) show_session_summary ;;
      q|Q)
        echo ""
        show_session_summary
        echo -e "${GREEN}${BOLD}학습을 마칩니다. 수고하셨습니다!${NC}"
        echo ""
        exit 0
        ;;
      *)
        warn "잘못된 선택입니다. 1-12, s, r, q 중 입력하세요."
        sleep 1
        ;;
    esac
  done
}

# =============================================================================
# 실행
# =============================================================================
check_kubectl
main_menu
