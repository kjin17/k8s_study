# 03. IPVS 모드

## 개요

**IPVS(IP Virtual Server)**는 리눅스 LVS(Linux Virtual Server) 프로젝트의 일부로,
커널 레벨의 고성능 로드밸런서입니다. kube-proxy가 IPVS 모드로 동작하면 해시 테이블 기반으로
Service를 처리하여 대규모 클러스터에서 iptables 대비 월등한 성능을 제공합니다.

---

## 아키텍처

```
패킷 수신 (ClusterIP:Port 목적지)
    │
    ▼
netfilter hook (PREROUTING)
    │
    ▼
ip_vs 모듈 (커널 해시 테이블 직접 조회)
    │
    ▼  O(1) 해시 룩업
    ├── Virtual Server: 10.96.0.1:80
    │       Real Server: 10.0.0.1:8080  (weight 1)
    │       Real Server: 10.0.0.2:8080  (weight 1)
    │       Real Server: 10.0.0.3:8080  (weight 1)
    │
    ▼
선택된 Real Server로 DNAT
```

IPVS는 Service를 **Virtual Server**, Endpoint를 **Real Server**로 관리합니다.
별도의 iptables 규칙 없이 커널 내부 해시 구조로 직접 매핑합니다.

---

## 지원 스케줄러 (로드밸런싱 알고리즘)

| 스케줄러 | 설명 | 적합한 경우 |
|---------|------|------------|
| `rr` | Round Robin — 순서대로 분배 | 동일 성능 Pod |
| `lc` | Least Connection — 연결 수 최소 Pod | 연결 유지 시간 가변 |
| `dh` | Destination Hash — 목적지 해시 | 캐시 친화적 |
| `sh` | Source Hash — 출발지 해시 | 세션 어피니티 |
| `sed` | Shortest Expected Delay | 응답 지연 최소화 |
| `nq` | Never Queue — 유휴 서버 우선 | 빠른 응답 우선 |
| `wlc` | Weighted Least Connection | 가중치 기반 분배 |
| `wrr` | Weighted Round Robin | 성능 차이 있는 Pod |

---

## 장점

- **높은 확장성**: O(1) 해시 룩업으로 서비스 수 증가에도 성능 유지
- **다양한 로드밸런싱**: rr, lc, wlc 등 여러 스케줄러 선택 가능
- **빠른 업데이트**: 엔드포인트 추가/삭제 시 해당 항목만 수정 (전체 재작성 불필요)
- **낮은 CPU 오버헤드**: 대량 트래픽에서도 iptables 대비 CPU 사용량 적음
- **대규모 검증**: 수천~수만 서비스 환경에서 검증된 성능

---

## 단점

- **커널 모듈 의존성**: `ip_vs`, `ip_vs_rr`, `ip_vs_wrr`, `ip_vs_sh` 등 모듈 사전 로드 필요
- **iptables 완전 대체 불가**: kube-proxy IPVS 모드도 일부 iptables 규칙 사용 (NodePort, masquerade 등)
- **디버깅 도구**: `ipvsadm` 명령어 별도 설치 필요, iptables보다 친숙도 낮음
- **ipset 의존성**: kube-proxy IPVS 모드는 ipset으로 IP 집합 관리 (ipset 설치 필요)

---

## 성능 특성

| 항목 | 내용 |
|------|------|
| 서비스 조회 복잡도 | O(1) — 해시 테이블 직접 조회 |
| 규칙 업데이트 방식 | 개별 항목 수정 |
| 적합한 클러스터 규모 | 중간~대규모 (서비스 1,000개 이상) |
| 로드밸런싱 방식 | rr / lc / wlc / wrr / sh / dh 등 |

---

## 사전 준비 (커널 모듈 로드)

```bash
# 필요한 커널 모듈 로드
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack

# 부팅 시 자동 로드 설정
cat >> /etc/modules-load.d/ipvs.conf <<EOF
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

# 모듈 로드 확인
lsmod | grep ip_vs
```

---

## kube-proxy IPVS 모드 설정

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
  scheduler: "rr"           # 기본 스케줄러
  syncPeriod: "30s"         # 동기화 주기
  minSyncPeriod: "5s"       # 최소 동기화 간격
  tcpTimeout: "0s"
  tcpFinTimeout: "0s"
  udpTimeout: "0s"
```

---

## 운영 확인 명령어

```bash
# ipvsadm 설치 (필요 시)
apt-get install ipvsadm   # Ubuntu/Debian
yum install ipvsadm       # CentOS/RHEL

# 가상 서버 목록 확인
ipvsadm -Ln

# 특정 서비스 확인
ipvsadm -Ln | grep -A5 "10.96.0.1:80"

# 연결 통계 확인
ipvsadm -Ln --stats

# ipset 목록 확인 (kube-proxy가 관리)
ipset list | grep KUBE

# kube-proxy 로그에서 ipvs 관련 확인
kubectl logs -n kube-system -l k8s-app=kube-proxy | grep ipvs
```

---

## 주의 사항

- 일부 관리형 쿠버네티스(EKS, GKE 등)에서는 커널 모듈 로드 제약이 있을 수 있음
- IPVS 모드에서도 NodePort, LoadBalancer, masquerade 처리를 위해 iptables 규칙 일부 사용됨
- 커널 버전 4.1 이상에서 IPVS 기능 안정화 (4.19+ 권장)
