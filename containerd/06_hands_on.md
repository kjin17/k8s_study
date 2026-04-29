# 06. 실습 예제

## 실습 환경 확인

```bash
# containerd 버전 확인
containerd --version
ctr version

# containerd 서비스 상태
systemctl status containerd

# 설정 파일 확인
cat /etc/containerd/config.toml
```

---

## 실습 1: ctr로 컨테이너 직접 관리

ctr은 containerd 기본 CLI입니다. (Kubernetes 네임스페이스와 별도)

```bash
# 이미지 pull
ctr image pull docker.io/library/nginx:latest

# 이미지 목록
ctr image ls

# 컨테이너 생성 및 실행
ctr run -d docker.io/library/nginx:latest nginx-test

# 실행 중인 컨테이너 목록
ctr container ls
ctr task ls

# 컨테이너 내 명령 실행
ctr task exec --exec-id shell nginx-test /bin/bash

# 컨테이너 정지 및 삭제
ctr task kill nginx-test
ctr task rm nginx-test
ctr container rm nginx-test

# 이미지 삭제
ctr image rm docker.io/library/nginx:latest
```

---

## 실습 2: crictl로 Kubernetes 런타임 디버깅

crictl은 CRI 인터페이스를 직접 호출하는 도구입니다. kubelet과 동일한 방식으로 동작합니다.

```bash
# crictl 설정
cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Pod 목록 (k8s.io 네임스페이스)
crictl pods
crictl pods --label app=nginx

# 컨테이너 목록
crictl ps
crictl ps -a   # 중지된 컨테이너 포함

# 이미지 목록
crictl images

# Pod 상세 정보
crictl inspectp <pod-id>
crictl inspectp <pod-id> | python3 -m json.tool

# 컨테이너 상세 정보
crictl inspect <container-id>

# 컨테이너 로그
crictl logs <container-id>
crictl logs --tail 50 <container-id>
crictl logs -f <container-id>   # 실시간

# 컨테이너 내 명령 실행
crictl exec -it <container-id> /bin/bash
crictl exec <container-id> ls /

# 컨테이너 통계
crictl stats
crictl stats <container-id>
```

---

## 실습 3: containerd-shim 직접 관찰

```bash
# 실행 중인 shim 프로세스 확인
ps aux | grep containerd-shim

# shim 수 = Pod 수
ps aux | grep containerd-shim | grep -v grep | wc -l
kubectl get pods -A --no-headers | grep Running | wc -l

# 특정 Pod의 shim 확인
POD_NAME=nginx-xxx
POD_UID=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.uid}')
kubectl get pod $POD_NAME -o jsonpath='{.status.containerStatuses[0].containerID}'
# containerd://abc123...

# shim 소켓 확인
ls /run/containerd/io.containerd.runtime.v2.task/k8s.io/

# shim PID 확인
CONTAINER_ID=abc123...
cat /run/containerd/io.containerd.runtime.v2.task/k8s.io/${CONTAINER_ID}/init.pid

# 프로세스 트리
pstree -p $(pgrep containerd | head -1)
```

---

## 실습 4: containerd 재시작 내결함성 확인

```bash
# 테스트 Pod 실행
kubectl run resilience-test --image=nginx

# Pod IP 및 컨테이너 ID 확인
kubectl get pod resilience-test -o wide
crictl ps | grep resilience

# containerd 재시작
sudo systemctl restart containerd

# Pod 상태 확인 — Running 유지되어야 함
kubectl get pods
# resilience-test   1/1   Running   0   ...

# shim은 살아있음
ps aux | grep containerd-shim | grep -v grep

# 정리
kubectl delete pod resilience-test
```

---

## 실습 5: nerdctl 사용

```bash
# nerdctl 설치 확인
nerdctl version

# 이미지 빌드
mkdir /tmp/nerdctl-test && cd /tmp/nerdctl-test
cat > Dockerfile << EOF
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["sh", "-c", "echo Hello from nerdctl && curl -s ifconfig.me"]
EOF

nerdctl build -t myapp:v1 .

# 실행
nerdctl run --rm myapp:v1

# 컨테이너 실행 (백그라운드)
nerdctl run -d --name myapp-test myapp:v1 sleep 300

# docker 명령과 동일하게 사용
nerdctl ps
nerdctl exec -it myapp-test sh
nerdctl logs myapp-test
nerdctl rm -f myapp-test
nerdctl rmi myapp:v1
```

---

## 실습 6: 이미지 레이어 및 스냅샷 확인

```bash
# 이미지 레이어 확인
ctr -n k8s.io image ls
ctr -n k8s.io content ls | head -20

# nginx 이미지 매니페스트 확인
IMAGE_DIGEST=$(ctr -n k8s.io image ls | grep nginx | awk '{print $3}')
ctr -n k8s.io content get $IMAGE_DIGEST | python3 -m json.tool

# 스냅샷 목록 (overlayfs 레이어)
ctr -n k8s.io snapshot ls | head -20

# 특정 컨테이너의 overlayfs 마운트 확인
CONTAINER_ID=$(crictl ps | grep nginx | awk '{print $1}')
cat /proc/$(crictl inspect $CONTAINER_ID | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['info']['pid'])")/mountinfo | grep overlay

# overlayfs lowerdir/upperdir 직접 확인
mount | grep overlay | head -3
```

---

## 트러블슈팅 명령어

```bash
# containerd 로그 확인
journalctl -u containerd -f
journalctl -u containerd --since "10 minutes ago"

# containerd 상태 확인
ctr version
systemctl status containerd

# 디스크 사용량 확인
du -sh /var/lib/containerd/
ctr -n k8s.io image ls --format '{{.Size}}' | awk '{sum+=$1} END {print sum/1024/1024 " MB"}'

# 이미지 가비지 컬렉션
ctr -n k8s.io image prune --all

# 컨테이너 강제 삭제
crictl stopp <pod-id>
crictl rmp <pod-id>

# containerd 설정 검증
containerd config dump
```
