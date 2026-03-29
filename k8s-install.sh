#!/usr/bin/env bash
# =============================================================================
# Kubernetes Cluster Auto-Installer
# 구성: 1 Master Node + 2 Worker Nodes
# 지원 OS: Ubuntu 20.04/22.04, CentOS/RHEL 7/8/9
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 색상 및 출력 함수
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="k8s-install-$(date +%Y%m%d-%H%M%S).log"

log()     { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
step()    { echo -e "\n${BOLD}${BLUE}==> $*${NC}" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}${BOLD}[OK]${NC}   $*" | tee -a "$LOG_FILE"; }
fail()    { echo -e "${RED}${BOLD}[FAIL]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║          Kubernetes Cluster Auto-Installer               ║"
  echo "║        Master x1  +  Worker x2  구성 자동화              ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_summary() {
  echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━ 설치 구성 요약 ━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}Master Node  :${NC} ${MASTER_USER}@${MASTER_IP}"
  echo -e "  ${BOLD}Worker Node 1:${NC} ${WORKER1_USER}@${WORKER1_IP}"
  echo -e "  ${BOLD}Worker Node 2:${NC} ${WORKER2_USER}@${WORKER2_IP}"
  echo ""
  echo -e "  ${BOLD}Kubernetes 버전 :${NC} ${K8S_VERSION}"
  echo -e "  ${BOLD}Container Runtime:${NC} containerd"
  echo -e "  ${BOLD}CNI Plugin      :${NC} ${CNI_PLUGIN}"
  echo -e "  ${BOLD}Pod CIDR        :${NC} ${POD_CIDR}"
  echo -e "  ${BOLD}Service CIDR    :${NC} ${SERVICE_CIDR}"
  echo -e "  ${BOLD}Master Hostname :${NC} ${MASTER_HOSTNAME}"
  echo ""
  if [[ "${VSPHERE_CSI_ENABLED}" == "yes" ]]; then
    echo -e "  ${BOLD}vSphere CSI     :${NC} ${GREEN}활성화${NC}"
    echo -e "  ${BOLD}vCenter         :${NC} ${VSPHERE_USER}@${VSPHERE_SERVER}:${VSPHERE_PORT}"
    echo -e "  ${BOLD}Datacenter      :${NC} ${VSPHERE_DATACENTER}"
    echo -e "  ${BOLD}Datastore       :${NC} ${VSPHERE_DATASTORE}"
    echo -e "  ${BOLD}Cluster ID      :${NC} ${VSPHERE_CLUSTER_ID}"
    echo -e "  ${BOLD}Storage Policy  :${NC} ${VSPHERE_STORAGE_POLICY:-없음 (Datastore 직접 사용)}"
    echo -e "  ${BOLD}CSI 버전        :${NC} v${VSPHERE_CSI_VERSION}"
  else
    echo -e "  ${BOLD}vSphere CSI     :${NC} ${YELLOW}비활성화${NC}"
  fi
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# -----------------------------------------------------------------------------
# 의존성 확인 (로컬)
# -----------------------------------------------------------------------------
check_local_deps() {
  step "로컬 의존성 확인"
  local missing=()

  for cmd in sshpass ssh scp; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "다음 도구가 설치되어 있지 않습니다: ${missing[*]}"
    echo ""
    echo -e "${YELLOW}설치 방법:${NC}"
    echo "  macOS  : brew install hudochenkov/sshpass/sshpass openssh"
    echo "  Ubuntu : sudo apt-get install -y sshpass openssh-client"
    echo "  CentOS : sudo yum install -y sshpass openssh-clients"
    exit 1
  fi
  success "로컬 의존성 확인 완료 (sshpass, ssh, scp)"
}

# -----------------------------------------------------------------------------
# SSH 헬퍼 함수
# -----------------------------------------------------------------------------
ssh_exec() {
  local user="$1"
  local host="$2"
  local pass="$3"
  local cmd="$4"
  local timeout="${5:-60}"

  sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=30 \
    -o BatchMode=no \
    -tt \
    "${user}@${host}" \
    "sudo bash -c '${cmd}'" 2>/dev/null
}

ssh_exec_raw() {
  local user="$1"
  local host="$2"
  local pass="$3"
  local cmd="$4"

  sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -o BatchMode=no \
    -tt \
    "${user}@${host}" \
    "$cmd" 2>/dev/null
}

scp_file() {
  local user="$1"
  local host="$2"
  local pass="$3"
  local src="$4"
  local dst="$5"

  sshpass -p "$pass" scp \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "$src" "${user}@${host}:${dst}" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 인터랙티브 입력 수집
# -----------------------------------------------------------------------------
read_input() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"
  local value

  if [[ -n "$default" ]]; then
    echo -ne "${BOLD}${prompt}${NC} [기본값: ${CYAN}${default}${NC}]: "
  else
    echo -ne "${BOLD}${prompt}${NC}: "
  fi

  read -r value
  value="${value:-$default}"

  if [[ -z "$value" ]]; then
    error "값을 입력해야 합니다: $prompt"
    exit 1
  fi

  printf -v "$var_name" '%s' "$value"
}

read_password() {
  local prompt="$1"
  local var_name="$2"
  local value

  echo -ne "${BOLD}${prompt}${NC}: "
  read -rs value
  echo ""

  if [[ -z "$value" ]]; then
    error "비밀번호를 입력해야 합니다."
    exit 1
  fi

  printf -v "$var_name" '%s' "$value"
}

read_select() {
  local prompt="$1"
  local var_name="$2"
  shift 2
  local options=("$@")

  echo -e "${BOLD}${prompt}${NC}"
  for i in "${!options[@]}"; do
    echo -e "  ${CYAN}$((i+1)))${NC} ${options[$i]}"
  done
  echo -ne "선택 [1-${#options[@]}]: "

  local choice
  read -r choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
     (( choice < 1 || choice > ${#options[@]} )); then
    error "잘못된 선택: $choice"
    exit 1
  fi

  printf -v "$var_name" '%s' "${options[$((choice-1))]}"
}

collect_inputs() {
  print_banner
  echo -e "${BOLD}설치 전 필요한 정보를 입력해 주세요.${NC}\n"

  # ── Master Node ──────────────────────────────────────────────────────────
  echo -e "${YELLOW}${BOLD}[ Master Node 정보 ]${NC}"
  read_input  "  Master Node IP 주소" MASTER_IP
  read_input  "  Master Node SSH 사용자명" MASTER_USER "root"
  read_password "  Master Node SSH 비밀번호" MASTER_PASS
  read_input  "  Master Node 호스트명" MASTER_HOSTNAME "k8s-master"
  echo ""

  # ── Worker Node 1 ────────────────────────────────────────────────────────
  echo -e "${YELLOW}${BOLD}[ Worker Node 1 정보 ]${NC}"
  read_input  "  Worker 1 IP 주소" WORKER1_IP
  read_input  "  Worker 1 SSH 사용자명" WORKER1_USER "root"
  read_password "  Worker 1 SSH 비밀번호" WORKER1_PASS
  read_input  "  Worker 1 호스트명" WORKER1_HOSTNAME "k8s-worker1"
  echo ""

  # ── Worker Node 2 ────────────────────────────────────────────────────────
  echo -e "${YELLOW}${BOLD}[ Worker Node 2 정보 ]${NC}"
  read_input  "  Worker 2 IP 주소" WORKER2_IP
  read_input  "  Worker 2 SSH 사용자명" WORKER2_USER "root"
  read_password "  Worker 2 SSH 비밀번호" WORKER2_PASS
  read_input  "  Worker 2 호스트명" WORKER2_HOSTNAME "k8s-worker2"
  echo ""

  # ── Kubernetes 옵션 ──────────────────────────────────────────────────────
  echo -e "${YELLOW}${BOLD}[ Kubernetes 설정 ]${NC}"

  # K8s 버전
  echo -e "  ${BOLD}Kubernetes 버전 선택${NC}"
  echo -e "  ${CYAN}1)${NC} 1.31 (latest stable)"
  echo -e "  ${CYAN}2)${NC} 1.30"
  echo -e "  ${CYAN}3)${NC} 1.29"
  echo -e "  ${CYAN}4)${NC} 직접 입력"
  echo -ne "  선택 [1-4]: "
  read -r ver_choice
  case "$ver_choice" in
    1) K8S_VERSION="1.31" ;;
    2) K8S_VERSION="1.30" ;;
    3) K8S_VERSION="1.29" ;;
    4) read_input "  버전 입력 (예: 1.28)" K8S_VERSION ;;
    *) K8S_VERSION="1.31" ;;
  esac
  echo ""

  # CNI 플러그인
  echo -e "  ${BOLD}CNI 플러그인 선택${NC}"
  echo -e "  ${CYAN}1)${NC} Antrea  (VMware 공식, NSX 연동 가능)"
  echo -e "  ${CYAN}2)${NC} Calico  (BGP 기반, 대규모 클러스터 적합)"
  echo -e "  ${CYAN}3)${NC} Cilium  (eBPF 기반, 고성능/보안 정책)"
  echo -ne "  선택 [1-3]: "
  read -r cni_choice
  case "$cni_choice" in
    1) CNI_PLUGIN="Antrea" ;;
    2) CNI_PLUGIN="Calico" ;;
    3) CNI_PLUGIN="Cilium" ;;
    *) CNI_PLUGIN="Calico" ;;
  esac
  echo ""

  # Pod CIDR
  case "$CNI_PLUGIN" in
    Antrea)  default_pod_cidr="10.244.0.0/16" ;;
    Calico)  default_pod_cidr="192.168.0.0/16" ;;
    Cilium)  default_pod_cidr="10.0.0.0/8" ;;
    *)       default_pod_cidr="192.168.0.0/16" ;;
  esac
  read_input "  Pod Network CIDR" POD_CIDR "$default_pod_cidr"

  # Service CIDR
  read_input "  Service Network CIDR" SERVICE_CIDR "10.96.0.0/12"
  echo ""

  # ── vSphere CSI Driver (선택 사항) ────────────────────────────────────────
  echo -e "${YELLOW}${BOLD}[ vSphere CSI Driver 설정 (선택) ]${NC}"
  echo -e "  vSphere 환경에서 PersistentVolume 동적 프로비저닝을 사용하려면 설치하세요."
  echo -ne "  vSphere CSI Driver를 설치하시겠습니까? [y/N]: "
  read -r csi_choice
  if [[ "$csi_choice" =~ ^[Yy]$ ]]; then
    VSPHERE_CSI_ENABLED="yes"
    read_input  "  vCenter IP 또는 FQDN" VSPHERE_SERVER
    read_input  "  vCenter 포트" VSPHERE_PORT "443"
    read_input  "  vCenter 사용자명 (예: administrator@vsphere.local)" VSPHERE_USER
    read_password "  vCenter 비밀번호" VSPHERE_PASS
    read_input  "  Datacenter 이름" VSPHERE_DATACENTER
    read_input  "  클러스터 고유 ID (영문/숫자/하이픈)" VSPHERE_CLUSTER_ID "k8s-cluster-1"
    read_input  "  기본 Datastore 경로 (예: /DC1/datastore/ds1)" VSPHERE_DATASTORE
    echo -ne "  스토리지 정책 사용 여부 [y/N]: "
    read -r spbm_choice
    if [[ "$spbm_choice" =~ ^[Yy]$ ]]; then
      read_input "  vSphere Storage Policy 이름" VSPHERE_STORAGE_POLICY
    else
      VSPHERE_STORAGE_POLICY=""
    fi
    read_input  "  vSphere CSI Driver 버전" VSPHERE_CSI_VERSION "3.3.0"
  else
    VSPHERE_CSI_ENABLED="no"
    VSPHERE_SERVER="" VSPHERE_PORT="443" VSPHERE_USER=""
    VSPHERE_PASS="" VSPHERE_DATACENTER="" VSPHERE_CLUSTER_ID=""
    VSPHERE_DATASTORE="" VSPHERE_STORAGE_POLICY="" VSPHERE_CSI_VERSION=""
  fi
  echo ""
}

# -----------------------------------------------------------------------------
# 사전 확인 (Pre-flight Checks)
# -----------------------------------------------------------------------------
check_ssh_connectivity() {
  local label="$1"
  local user="$2"
  local host="$3"
  local pass="$4"

  echo -ne "  SSH 연결 테스트 (${label}: ${user}@${host}) ... "
  if sshpass -p "$pass" ssh \
       -o StrictHostKeyChecking=no \
       -o ConnectTimeout=8 \
       -o BatchMode=no \
       "${user}@${host}" \
       "echo connected" &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC}"
    return 1
  fi
}

check_node_requirements() {
  local label="$1"
  local user="$2"
  local host="$3"
  local pass="$4"
  local errors=0

  echo -e "\n  ${BOLD}[ ${label}: ${host} ]${NC}"

  # OS 확인
  local os_info
  os_info=$(ssh_exec_raw "$user" "$host" "$pass" \
    "cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION_ID)' | tr '\n' ' '" 2>/dev/null || echo "unknown")
  echo -e "  OS             : ${CYAN}${os_info}${NC}"

  # CPU 코어 수 (최소 2)
  local cpu_cores
  cpu_cores=$(ssh_exec_raw "$user" "$host" "$pass" \
    "nproc 2>/dev/null || echo 0" 2>/dev/null | tr -d '\r' | tr -d ' ')
  if (( cpu_cores >= 2 )); then
    echo -e "  CPU 코어       : ${GREEN}${cpu_cores} (최소 2 충족)${NC}"
  else
    echo -e "  CPU 코어       : ${RED}${cpu_cores} (최소 2 미충족!)${NC}"
    ((errors++))
  fi

  # 메모리 (최소 2GB)
  local mem_mb
  mem_mb=$(ssh_exec_raw "$user" "$host" "$pass" \
    "free -m 2>/dev/null | awk '/^Mem:/{print \$2}'" 2>/dev/null | tr -d '\r' | tr -d ' ')
  mem_mb="${mem_mb:-0}"
  if (( mem_mb >= 1800 )); then
    echo -e "  메모리         : ${GREEN}${mem_mb}MB (최소 2GB 충족)${NC}"
  else
    echo -e "  메모리         : ${RED}${mem_mb}MB (최소 2GB 미충족!)${NC}"
    ((errors++))
  fi

  # 디스크 여유 공간 (최소 20GB)
  local disk_avail_gb
  disk_avail_gb=$(ssh_exec_raw "$user" "$host" "$pass" \
    "df -BG / 2>/dev/null | awk 'NR==2{gsub(/G/,\"\",\$4); print \$4}'" 2>/dev/null | tr -d '\r' | tr -d ' ')
  disk_avail_gb="${disk_avail_gb:-0}"
  if (( disk_avail_gb >= 20 )); then
    echo -e "  디스크 여유    : ${GREEN}${disk_avail_gb}GB (최소 20GB 충족)${NC}"
  else
    echo -e "  디스크 여유    : ${YELLOW}${disk_avail_gb}GB (권장 20GB 미달, 계속 진행 가능)${NC}"
  fi

  # Swap 상태
  local swap_on
  swap_on=$(ssh_exec_raw "$user" "$host" "$pass" \
    "swapon --show 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r' | tr -d ' ')
  swap_on="${swap_on:-0}"
  if (( swap_on == 0 )); then
    echo -e "  Swap           : ${GREEN}비활성화됨 (적합)${NC}"
  else
    echo -e "  Swap           : ${YELLOW}활성화됨 (설치 중 자동 비활성화)${NC}"
  fi

  # 네트워크 연결 (외부)
  local net_ok
  net_ok=$(ssh_exec_raw "$user" "$host" "$pass" \
    "ping -c1 -W3 8.8.8.8 &>/dev/null && echo ok || echo fail" 2>/dev/null | tail -1 | tr -d '\r' | tr -d ' ')
  if [[ "$net_ok" == "ok" ]]; then
    echo -e "  인터넷 연결    : ${GREEN}정상${NC}"
  else
    echo -e "  인터넷 연결    : ${RED}실패 (패키지 다운로드 불가)${NC}"
    ((errors++))
  fi

  # sudo 권한 확인
  local sudo_ok
  sudo_ok=$(sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 \
    "${user}@${host}" \
    "sudo -n true 2>/dev/null && echo ok || echo fail" 2>/dev/null | tail -1 | tr -d '\r' | tr -d ' ')
  if [[ "$sudo_ok" == "ok" ]]; then
    echo -e "  sudo 권한      : ${GREEN}확인됨${NC}"
  else
    echo -e "  sudo 권한      : ${YELLOW}암호 필요 (자동 처리됨)${NC}"
  fi

  return $errors
}

run_preflight_checks() {
  step "사전 요구사항 확인 (Pre-flight Checks)"

  # SSH 연결 테스트
  echo -e "\n${BOLD}SSH 연결 테스트:${NC}"
  local ssh_fail=0
  check_ssh_connectivity "Master"  "$MASTER_USER"  "$MASTER_IP"  "$MASTER_PASS"  || ((ssh_fail++))
  check_ssh_connectivity "Worker1" "$WORKER1_USER" "$WORKER1_IP" "$WORKER1_PASS" || ((ssh_fail++))
  check_ssh_connectivity "Worker2" "$WORKER2_USER" "$WORKER2_IP" "$WORKER2_PASS" || ((ssh_fail++))

  if (( ssh_fail > 0 )); then
    fail "SSH 연결 실패한 노드가 있습니다. IP/계정/비밀번호를 확인하세요."
  fi

  # 노드별 시스템 요구사항 확인
  echo -e "\n${BOLD}시스템 요구사항 확인:${NC}"
  local total_errors=0
  check_node_requirements "Master"  "$MASTER_USER"  "$MASTER_IP"  "$MASTER_PASS"  || ((total_errors+=$?))
  check_node_requirements "Worker1" "$WORKER1_USER" "$WORKER1_IP" "$WORKER1_PASS" || ((total_errors+=$?))
  check_node_requirements "Worker2" "$WORKER2_USER" "$WORKER2_IP" "$WORKER2_PASS" || ((total_errors+=$?))

  if (( total_errors > 0 )); then
    echo ""
    warn "요구사항 미충족 항목이 있습니다. 계속 진행하시겠습니까?"
    echo -ne "${YELLOW}계속 진행하려면 'yes' 입력:${NC} "
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
      echo "설치를 중단합니다."
      exit 0
    fi
  fi

  success "사전 확인 완료"
}

# -----------------------------------------------------------------------------
# 노드 OS 감지
# -----------------------------------------------------------------------------
detect_os() {
  local user="$1"
  local host="$2"
  local pass="$3"

  local os_id
  os_id=$(ssh_exec_raw "$user" "$host" "$pass" \
    "grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '\"'" 2>/dev/null | tail -1 | tr -d '\r')
  echo "$os_id"
}

# -----------------------------------------------------------------------------
# 공통 노드 준비 (모든 노드에서 실행)
# -----------------------------------------------------------------------------
prepare_node() {
  local label="$1"
  local user="$2"
  local host="$3"
  local pass="$4"
  local hostname="$5"

  log "[${label}] 노드 초기화 시작 ..."

  local os_id
  os_id=$(detect_os "$user" "$host" "$pass")
  log "[${label}] OS 감지: ${os_id}"

  # 호스트명 설정
  ssh_exec "$user" "$host" "$pass" "hostnamectl set-hostname ${hostname}" || true
  log "[${label}] 호스트명 설정: ${hostname}"

  # /etc/hosts 업데이트
  ssh_exec "$user" "$host" "$pass" "
    grep -v 'k8s-master\|k8s-worker' /etc/hosts > /tmp/hosts.tmp
    echo '${MASTER_IP}  ${MASTER_HOSTNAME}' >> /tmp/hosts.tmp
    echo '${WORKER1_IP} ${WORKER1_HOSTNAME}' >> /tmp/hosts.tmp
    echo '${WORKER2_IP} ${WORKER2_HOSTNAME}' >> /tmp/hosts.tmp
    cp /tmp/hosts.tmp /etc/hosts
  " || true
  log "[${label}] /etc/hosts 업데이트 완료"

  # Swap 비활성화
  ssh_exec "$user" "$host" "$pass" "
    swapoff -a
    sed -i '/\s\+swap\s\+/d' /etc/fstab
    sed -i 's/^[^#].*swap.*/#&/' /etc/fstab 2>/dev/null || true
  " || true
  log "[${label}] Swap 비활성화 완료"

  # 필요한 커널 모듈 로드
  ssh_exec "$user" "$host" "$pass" "
    modprobe overlay
    modprobe br_netfilter
    cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
  " || true
  log "[${label}] 커널 모듈 로드 완료"

  # sysctl 파라미터 설정
  ssh_exec "$user" "$host" "$pass" "
    cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system
  " || true
  log "[${label}] sysctl 설정 완료"

  # SELinux / firewalld 비활성화 (CentOS/RHEL)
  case "$os_id" in
    centos|rhel|rocky|almalinux)
      ssh_exec "$user" "$host" "$pass" "
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
      " || true
      log "[${label}] SELinux/firewalld 비활성화"
      ;;
  esac

  # OS별 containerd 설치
  install_containerd "$label" "$user" "$host" "$pass" "$os_id"

  # OS별 kubeadm/kubelet/kubectl 설치
  install_kubernetes_packages "$label" "$user" "$host" "$pass" "$os_id"

  success "[${label}] 노드 초기화 완료"
}

# -----------------------------------------------------------------------------
# containerd 설치
# -----------------------------------------------------------------------------
install_containerd() {
  local label="$1"
  local user="$2"
  local host="$3"
  local pass="$4"
  local os_id="$5"

  log "[${label}] containerd 설치 중 ..."

  case "$os_id" in
    ubuntu|debian)
      ssh_exec "$user" "$host" "$pass" "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
          -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
          https://download.docker.com/linux/ubuntu \
          \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" \
          > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq containerd.io
      "
      ;;
    centos|rhel|rocky|almalinux)
      ssh_exec "$user" "$host" "$pass" "
        yum install -y -q yum-utils
        yum-config-manager --add-repo \
          https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y -q containerd.io
      "
      ;;
    fedora)
      ssh_exec "$user" "$host" "$pass" "
        dnf install -y -q containerd
      "
      ;;
    *)
      # 범용 바이너리 설치
      ssh_exec "$user" "$host" "$pass" "
        CONTAINERD_VERSION=1.7.14
        curl -fsSL \
          https://github.com/containerd/containerd/releases/download/v\${CONTAINERD_VERSION}/containerd-\${CONTAINERD_VERSION}-linux-amd64.tar.gz \
          | tar xz -C /usr/local
        curl -fsSL \
          https://raw.githubusercontent.com/containerd/containerd/main/containerd.service \
          -o /etc/systemd/system/containerd.service
        systemctl daemon-reload
      "
      ;;
  esac

  # containerd 기본 설정
  ssh_exec "$user" "$host" "$pass" "
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd
    systemctl restart containerd
  "
  log "[${label}] containerd 설치 및 설정 완료"
}

# -----------------------------------------------------------------------------
# Kubernetes 패키지 설치 (kubeadm, kubelet, kubectl)
# -----------------------------------------------------------------------------
install_kubernetes_packages() {
  local label="$1"
  local user="$2"
  local host="$3"
  local pass="$4"
  local os_id="$5"

  # 버전 메이저.마이너만 추출
  local k8s_major_minor="$K8S_VERSION"

  log "[${label}] Kubernetes ${k8s_major_minor} 패키지 설치 중 ..."

  case "$os_id" in
    ubuntu|debian)
      ssh_exec "$user" "$host" "$pass" "
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq apt-transport-https ca-certificates curl gpg
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/deb/Release.key \
          | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
          https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/deb/ /' \
          > /etc/apt/sources.list.d/kubernetes.list
        apt-get update -qq
        apt-get install -y -qq kubelet kubeadm kubectl
        apt-mark hold kubelet kubeadm kubectl
      "
      ;;
    centos|rhel|rocky|almalinux|fedora)
      ssh_exec "$user" "$host" "$pass" "
        cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
        yum install -y -q kubelet kubeadm kubectl \
          --disableexcludes=kubernetes
        systemctl enable --now kubelet
      "
      ;;
    *)
      warn "[${label}] 알 수 없는 OS (${os_id}). 수동 설치가 필요할 수 있습니다."
      ;;
  esac

  ssh_exec "$user" "$host" "$pass" "
    systemctl enable kubelet
  " || true

  log "[${label}] Kubernetes 패키지 설치 완료"
}

# -----------------------------------------------------------------------------
# Master 노드 초기화
# -----------------------------------------------------------------------------
init_master() {
  step "Master 노드 초기화 (kubeadm init)"

  log "[Master] kubeadm init 실행 중 (약 2~5분 소요) ..."

  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    kubeadm init \
      --apiserver-advertise-address=${MASTER_IP} \
      --pod-network-cidr=${POD_CIDR} \
      --service-cidr=${SERVICE_CIDR} \
      --kubernetes-version=${K8S_VERSION} \
      --node-name=${MASTER_HOSTNAME} \
      2>&1 | tee /tmp/kubeadm-init.log
  " 2>/dev/null | tee -a "$LOG_FILE"

  # kubeconfig 설정
  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    mkdir -p \$HOME/.kube
    cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config
    chown \$(id -u):\$(id -g) \$HOME/.kube/config
  " || true

  # kubectl bash completion
  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
    echo 'alias k=kubectl' >> /root/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> /root/.bashrc
  " || true

  success "[Master] kubeadm init 완료"
}

# -----------------------------------------------------------------------------
# CNI 플러그인 설치
# -----------------------------------------------------------------------------
install_cni() {
  step "CNI 플러그인 설치 (${CNI_PLUGIN})"

  case "$CNI_PLUGIN" in
    Antrea)
      # Antrea v2.2.0 — VMware 공식 CNI, NetworkPolicy 풍부 지원
      log "[Master] Antrea 설치 중 ..."
      ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
        ANTREA_VERSION=v2.2.0
        kubectl apply -f \
          https://github.com/antrea-io/antrea/releases/download/\${ANTREA_VERSION}/antrea.yml
      " 2>/dev/null
      ;;

    Calico)
      # Calico v3.28 — BGP/IPIP 지원, 대규모 클러스터에 적합
      log "[Master] Calico 설치 중 ..."
      ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
        CALICO_VERSION=v3.28.0
        kubectl apply -f \
          https://raw.githubusercontent.com/projectcalico/calico/\${CALICO_VERSION}/manifests/calico.yaml
      " 2>/dev/null
      ;;

    Cilium)
      # Cilium — eBPF 기반 고성능 CNI, Cilium CLI로 설치
      log "[Master] Cilium CLI 설치 중 ..."
      ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
        # Cilium CLI 설치
        CILIUM_CLI_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        ARCH=amd64
        curl -fsSL --remote-name-all \
          https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-\${ARCH}.tar.gz \
          https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-\${ARCH}.tar.gz.sha256sum
        sha256sum --check cilium-linux-\${ARCH}.tar.gz.sha256sum
        tar xzvfC cilium-linux-\${ARCH}.tar.gz /usr/local/bin
        rm -f cilium-linux-\${ARCH}.tar.gz cilium-linux-\${ARCH}.tar.gz.sha256sum
      " 2>/dev/null

      log "[Master] Cilium 클러스터에 설치 중 ..."
      ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
        cilium install \
          --set ipam.mode=cluster-pool \
          --set ipam.operator.clusterPoolIPv4PodCIDRList=${POD_CIDR} \
          --set kubeProxyReplacement=false \
          2>&1
        cilium status --wait
      " 2>/dev/null | tee -a "$LOG_FILE" || true
      ;;
  esac

  log "[Master] CNI 설치 후 Master 노드 Ready 대기 중 (최대 3분) ..."
  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    for i in \$(seq 1 36); do
      if kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
        echo 'Master node is Ready'
        break
      fi
      echo \"대기 중... (\${i}/36)\"
      sleep 5
    done
  " 2>/dev/null | tee -a "$LOG_FILE" || true

  success "[Master] ${CNI_PLUGIN} CNI 설치 완료"
}

# -----------------------------------------------------------------------------
# vSphere CSI Driver 설치
# -----------------------------------------------------------------------------
install_vsphere_csi() {
  [[ "${VSPHERE_CSI_ENABLED}" != "yes" ]] && return 0

  step "vSphere CSI Driver 설치 (v${VSPHERE_CSI_VERSION})"

  # ── 사전 경고 ────────────────────────────────────────────────────────────
  warn "vSphere CSI 전제 조건:"
  warn "  1) 모든 VM에서 disk.EnableUUID = TRUE 설정 필요"
  warn "  2) VM Hardware 버전 15 이상 필요"
  warn "  3) vSphere 6.7U3 / ESXi 6.7U3 이상 필요"
  warn "  4) 각 노드의 VM 이름과 K8s 노드 이름이 동일해야 함"
  echo ""

  # ── csi-vsphere.conf 생성 ────────────────────────────────────────────────
  log "vSphere 설정 파일 생성 중 ..."

  local conf_file
  conf_file=$(mktemp /tmp/csi-vsphere-XXXXXX.conf)

  cat > "$conf_file" << EOF
[Global]
cluster-id = "${VSPHERE_CLUSTER_ID}"
insecure-flag = "true"

[VirtualCenter "${VSPHERE_SERVER}"]
insecure-flag = "true"
user = "${VSPHERE_USER}"
password = "${VSPHERE_PASS}"
port = "${VSPHERE_PORT}"
datacenters = "${VSPHERE_DATACENTER}"
EOF

  # ── Master 노드에 namespace/secret 생성 ──────────────────────────────────
  log "vmware-system-csi 네임스페이스 및 Secret 생성 중 ..."

  scp_file "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" \
    "$conf_file" "/tmp/csi-vsphere.conf"

  rm -f "$conf_file"

  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    kubectl create namespace vmware-system-csi --dry-run=client -o yaml \
      | kubectl apply -f -

    kubectl create secret generic vsphere-config-secret \
      --from-file=/tmp/csi-vsphere.conf \
      --namespace=vmware-system-csi \
      --dry-run=client -o yaml \
      | kubectl apply -f -

    rm -f /tmp/csi-vsphere.conf
  " 2>/dev/null
  log "Secret 생성 완료"

  # ── CSI Driver 매니페스트 적용 ────────────────────────────────────────────
  log "vSphere CSI Driver 매니페스트 적용 중 (v${VSPHERE_CSI_VERSION}) ..."

  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    CSI_VER=${VSPHERE_CSI_VERSION}
    BASE_URL=https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v\${CSI_VER}/manifests/vanilla

    # RBAC
    kubectl apply -f \${BASE_URL}/vsphere-csi-driver.yaml

  " 2>/dev/null | tee -a "$LOG_FILE"

  # ── StorageClass 생성 ─────────────────────────────────────────────────────
  log "StorageClass 생성 중 ..."

  local sc_params=""
  if [[ -n "${VSPHERE_STORAGE_POLICY}" ]]; then
    sc_params="storagePolicyName: \"${VSPHERE_STORAGE_POLICY}\""
  else
    sc_params="datastoreURL: \"ds:///${VSPHERE_DATASTORE}\""
  fi

  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    cat << 'SCEOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: \"true\"
provisioner: csi.vsphere.volume
parameters:
  ${sc_params}
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
SCEOF
  " 2>/dev/null

  # ── CSI Pod 준비 대기 ─────────────────────────────────────────────────────
  log "vSphere CSI Pod 준비 대기 중 (최대 3분) ..."
  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    for i in \$(seq 1 36); do
      running=\$(kubectl get pods -n vmware-system-csi 2>/dev/null \
        | grep -c 'Running' || true)
      if (( running >= 2 )); then
        echo 'vSphere CSI pods are Running'
        break
      fi
      echo \"CSI Pod 준비 중... (\${i}/36)\"
      sleep 5
    done
    echo ''
    kubectl get pods -n vmware-system-csi
    echo ''
    kubectl get storageclass
  " 2>/dev/null | tee -a "$LOG_FILE" || true

  success "vSphere CSI Driver 설치 완료"
  success "기본 StorageClass: vsphere-csi"
}

# -----------------------------------------------------------------------------
# Join 토큰 생성 및 Worker 노드 조인
# -----------------------------------------------------------------------------
join_workers() {
  step "Worker 노드 클러스터 조인"

  log "Join 명령어 생성 중 ..."

  local join_cmd
  join_cmd=$(sshpass -p "$MASTER_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${MASTER_USER}@${MASTER_IP}" \
    "sudo kubeadm token create --print-join-command 2>/dev/null" 2>/dev/null \
    | tail -1 | tr -d '\r')

  if [[ -z "$join_cmd" ]]; then
    fail "Join 명령어 생성 실패. Master 초기화를 확인하세요."
  fi

  log "Join 명령어 획득 완료"

  # Worker 1 조인
  log "[Worker1] 클러스터 조인 중 ..."
  ssh_exec "$WORKER1_USER" "$WORKER1_IP" "$WORKER1_PASS" \
    "${join_cmd} --node-name=${WORKER1_HOSTNAME}" 2>/dev/null | tee -a "$LOG_FILE" || \
    fail "[Worker1] 조인 실패"
  success "[Worker1] 클러스터 조인 완료"

  # Worker 2 조인
  log "[Worker2] 클러스터 조인 중 ..."
  ssh_exec "$WORKER2_USER" "$WORKER2_IP" "$WORKER2_PASS" \
    "${join_cmd} --node-name=${WORKER2_HOSTNAME}" 2>/dev/null | tee -a "$LOG_FILE" || \
    fail "[Worker2] 조인 실패"
  success "[Worker2] 클러스터 조인 완료"
}

# -----------------------------------------------------------------------------
# 설치 검증
# -----------------------------------------------------------------------------
verify_cluster() {
  step "클러스터 상태 검증"

  log "노드 상태 확인 중 (최대 5분 대기) ..."

  # 모든 노드 Ready 대기
  ssh_exec "$MASTER_USER" "$MASTER_IP" "$MASTER_PASS" "
    for i in \$(seq 1 60); do
      ready_count=\$(kubectl get nodes 2>/dev/null | grep -c ' Ready' || true)
      if (( ready_count >= 3 )); then
        echo 'All 3 nodes are Ready!'
        break
      fi
      echo \"Ready 노드: \${ready_count}/3 (대기 중... \${i}/60)\"
      sleep 5
    done
    echo ''
    echo '=== 노드 상태 ==='
    kubectl get nodes -o wide
    echo ''
    echo '=== 시스템 Pod 상태 ==='
    kubectl get pods -n kube-system
    echo ''
    if kubectl get ns vmware-system-csi &>/dev/null; then
      echo '=== vSphere CSI Pod 상태 ==='
      kubectl get pods -n vmware-system-csi
      echo ''
      echo '=== StorageClass 목록 ==='
      kubectl get storageclass
    fi
  " 2>/dev/null | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# 완료 메시지
# -----------------------------------------------------------------------------
print_completion() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Kubernetes 클러스터 설치 완료!                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "${BOLD}클러스터 접속 방법:${NC}"
  echo -e "  ssh ${MASTER_USER}@${MASTER_IP}"
  echo -e "  kubectl get nodes"
  echo ""
  echo -e "${BOLD}kubeconfig 로컬 복사:${NC}"
  echo -e "  mkdir -p ~/.kube"
  echo -e "  scp ${MASTER_USER}@${MASTER_IP}:~/.kube/config ~/.kube/config"
  echo ""
  if [[ "${VSPHERE_CSI_ENABLED}" == "yes" ]]; then
    echo -e "${BOLD}vSphere CSI 확인:${NC}"
    echo -e "  kubectl get pods -n vmware-system-csi"
    echo -e "  kubectl get storageclass"
    echo ""
  fi
  echo -e "${BOLD}로그 파일:${NC} ${LOG_FILE}"
  echo ""
}

# -----------------------------------------------------------------------------
# 최종 확인 프롬프트
# -----------------------------------------------------------------------------
confirm_install() {
  print_summary
  echo -e "${YELLOW}${BOLD}위 설정으로 Kubernetes 클러스터 설치를 시작하시겠습니까?${NC}"
  echo -e "${RED}주의: 각 노드의 기존 Kubernetes 설정이 초기화됩니다.${NC}"
  echo -ne "\n계속하려면 ${BOLD}'yes'${NC}를 입력하세요: "
  read -r confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "설치를 취소했습니다."
    exit 0
  fi
  echo ""
}

# -----------------------------------------------------------------------------
# 병렬 노드 준비 실행
# -----------------------------------------------------------------------------
prepare_all_nodes_parallel() {
  step "모든 노드 동시 초기화 (병렬 실행)"
  log "3개 노드를 병렬로 초기화합니다 ..."

  prepare_node "Master"  "$MASTER_USER"  "$MASTER_IP"  "$MASTER_PASS"  "$MASTER_HOSTNAME"  &
  local pid_master=$!

  prepare_node "Worker1" "$WORKER1_USER" "$WORKER1_IP" "$WORKER1_PASS" "$WORKER1_HOSTNAME" &
  local pid_w1=$!

  prepare_node "Worker2" "$WORKER2_USER" "$WORKER2_IP" "$WORKER2_PASS" "$WORKER2_HOSTNAME" &
  local pid_w2=$!

  local failed=0
  wait $pid_master || { error "Master 노드 초기화 실패"; ((failed++)); }
  wait $pid_w1     || { error "Worker1 노드 초기화 실패"; ((failed++)); }
  wait $pid_w2     || { error "Worker2 노드 초기화 실패"; ((failed++)); }

  if (( failed > 0 )); then
    fail "노드 초기화 중 오류 발생. 로그를 확인하세요: ${LOG_FILE}"
  fi

  success "모든 노드 초기화 완료"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  check_local_deps
  collect_inputs
  confirm_install

  echo -e "${BOLD}설치 로그: ${LOG_FILE}${NC}\n"

  run_preflight_checks
  prepare_all_nodes_parallel
  init_master
  install_cni
  join_workers
  install_vsphere_csi
  verify_cluster
  print_completion
}

main "$@"
