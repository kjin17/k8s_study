#!/usr/bin/env bash
# =============================================================================
# Kubernetes RBAC 인터랙티브 실습 스크립트
# 대상: K8s RBAC를 처음 배우는 학습자
# 권한: 클러스터에 RBAC 리소스를 생성/삭제할 수 있는 admin 권한 필요
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
err()     { echo -e "${RED}[ERR]${NC}   $*"; }
label()   { echo -e "${CYAN}${BOLD}$*${NC}"; }
step()    { echo -e "\n${BOLD}${BLUE}▶  $*${NC}"; }
success() { echo -e "${GREEN}${BOLD}✔  $*${NC}"; }
tip()     { echo -e "${MAGENTA}${BOLD}💡 TIP:${NC} ${MAGENTA}$*${NC}"; }

box() {
  local text="$1"
  local len=${#text}
  local line
  printf -v line '%*s' "$((len + 4))" ''
  echo -e "${CYAN}${BOLD}┌${line// /─}┐${NC}"
  echo -e "${CYAN}${BOLD}│  ${text}  │${NC}"
  echo -e "${CYAN}${BOLD}└${line// /─}┘${NC}"
}

show_yaml() {
  echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━ 적용될 YAML ━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}$1${NC}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

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

# 세션 중 생성된 리소스 추적
SESSION_LOG=()
log_created() { SESSION_LOG+=("$1"); }

# -----------------------------------------------------------------------------
# 사전 점검
# -----------------------------------------------------------------------------
check_prereq() {
  if ! command -v kubectl &>/dev/null; then
    err "kubectl 명령어를 찾을 수 없습니다. 설치 후 다시 실행해주세요."
    exit 1
  fi
  if ! kubectl cluster-info &>/dev/null; then
    err "Kubernetes 클러스터에 연결할 수 없습니다. kubeconfig를 확인하세요."
    exit 1
  fi

  # RBAC 리소스 생성 권한 확인
  if ! kubectl auth can-i create rolebindings -A &>/dev/null; then
    warn "현재 사용자는 RoleBinding 생성 권한이 없을 수 있습니다."
    warn "실습 진행 중 일부 기능이 실패할 수 있습니다."
    confirm "그래도 계속 진행하시겠습니까?" || exit 0
  fi

  if ! command -v openssl &>/dev/null; then
    warn "openssl 이 없습니다. 'User 생성(X.509)' 메뉴는 비활성화됩니다."
  fi
}

# 실습 환경 변수
PRACTICE_NS="rbac-lab"
PRACTICE_SA="lab-sa"
CSR_USER=""
CSR_GROUP="rbac-students"

# =============================================================================
# 0. 인트로
# =============================================================================
intro() {
  clear
  box "Kubernetes RBAC 인터랙티브 실습"
  echo -e "
${BOLD}이 스크립트로 학습할 내용:${NC}
  ${CYAN}①${NC}  RBAC 4대 리소스: Role / ClusterRole / RoleBinding / ClusterRoleBinding
  ${CYAN}②${NC}  ServiceAccount 생성 및 Pod에서 사용하기
  ${CYAN}③${NC}  사용자(User)를 X.509 인증서로 만들기
  ${CYAN}④${NC}  kubectl auth can-i 로 권한 테스트
  ${CYAN}⑤${NC}  Forbidden 에러를 보고 권한 추가하기

${BOLD}실습 전 알아두기:${NC}
  • 이 스크립트는 ${CYAN}${PRACTICE_NS}${NC} 네임스페이스에서 작업합니다.
  • 종료 시 'r' 메뉴로 모든 실습 리소스를 정리할 수 있습니다.
  • RBAC 변경에는 cluster-admin 권한이 필요합니다.

${BOLD}현재 사용자:${NC}
  $(kubectl auth whoami 2>/dev/null || echo '  (whoami API 미지원 — kubectl 1.27+ 필요)')

${BOLD}현재 컨텍스트:${NC}
  $(kubectl config current-context)
"
  pause
}

# =============================================================================
# 1. 실습 네임스페이스 준비
# =============================================================================
module_namespace() {
  clear
  box "1. 실습 네임스페이스 준비"

  echo -e "
${BOLD}왜 별도 네임스페이스가 필요한가?${NC}
  RBAC 실습은 다른 네임스페이스의 리소스에 영향을 주지 않도록
  ${CYAN}격리된 네임스페이스${NC}에서 진행하는 것이 안전합니다.

${BOLD}이 스크립트의 실습 네임스페이스:${NC} ${CYAN}${PRACTICE_NS}${NC}
"
  pause

  step "현재 네임스페이스 목록"
  kube_result "$(kubectl get namespaces 2>&1)"

  if kubectl get namespace "$PRACTICE_NS" &>/dev/null; then
    info "네임스페이스 '${PRACTICE_NS}' 가 이미 존재합니다."
  else
    if confirm "실습 네임스페이스 '${PRACTICE_NS}' 를 생성하시겠습니까?"; then
      local yaml
      yaml=$(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${PRACTICE_NS}
  labels:
    purpose: rbac-practice
EOF
)
      show_yaml "$yaml"
      echo "$yaml" | kubectl apply -f -
      log_created "Namespace/${PRACTICE_NS}"
      success "네임스페이스 생성 완료!"
    fi
  fi

  # 데모용 Pod 생성 (Pod이 있어야 권한 테스트가 의미 있음)
  if confirm "권한 테스트용 데모 Pod(nginx) 도 생성하시겠습니까?"; then
    kubectl run demo-pod --image=nginx:alpine -n "$PRACTICE_NS" \
      --restart=Never 2>/dev/null || warn "이미 존재하거나 생성 실패"
    log_created "Pod/${PRACTICE_NS}/demo-pod"
    kube_result "$(kubectl get pods -n "$PRACTICE_NS" 2>&1)"
  fi
  pause
}

# =============================================================================
# 2. ServiceAccount 생성 + 토큰 발급
# =============================================================================
module_serviceaccount() {
  clear
  box "2. ServiceAccount — Pod의 신원"

  echo -e "
${BOLD}ServiceAccount(SA)란?${NC}
  Pod 내부의 ${CYAN}워크로드(앱, CI 도구 등)${NC}가 K8s API를 호출할 때
  사용하는 신원(Identity) 입니다.

${BOLD}자동 토큰 마운트:${NC}
  ${DIM}/var/run/secrets/kubernetes.io/serviceaccount/
  ├── token       ← JWT 토큰 (자동 갱신)
  ├── ca.crt
  └── namespace${NC}

${BOLD}이번 실습:${NC}
  • 네임스페이스 '${PRACTICE_NS}' 에 SA '${PRACTICE_SA}' 생성
  • 그 SA의 토큰을 발급해서 직접 확인
"
  pause

  step "현재 ServiceAccount 목록"
  kube_result "$(kubectl get serviceaccount -n "$PRACTICE_NS" 2>&1)"

  read_val "ServiceAccount 이름" PRACTICE_SA "$PRACTICE_SA"

  local yaml
  yaml=$(cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${PRACTICE_SA}
  namespace: ${PRACTICE_NS}
EOF
)
  show_yaml "$yaml"

  if confirm "위 ServiceAccount 를 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "ServiceAccount/${PRACTICE_NS}/${PRACTICE_SA}"
    success "ServiceAccount '${PRACTICE_SA}' 생성 완료!"
    kube_result "$(kubectl get sa "$PRACTICE_SA" -n "$PRACTICE_NS" -o yaml 2>&1)"
  fi

  if confirm "이 SA 의 토큰을 발급해보시겠습니까? (kubectl create token, 1시간 유효)"; then
    local token
    token=$(kubectl create token "$PRACTICE_SA" -n "$PRACTICE_NS" --duration=1h 2>&1)
    kube_result "$token"
    tip "이 토큰을 외부 도구(Jenkins, ArgoCD 등) 의 자격증명으로 등록할 수 있습니다."
    tip "토큰을 디코딩해서 내용을 확인: echo '<token>' | cut -d. -f2 | base64 -d"
  fi
  pause
}

# =============================================================================
# 3. Role 생성 (Namespace-scoped)
# =============================================================================
module_role() {
  clear
  box "3. Role — 네임스페이스 내 권한 정의"

  echo -e "
${BOLD}Role 이란?${NC}
  특정 ${CYAN}네임스페이스 안에서${NC} 어떤 리소스에 어떤 작업이 가능한지 정의합니다.

${BOLD}rules 의 3요소:${NC}
  ${CYAN}apiGroups${NC}  — \"\" (core), apps, batch, networking.k8s.io ...
  ${CYAN}resources${NC}  — pods, services, deployments, secrets ...
  ${CYAN}verbs${NC}      — get, list, watch, create, update, patch, delete ...

${BOLD}이번 실습:${NC}
  ${PRACTICE_NS} 네임스페이스의 Pod 를 ${CYAN}읽기 전용${NC}으로 볼 수 있는 Role 을 생성합니다.
"
  pause

  read_val "Role 이름" ROLE_NAME "pod-reader"
  echo -e "\n  ${BOLD}권한 프리셋 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Pod 읽기 전용 (get/list/watch on pods,pods/log)"
  echo -e "    ${CYAN}2)${NC} Deployment 편집 (get/list/watch/patch/update on deployments)"
  echo -e "    ${CYAN}3)${NC} ConfigMap 관리 (모든 verb on configmaps)"
  echo -e "    ${CYAN}4)${NC} Pod exec 권한 (디버깅용)"
  echo -ne "    선택 [1-4]: "
  read -r preset

  local rules_yaml
  case "$preset" in
    2)
      rules_yaml="- apiGroups: [\"apps\"]
  resources: [\"deployments\"]
  verbs: [\"get\", \"list\", \"watch\", \"patch\", \"update\"]"
      ;;
    3)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"configmaps\"]
  verbs: [\"*\"]"
      ;;
    4)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"pods\"]
  verbs: [\"get\", \"list\"]
- apiGroups: [\"\"]
  resources: [\"pods/exec\", \"pods/portforward\", \"pods/log\"]
  verbs: [\"create\", \"get\"]"
      ;;
    *)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"pods\", \"pods/log\"]
  verbs: [\"get\", \"list\", \"watch\"]"
      ;;
  esac

  local yaml
  yaml=$(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${PRACTICE_NS}
rules:
${rules_yaml}
EOF
)
  show_yaml "$yaml"

  if confirm "위 Role 을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "Role/${PRACTICE_NS}/${ROLE_NAME}"
    success "Role '${ROLE_NAME}' 생성 완료!"
    kube_result "$(kubectl describe role "$ROLE_NAME" -n "$PRACTICE_NS" 2>&1)"
    tip "이 Role 은 아직 누구에게도 부여되지 않았습니다 — RoleBinding 이 필요합니다."
  fi
  pause
}

# =============================================================================
# 4. ClusterRole 생성 (Cluster-scoped)
# =============================================================================
module_clusterrole() {
  clear
  box "4. ClusterRole — 클러스터 전역 권한 정의"

  echo -e "
${BOLD}ClusterRole 이란?${NC}
  ${CYAN}클러스터 전체${NC} 또는 비-네임스페이스 리소스(노드, PV, CRD 등) 에 대한
  권한을 정의합니다. 또는 모든 네임스페이스에서 재사용할 권한 템플릿.

${BOLD}활용 패턴:${NC}
  ${DIM}① ClusterRole + ClusterRoleBinding → 클러스터 전역 권한
  ② ClusterRole + RoleBinding         → 같은 권한을 여러 NS 에서 재사용 ⭐${NC}

${BOLD}이번 실습:${NC}
  ${CYAN}node-reader${NC} ClusterRole 생성 (Node 정보 읽기)
"
  pause

  read_val "ClusterRole 이름" CR_NAME "node-reader"
  echo -e "\n  ${BOLD}권한 프리셋 선택:${NC}"
  echo -e "    ${CYAN}1)${NC} Node 읽기 (get/list/watch on nodes)"
  echo -e "    ${CYAN}2)${NC} PV 읽기 (get/list/watch on persistentvolumes)"
  echo -e "    ${CYAN}3)${NC} 모든 Pod 읽기 (모든 NS, get/list/watch)"
  echo -ne "    선택 [1-3]: "
  read -r preset

  local rules_yaml
  case "$preset" in
    2)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"persistentvolumes\"]
  verbs: [\"get\", \"list\", \"watch\"]"
      ;;
    3)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"pods\", \"pods/log\"]
  verbs: [\"get\", \"list\", \"watch\"]"
      ;;
    *)
      rules_yaml="- apiGroups: [\"\"]
  resources: [\"nodes\", \"nodes/status\"]
  verbs: [\"get\", \"list\", \"watch\"]"
      ;;
  esac

  local yaml
  yaml=$(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${CR_NAME}
rules:
${rules_yaml}
EOF
)
  show_yaml "$yaml"

  if confirm "위 ClusterRole 을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "ClusterRole/${CR_NAME}"
    success "ClusterRole '${CR_NAME}' 생성 완료!"
    kube_result "$(kubectl describe clusterrole "$CR_NAME" 2>&1)"
  fi
  pause
}

# =============================================================================
# 5. RoleBinding 생성
# =============================================================================
module_rolebinding() {
  clear
  box "5. RoleBinding — Role 을 Subject 에 부여 (NS 한정)"

  echo -e "
${BOLD}RoleBinding 이란?${NC}
  앞서 정의한 Role 또는 ClusterRole 을 ${CYAN}특정 네임스페이스${NC} 안에서
  ${CYAN}Subject(User/Group/SA)${NC} 에게 부여합니다.

${BOLD}roleRef 는 변경 불가:${NC}
  ${RED}한 번 만든 RoleBinding 의 roleRef 는 수정할 수 없습니다.${NC}
  → 다른 Role 을 참조하려면 삭제 후 재생성

${BOLD}현재 ${PRACTICE_NS} 네임스페이스의 Role / ClusterRole 후보:${NC}
"
  echo -e "${BOLD}  Role:${NC}"
  kubectl get role -n "$PRACTICE_NS" 2>/dev/null || echo "  (없음)"
  echo -e "\n${BOLD}  ClusterRole (일부):${NC}"
  kubectl get clusterrole 2>/dev/null | grep -E '^(view|edit|admin|node-reader|pod-reader)' || echo "  (기본 ClusterRole 사용 가능)"
  pause

  read_val "RoleBinding 이름" RB_NAME "lab-binding"

  echo -e "\n  ${BOLD}어떤 Role 을 부여할지:${NC}"
  echo -e "    ${CYAN}1)${NC} Role         (${PRACTICE_NS} 네임스페이스의 Role)"
  echo -e "    ${CYAN}2)${NC} ClusterRole  (재사용 패턴 — view, edit, 사용자 정의 등)"
  echo -ne "    선택 [1-2]: "
  read -r role_kind_choice

  local ROLE_KIND ROLE_REF
  case "$role_kind_choice" in
    2)
      ROLE_KIND="ClusterRole"
      read_val "ClusterRole 이름" ROLE_REF "view"
      ;;
    *)
      ROLE_KIND="Role"
      read_val "Role 이름" ROLE_REF "pod-reader"
      ;;
  esac

  echo -e "\n  ${BOLD}Subject 종류:${NC}"
  echo -e "    ${CYAN}1)${NC} ServiceAccount  (이 NS 의 SA)"
  echo -e "    ${CYAN}2)${NC} User            (X.509/OIDC 사용자)"
  echo -e "    ${CYAN}3)${NC} Group           (그룹)"
  echo -ne "    선택 [1-3]: "
  read -r subj_choice

  local subject_yaml
  case "$subj_choice" in
    2)
      read_val "User 이름" SUBJ_NAME "alice"
      subject_yaml="- kind: User
  name: ${SUBJ_NAME}
  apiGroup: rbac.authorization.k8s.io"
      ;;
    3)
      read_val "Group 이름" SUBJ_NAME "dev-team"
      subject_yaml="- kind: Group
  name: ${SUBJ_NAME}
  apiGroup: rbac.authorization.k8s.io"
      ;;
    *)
      read_val "ServiceAccount 이름" SUBJ_NAME "$PRACTICE_SA"
      subject_yaml="- kind: ServiceAccount
  name: ${SUBJ_NAME}
  namespace: ${PRACTICE_NS}"
      ;;
  esac

  local yaml
  yaml=$(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${RB_NAME}
  namespace: ${PRACTICE_NS}
subjects:
${subject_yaml}
roleRef:
  kind: ${ROLE_KIND}
  name: ${ROLE_REF}
  apiGroup: rbac.authorization.k8s.io
EOF
)
  show_yaml "$yaml"

  if confirm "위 RoleBinding 을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "RoleBinding/${PRACTICE_NS}/${RB_NAME}"
    success "RoleBinding '${RB_NAME}' 생성 완료!"
    kube_result "$(kubectl describe rolebinding "$RB_NAME" -n "$PRACTICE_NS" 2>&1)"
    tip "다음 메뉴 (7번) 에서 'kubectl auth can-i' 로 권한을 테스트해보세요."
  fi
  pause
}

# =============================================================================
# 6. ClusterRoleBinding 생성
# =============================================================================
module_clusterrolebinding() {
  clear
  box "6. ClusterRoleBinding — 클러스터 전역 권한 부여"

  echo -e "
${BOLD}ClusterRoleBinding 이란?${NC}
  ClusterRole 을 ${CYAN}클러스터 전역${NC}에서 Subject 에게 부여합니다.
  → 모든 네임스페이스에 권한 부여
  → 비-네임스페이스 리소스(노드, PV) 권한 부여

${RED}${BOLD}⚠️ 주의:${NC}
  ${RED}ClusterRoleBinding 은 권한이 강력합니다.
  꼭 필요한 경우에만 사용하고, 가능하면 RoleBinding 으로 NS 를 제한하세요.${NC}
"
  pause

  read_val "ClusterRoleBinding 이름" CRB_NAME "lab-cluster-binding"
  read_val "참조할 ClusterRole 이름" CRB_ROLE_REF "view"

  echo -e "\n  ${BOLD}Subject 종류:${NC}"
  echo -e "    ${CYAN}1)${NC} ServiceAccount"
  echo -e "    ${CYAN}2)${NC} User"
  echo -e "    ${CYAN}3)${NC} Group"
  echo -ne "    선택 [1-3]: "
  read -r subj_choice

  local subject_yaml
  case "$subj_choice" in
    2)
      read_val "User 이름" SUBJ_NAME "alice"
      subject_yaml="- kind: User
  name: ${SUBJ_NAME}
  apiGroup: rbac.authorization.k8s.io"
      ;;
    3)
      read_val "Group 이름" SUBJ_NAME "ops-team"
      subject_yaml="- kind: Group
  name: ${SUBJ_NAME}
  apiGroup: rbac.authorization.k8s.io"
      ;;
    *)
      read_val "ServiceAccount 이름" SUBJ_NAME "$PRACTICE_SA"
      read_val "ServiceAccount 의 namespace" SUBJ_NS "$PRACTICE_NS"
      subject_yaml="- kind: ServiceAccount
  name: ${SUBJ_NAME}
  namespace: ${SUBJ_NS}"
      ;;
  esac

  local yaml
  yaml=$(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${CRB_NAME}
subjects:
${subject_yaml}
roleRef:
  kind: ClusterRole
  name: ${CRB_ROLE_REF}
  apiGroup: rbac.authorization.k8s.io
EOF
)
  show_yaml "$yaml"

  if confirm "위 ClusterRoleBinding 을 생성하시겠습니까?"; then
    echo "$yaml" | kubectl apply -f -
    log_created "ClusterRoleBinding/${CRB_NAME}"
    success "ClusterRoleBinding '${CRB_NAME}' 생성 완료!"
    kube_result "$(kubectl describe clusterrolebinding "$CRB_NAME" 2>&1)"
  fi
  pause
}

# =============================================================================
# 7. 권한 테스트 (kubectl auth can-i, --as)
# =============================================================================
module_test_permission() {
  clear
  box "7. 권한 테스트 — kubectl auth can-i"

  echo -e "
${BOLD}kubectl auth can-i 란?${NC}
  특정 사용자/SA 가 어떤 작업을 할 수 있는지 ${CYAN}실제로 시도하지 않고${NC}
  검증하는 명령어입니다.

${BOLD}주요 옵션:${NC}
  ${GREEN}--as <user>${NC}         다른 사용자로 가장(impersonation)
  ${GREEN}--as-group <group>${NC}   특정 그룹의 권한으로 검증
  ${GREEN}--list${NC}               해당 NS 의 모든 권한 나열

${BOLD}이번 실습:${NC}
  내가 생성한 SA / User 가 어떤 권한을 가졌는지 직접 확인합니다.
"
  pause

  echo -e "  ${BOLD}어떤 Subject 의 권한을 테스트할까요?${NC}"
  echo -e "    ${CYAN}1)${NC} ServiceAccount  (예: ${PRACTICE_NS}:${PRACTICE_SA})"
  echo -e "    ${CYAN}2)${NC} User            (예: alice)"
  echo -e "    ${CYAN}3)${NC} 현재 나 자신     (whoami)"
  echo -ne "    선택 [1-3]: "
  read -r who

  local AS_FLAG=""
  case "$who" in
    1)
      read_val "SA 이름" SA_NAME "$PRACTICE_SA"
      read_val "SA namespace" SA_NS "$PRACTICE_NS"
      AS_FLAG="--as=system:serviceaccount:${SA_NS}:${SA_NAME}"
      ;;
    2)
      read_val "User 이름" USR_NAME "alice"
      AS_FLAG="--as=${USR_NAME}"
      read_val "그룹 (optional, 없으면 빈칸)" USR_GRP ""
      [[ -n "$USR_GRP" ]] && AS_FLAG="${AS_FLAG} --as-group=${USR_GRP}"
      ;;
    *) AS_FLAG="" ;;
  esac

  echo -e "\n  ${BOLD}테스트 메뉴:${NC}"
  echo -e "    ${CYAN}1)${NC} 단일 권한 체크 (verb + resource 입력)"
  echo -e "    ${CYAN}2)${NC} 권한 풀 리스트 (--list, ${PRACTICE_NS} NS)"
  echo -e "    ${CYAN}3)${NC} 자주 묻는 권한 일괄 체크"
  echo -ne "    선택 [1-3]: "
  read -r mode

  case "$mode" in
    1)
      read_val "verb (예: get, list, create, delete)" VERB "list"
      read_val "resource (예: pods, deployments, secrets)" RES "pods"
      read_val "namespace (cluster-scoped 면 빈칸)" NS_OPT "$PRACTICE_NS"
      local NS_ARG=""
      [[ -n "$NS_OPT" ]] && NS_ARG="-n $NS_OPT"
      step "kubectl auth can-i ${VERB} ${RES} ${NS_ARG} ${AS_FLAG}"
      kubectl auth can-i "$VERB" "$RES" $NS_ARG $AS_FLAG && \
        success "허용됨 (yes)" || warn "거부됨 (no)"
      ;;
    2)
      step "kubectl auth can-i --list -n ${PRACTICE_NS} ${AS_FLAG}"
      kubectl auth can-i --list -n "$PRACTICE_NS" $AS_FLAG 2>&1 | head -50
      ;;
    3)
      step "자주 묻는 권한 일괄 체크 (NS=${PRACTICE_NS})"
      local checks=(
        "list pods"
        "get pods/log"
        "create pods"
        "delete pods"
        "list secrets"
        "create deployments"
        "patch deployments"
        "list nodes"
        "get persistentvolumes"
        "create rolebindings"
      )
      printf "  %-30s %s\n" "권한" "결과"
      printf "  %-30s %s\n" "------------------------------" "----"
      for c in "${checks[@]}"; do
        local v="${c% *}"
        local r="${c#* }"
        local ns_arg="-n $PRACTICE_NS"
        # cluster-scoped resource 는 -n 제외
        case "$r" in
          nodes|persistentvolumes|clusterroles|clusterrolebindings) ns_arg="" ;;
        esac
        if kubectl auth can-i "$v" "$r" $ns_arg $AS_FLAG &>/dev/null; then
          printf "  %-30s ${GREEN}✔ yes${NC}\n" "$c"
        else
          printf "  %-30s ${RED}✘ no${NC}\n" "$c"
        fi
      done
      ;;
  esac
  pause
}

# =============================================================================
# 8. User(X.509) 만들기 — 실제 kubeconfig 생성
# =============================================================================
module_create_user() {
  clear
  box "8. X.509 인증서로 User 만들기"

  if ! command -v openssl &>/dev/null; then
    err "openssl 명령이 없어 사용할 수 없습니다."
    pause; return
  fi

  echo -e "
${BOLD}이 실습은 무엇을 하나?${NC}
  ${CYAN}①${NC} 사용자용 RSA 키 생성
  ${CYAN}②${NC} CSR(Certificate Signing Request) 생성
  ${CYAN}③${NC} K8s CSR 리소스로 제출 → 관리자 승인
  ${CYAN}④${NC} 발급된 인증서로 ${CYAN}별도 kubeconfig 파일${NC} 생성
  ${CYAN}⑤${NC} 새 사용자로 권한 테스트 가능

${BOLD}생성 위치:${NC} ./rbac-lab/${BOLD}<username>${NC}/
${YELLOW}주의: kubeadm 같은 자체 서명 CA 가 없는 환경에서는 동작하지 않을 수 있습니다.${NC}
"
  pause

  read_val "사용자명 (CN)" CSR_USER "alice"
  read_val "그룹명 (O)" CSR_GROUP "$CSR_GROUP"

  local USER_DIR="./rbac-lab/${CSR_USER}"
  mkdir -p "$USER_DIR"

  step "1) 개인 키 생성"
  openssl genrsa -out "$USER_DIR/${CSR_USER}.key" 2048 2>&1 | tail -3
  success "키 생성: $USER_DIR/${CSR_USER}.key"

  step "2) CSR 생성 (CN=${CSR_USER}, O=${CSR_GROUP})"
  openssl req -new \
    -key "$USER_DIR/${CSR_USER}.key" \
    -out "$USER_DIR/${CSR_USER}.csr" \
    -subj "/CN=${CSR_USER}/O=${CSR_GROUP}" 2>&1 | tail -3
  success "CSR 생성: $USER_DIR/${CSR_USER}.csr"

  step "3) K8s CSR 리소스로 제출"
  local csr_b64
  csr_b64=$(base64 < "$USER_DIR/${CSR_USER}.csr" | tr -d '\n')

  local csr_name="rbac-lab-${CSR_USER}"
  # 기존에 있으면 삭제
  kubectl delete csr "$csr_name" 2>/dev/null || true

  local yaml
  yaml=$(cat <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${csr_name}
spec:
  request: ${csr_b64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
)
  show_yaml "$yaml"
  echo "$yaml" | kubectl apply -f -
  log_created "CertificateSigningRequest/${csr_name}"

  step "4) CSR 승인"
  kubectl certificate approve "$csr_name"
  sleep 2

  step "5) 발급된 인증서 추출"
  if ! kubectl get csr "$csr_name" -o jsonpath='{.status.certificate}' 2>/dev/null | base64 -d > "$USER_DIR/${CSR_USER}.crt" 2>/dev/null; then
    err "인증서 발급 실패. CA signer 가 활성화되어 있는지 확인하세요."
    warn "kubeadm 클러스터에서는 보통 정상 동작합니다."
    pause; return
  fi

  if [[ ! -s "$USER_DIR/${CSR_USER}.crt" ]]; then
    warn "인증서가 비어있습니다. CSR 가 아직 처리되지 않았을 수 있습니다."
    warn "kubectl get csr ${csr_name} 으로 상태를 확인하세요."
    pause; return
  fi
  success "인증서 추출: $USER_DIR/${CSR_USER}.crt"

  step "6) 별도 kubeconfig 파일 생성"
  local kubeconfig="$USER_DIR/${CSR_USER}.kubeconfig"
  local cluster_name api_server ca_data
  cluster_name=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
  api_server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  ca_data=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' || echo "")

  cat > "$kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${cluster_name}
  cluster:
    server: ${api_server}
    certificate-authority-data: ${ca_data}
users:
- name: ${CSR_USER}
  user:
    client-certificate: $(realpath "$USER_DIR/${CSR_USER}.crt")
    client-key: $(realpath "$USER_DIR/${CSR_USER}.key")
contexts:
- name: ${CSR_USER}@${cluster_name}
  context:
    cluster: ${cluster_name}
    user: ${CSR_USER}
    namespace: ${PRACTICE_NS}
current-context: ${CSR_USER}@${cluster_name}
EOF

  success "kubeconfig 생성: $kubeconfig"
  echo ""
  tip "이 사용자로 kubectl 사용:"
  echo "    KUBECONFIG=$kubeconfig kubectl get pods"
  echo ""
  tip "권한이 없으면 RoleBinding 을 추가해보세요:"
  echo "    kubectl create rolebinding ${CSR_USER}-view \\"
  echo "      --clusterrole=view --user=${CSR_USER} -n ${PRACTICE_NS}"
  echo ""

  if confirm "${CSR_USER} 에게 ${PRACTICE_NS} NS 의 view 권한을 즉시 부여할까요?"; then
    kubectl create rolebinding "${CSR_USER}-view" \
      --clusterrole=view \
      --user="$CSR_USER" \
      -n "$PRACTICE_NS" 2>&1 || warn "이미 존재하거나 생성 실패"
    log_created "RoleBinding/${PRACTICE_NS}/${CSR_USER}-view"

    step "이제 ${CSR_USER} 로 시도해봅니다"
    if KUBECONFIG="$kubeconfig" kubectl get pods -n "$PRACTICE_NS" 2>&1; then
      success "Pod 조회 성공!"
    fi
  fi
  pause
}

# =============================================================================
# 9. 현재 RBAC 상태 조회 (이 NS 의 모든 RBAC)
# =============================================================================
module_inspect() {
  clear
  box "9. 현재 RBAC 상태 조회"

  step "${PRACTICE_NS} 네임스페이스의 ServiceAccount"
  kubectl get serviceaccount -n "$PRACTICE_NS" 2>&1
  echo ""

  step "${PRACTICE_NS} 네임스페이스의 Role"
  kubectl get role -n "$PRACTICE_NS" 2>&1
  echo ""

  step "${PRACTICE_NS} 네임스페이스의 RoleBinding"
  kubectl get rolebinding -n "$PRACTICE_NS" -o wide 2>&1
  echo ""

  step "이 실습 세션이 만든 ClusterRole / ClusterRoleBinding"
  for item in "${SESSION_LOG[@]}"; do
    case "$item" in
      ClusterRole/*) kubectl get clusterrole "${item#ClusterRole/}" 2>/dev/null ;;
      ClusterRoleBinding/*) kubectl get clusterrolebinding "${item#ClusterRoleBinding/}" 2>/dev/null ;;
    esac
  done
  echo ""

  read_val "특정 사용자/SA 의 권한을 inspect 할까요? (이름 또는 빈칸)" INSPECT_NAME ""

  if [[ -n "$INSPECT_NAME" ]]; then
    step "이름이 '${INSPECT_NAME}' 인 RoleBinding/ClusterRoleBinding 의 subject 검색"
    if command -v jq &>/dev/null; then
      echo -e "${BOLD}RoleBindings:${NC}"
      kubectl get rolebinding -A -o json | \
        jq -r --arg n "$INSPECT_NAME" \
        '.items[] | select(.subjects[]?.name==$n) |
         "  \(.metadata.namespace)/\(.metadata.name) -> \(.roleRef.kind)/\(.roleRef.name)"'
      echo -e "\n${BOLD}ClusterRoleBindings:${NC}"
      kubectl get clusterrolebinding -o json | \
        jq -r --arg n "$INSPECT_NAME" \
        '.items[] | select(.subjects[]?.name==$n) |
         "  \(.metadata.name) -> \(.roleRef.kind)/\(.roleRef.name)"'
    else
      warn "jq 가 없어 간단 출력만 표시합니다. 'brew install jq' 추천."
      kubectl get rolebinding -A -o wide | grep -E "$INSPECT_NAME" || echo "  (없음)"
      kubectl get clusterrolebinding -o wide | grep -E "$INSPECT_NAME" || echo "  (없음)"
    fi
  fi

  pause
}

# =============================================================================
# 10. Forbidden 시뮬레이션 + 권한 추가 워크플로우
# =============================================================================
module_forbidden_demo() {
  clear
  box "10. Forbidden 에러 → 권한 추가 워크플로우"

  echo -e "
${BOLD}이 실습은 무엇을 하나?${NC}
  ${CYAN}①${NC} 권한이 없는 SA 로 어떤 작업을 시도 → ${RED}Forbidden${NC} 발생
  ${CYAN}②${NC} 에러 메시지를 분석 → 필요한 권한 파악
  ${CYAN}③${NC} 정확한 RBAC 추가 → 다시 시도 → ${GREEN}성공${NC}

${BOLD}시나리오:${NC}
  새 SA 'no-perm-sa' 를 만들고, demo-pod 의 로그를 읽으려 시도합니다.
  처음엔 거부 → 권한 추가 후 허용됨을 확인합니다.
"
  pause

  local DEMO_SA="no-perm-sa"
  step "1) 권한이 없는 SA 생성"
  kubectl create sa "$DEMO_SA" -n "$PRACTICE_NS" 2>/dev/null || info "이미 존재"
  log_created "ServiceAccount/${PRACTICE_NS}/${DEMO_SA}"

  step "2) ${DEMO_SA} 가 demo-pod 의 로그를 볼 수 있는지 시도 (현재: 권한 없음)"
  echo "  ${DIM}\$ kubectl auth can-i get pods/log --as=system:serviceaccount:${PRACTICE_NS}:${DEMO_SA} -n ${PRACTICE_NS}${NC}"
  if kubectl auth can-i get pods/log \
    --as="system:serviceaccount:${PRACTICE_NS}:${DEMO_SA}" \
    -n "$PRACTICE_NS" 2>/dev/null; then
    warn "예상과 다르게 권한이 있습니다. 다른 RoleBinding 이 적용 중인지 확인하세요."
  else
    echo -e "  ${RED}${BOLD}→ no (Forbidden 예상됨)${NC}"
  fi

  step "3) 실제 로그 조회 시도 (실패 메시지 확인)"
  local out
  out=$(kubectl logs demo-pod -n "$PRACTICE_NS" \
    --as="system:serviceaccount:${PRACTICE_NS}:${DEMO_SA}" 2>&1 || true)
  echo -e "${RED}${out}${NC}"
  echo ""
  tip "에러 메시지에서 추출:"
  echo "    verb     : ${BOLD}get${NC} (logs 는 pods/log 의 get 으로 매핑됨)"
  echo "    resource : ${BOLD}pods/log${NC}"
  echo "    apiGroup : ${BOLD}\"\" (core)${NC}"
  echo "    namespace: ${BOLD}${PRACTICE_NS}${NC}"
  pause

  step "4) 정확한 권한이 담긴 Role + RoleBinding 생성"
  local fix_yaml
  fix_yaml=$(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: log-viewer
  namespace: ${PRACTICE_NS}
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${DEMO_SA}-log-viewer
  namespace: ${PRACTICE_NS}
subjects:
- kind: ServiceAccount
  name: ${DEMO_SA}
  namespace: ${PRACTICE_NS}
roleRef:
  kind: Role
  name: log-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
)
  show_yaml "$fix_yaml"

  if confirm "위 권한을 적용하시겠습니까?"; then
    echo "$fix_yaml" | kubectl apply -f -
    log_created "Role/${PRACTICE_NS}/log-viewer"
    log_created "RoleBinding/${PRACTICE_NS}/${DEMO_SA}-log-viewer"

    step "5) 다시 시도 (이번엔 성공해야 함)"
    sleep 1
    if kubectl auth can-i get pods/log \
      --as="system:serviceaccount:${PRACTICE_NS}:${DEMO_SA}" \
      -n "$PRACTICE_NS"; then
      success "권한 부여 성공! Forbidden 이 해결되었습니다."
    fi

    echo ""
    info "실제 로그 조회:"
    kubectl logs demo-pod -n "$PRACTICE_NS" \
      --as="system:serviceaccount:${PRACTICE_NS}:${DEMO_SA}" 2>&1 | head -5 || true
  fi
  pause
}

# =============================================================================
# 세션 요약 / 정리
# =============================================================================
show_session_summary() {
  clear
  box "세션 요약 — 생성된 RBAC 리소스"
  echo ""
  if [[ ${#SESSION_LOG[@]} -eq 0 ]]; then
    echo -e "  이번 세션에서 생성된 리소스가 없습니다."
    pause
    return
  fi

  echo -e "  ${BOLD}이번 세션에서 생성된 리소스:${NC}"
  for item in "${SESSION_LOG[@]}"; do
    echo -e "  ${GREEN}✔${NC}  $item"
  done
  echo ""

  if confirm "위 리소스들을 모두 삭제하시겠습니까? (네임스페이스 ${PRACTICE_NS} 도 함께 삭제됩니다)"; then
    warn "정리 중..."

    # ClusterRole / ClusterRoleBinding 정리
    for item in "${SESSION_LOG[@]}"; do
      case "$item" in
        ClusterRole/*) kubectl delete clusterrole "${item#ClusterRole/}" --ignore-not-found 2>/dev/null || true ;;
        ClusterRoleBinding/*) kubectl delete clusterrolebinding "${item#ClusterRoleBinding/}" --ignore-not-found 2>/dev/null || true ;;
        CertificateSigningRequest/*) kubectl delete csr "${item#CertificateSigningRequest/}" --ignore-not-found 2>/dev/null || true ;;
      esac
    done

    # 네임스페이스 통째로 삭제 (NS 안의 모든 Role/RB/SA 도 함께 삭제됨)
    kubectl delete namespace "$PRACTICE_NS" --ignore-not-found 2>/dev/null || true

    # 로컬 작업 디렉터리 정리 옵션
    if [[ -d "./rbac-lab" ]]; then
      if confirm "로컬 ./rbac-lab/ 디렉터리(인증서/kubeconfig)도 삭제할까요?"; then
        rm -rf "./rbac-lab"
        info "로컬 디렉터리 삭제 완료"
      fi
    fi

    success "정리 완료!"
  fi
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
    echo "║           Kubernetes RBAC — 인터랙티브 실습                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  실습 네임스페이스: ${CYAN}${BOLD}${PRACTICE_NS}${NC}"
    echo -e "  생성한 리소스:    ${GREEN}${#SESSION_LOG[@]}개${NC}"
    echo -e "  현재 컨텍스트:    ${DIM}$(kubectl config current-context)${NC}"
    echo ""
    echo -e "  ${BOLD}── 실습 단계 ───────────────────────────────────────${NC}"
    echo -e "  ${CYAN} 1)${NC} 실습 네임스페이스 + 데모 Pod 준비"
    echo -e "  ${CYAN} 2)${NC} ServiceAccount 생성 + 토큰 발급"
    echo -e "  ${CYAN} 3)${NC} Role 생성              (NS 한정 권한)"
    echo -e "  ${CYAN} 4)${NC} ClusterRole 생성       (전역 권한)"
    echo -e "  ${CYAN} 5)${NC} RoleBinding 생성       (Subject ↔ Role)"
    echo -e "  ${CYAN} 6)${NC} ClusterRoleBinding 생성"
    echo -e "  ${CYAN} 7)${NC} 권한 테스트            (kubectl auth can-i)"
    echo -e "  ${CYAN} 8)${NC} X.509 사용자 만들기    (kubeconfig 생성까지)"
    echo -e "  ${CYAN} 9)${NC} 현재 RBAC 상태 조회"
    echo -e "  ${CYAN}10)${NC} Forbidden → 권한 추가 시나리오"
    echo ""
    echo -e "  ${BOLD}── 기타 ──────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}r)${NC} 세션 요약 / 정리"
    echo -e "  ${YELLOW}i)${NC} 이 스크립트 사용 안내"
    echo -e "  ${RED}q)${NC} 종료"
    echo ""
    echo -ne "  ${BOLD}메뉴 선택:${NC} "
    read -r choice

    case "$choice" in
      1)  module_namespace ;;
      2)  module_serviceaccount ;;
      3)  module_role ;;
      4)  module_clusterrole ;;
      5)  module_rolebinding ;;
      6)  module_clusterrolebinding ;;
      7)  module_test_permission ;;
      8)  module_create_user ;;
      9)  module_inspect ;;
      10) module_forbidden_demo ;;
      r|R) show_session_summary ;;
      i|I) intro ;;
      q|Q)
        echo ""
        show_session_summary
        echo -e "${GREEN}${BOLD}RBAC 학습을 마칩니다. 수고하셨습니다!${NC}"
        echo ""
        exit 0
        ;;
      *)
        warn "잘못된 선택입니다. 1-10, r, i, q 중 입력하세요."
        sleep 1
        ;;
    esac
  done
}

# =============================================================================
# Entry Point
# =============================================================================
check_prereq
intro
main_menu
