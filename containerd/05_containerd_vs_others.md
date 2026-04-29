# 05. containerd vs Docker vs CRI-O 비교

## 컨테이너 런타임 비교표

| 항목 | containerd | Docker Engine | CRI-O |
|------|-----------|---------------|-------|
| **개발사** | CNCF (원래 Docker) | Docker Inc. | Red Hat / CNCF |
| **CRI 지원** | ✅ 내장 | ❌ (dockershim 필요, 제거됨) | ✅ 설계 목적 |
| **K8s 지원** | ✅ 공식 | ❌ (1.24 이후 제거) | ✅ 공식 |
| **OCI 호환** | ✅ | ✅ | ✅ |
| **이미지 빌드** | ❌ (별도 도구 필요) | ✅ docker build | ❌ (Buildah 필요) |
| **CLI** | ctr, nerdctl | docker | podman, crictl |
| **데몬** | containerd | dockerd + containerd | crio |
| **용도** | K8s 런타임, 범용 | 개발 환경, CI | K8s 전용 |
| **메모리** | 낮음 | 높음 | 낮음 |
| **성숙도** | 높음 | 매우 높음 | 높음 |

---

## 아키텍처 비교

### containerd (직접)

```
kubelet
  │ CRI
containerd
  │
containerd-shim-runc-v2
  │
runc → 컨테이너
```

### Docker Engine (과거 K8s)

```
kubelet
  │ CRI
dockershim (제거됨)
  │ Docker API
dockerd
  │
containerd   ← Docker도 내부적으로 containerd 사용
  │
containerd-shim-runc-v2
  │
runc → 컨테이너
```

### CRI-O

```
kubelet
  │ CRI
crio
  │
conmon (container monitor, shim 역할)
  │
runc → 컨테이너
```

---

## 언제 무엇을 선택할까?

### containerd 선택

```
✅ Kubernetes 클러스터 운영 (가장 보편적)
✅ 경량 런타임 필요
✅ Docker 호환 CLI 필요 (nerdctl 사용)
✅ 멀티 런타임 지원 (kata, gVisor, Wasm)
✅ 클라우드 환경 (EKS, GKE, AKS 기본값)
```

### Docker Engine 선택

```
✅ 개발자 로컬 환경 (docker build, docker compose)
✅ CI/CD 파이프라인 이미지 빌드
✅ Docker Desktop 사용
❌ Kubernetes 런타임으로는 부적합 (1.24 이후 지원 종료)
```

### CRI-O 선택

```
✅ Red Hat OpenShift / RHEL 환경
✅ K8s 전용 경량 런타임 필요
✅ Kubernetes 버전과 1:1 매핑 관리
✅ 보안 요구사항이 높은 환경
```

---

## nerdctl — containerd용 Docker 호환 CLI

Docker 명령어와 거의 동일한 문법으로 containerd를 제어합니다.

```bash
# nerdctl 설치
wget https://github.com/containerd/nerdctl/releases/download/v1.7.0/nerdctl-1.7.0-linux-amd64.tar.gz
tar xzf nerdctl-1.7.0-linux-amd64.tar.gz -C /usr/local/bin/

# docker와 동일한 문법
nerdctl run -d --name nginx -p 80:80 nginx
nerdctl ps
nerdctl images
nerdctl pull alpine
nerdctl build -t myapp:v1 .
nerdctl push myregistry.com/myapp:v1

# docker compose 호환
nerdctl compose up -d
nerdctl compose down
```

---

## 이미지 포맷 호환성

모든 런타임은 OCI 이미지 표준을 따릅니다.

```
Docker 이미지 == OCI 이미지 (사실상 동일)

docker build → Docker Hub → containerd pull ✅
nerdctl build → Harbor → CRI-O pull ✅
```

```bash
# 이미지 형식 확인
skopeo inspect docker://nginx:latest | grep MediaType
# application/vnd.oci.image.manifest.v1+json (OCI)
# application/vnd.docker.distribution.manifest.v2+json (Docker)
```
