# Kubernetes GPU 교육 커리큘럼: Pod의 GPU 사용과 노드 간 분산 잡

> 시작: 2026-10-10. 한 회차에 한 절씩 `gpu/NN-<주제>.md`로 채운다. 채운 절은 `[x]`로 바꾸고 파일 링크를 단다.
> 공개된 1차 출처(Kubernetes·NVIDIA·Kubeflow·Ray·Volcano·Kueue 공식 문서, 릴리스 노트, KEP)만 쓴다.
> 주장마다 등급을 붙인다. **[근거]** 는 출처에 그대로 있는 것, **[추론]** 은 여러 출처를 엮어 직접 내린 결론이다.
> 출처 링크 옆에는 확인한 날짜를 적는다. 버전이 빨리 바뀌는 분야라 날짜 없는 주장은 믿지 않는다.

## 이 과정의 전제

- 대상: 이 리포의 10주 커리큘럼([`../curriculum-10weeks.md`](../curriculum-10weeks.md))을 마친 사람. Pod·DaemonSet·스케줄링·CRD를 안다고 본다.
- GPU 공유는 MIG·time-slicing·MPS만 다룬다. **하이퍼바이저 vGPU는 다루지 않는다**(베어메탈 또는 패스스루 GPU 노드 전제).
- 버전 기준(2026-10-10 확인): Kubernetes 지원 브랜치는 1.37·1.36·1.35, 1.34는 2026-10-27 EOL. [근거] <https://kubernetes.io/releases/>

## 각 절의 틀

모든 절은 같은 순서로 쓴다.

1. 개념: 왜 필요한가, 무엇을 푸는가
2. 그림: mermaid 한 장 이상
3. 실습: YAML과 명령, 기대 출력
4. **GPU 없이 확인하는 법**: kind + fake device plugin(확장 리소스 패치), `kubectl apply --dry-run=server`, 스케줄링만 보는 방법
5. 흔한 실수
6. 확인 문제 3개(답은 접어서)
7. 출처(링크 + 확인 날짜)

## 절 목록

### Part 1. Pod 하나가 GPU를 쓰기까지

- [ ] **01. GPU를 Pod에 붙이는 원리**
  device plugin API(kubelet 등록, `ListAndWatch`, `Allocate`), 확장 리소스 `nvidia.com/gpu`의 요청/제한 규칙(정수, limits만 써도 되고 requests=limits여야 함, 오버커밋 없음), NVIDIA Container Toolkit과 CDI, containerd 런타임 설정, `RuntimeClass`.
  GPU 없이: 노드 status에 `nvidia.com/gpu` 용량을 패치해 스케줄링만 재현.
- [ ] **02. NVIDIA GPU Operator 구성 요소**
  driver 컨테이너, container-toolkit, device-plugin, GPU Feature Discovery, NFD, DCGM·dcgm-exporter, MIG manager, validator. 어떤 순서로 뜨고 하나가 죽으면 무엇이 멈추나. 드라이버 사전 설치 노드와의 공존.
- [ ] **03. GPU 노드 고르기**
  NFD/GFD 라벨(`nvidia.com/gpu.product`, `nvidia.com/gpu.count` 등), nodeSelector·nodeAffinity, GPU 노드 taint와 toleration, 일반 Pod가 GPU 노드를 차지하지 않게 하는 패턴, PriorityClass.
- [ ] **04. GPU 나눠 쓰기: MIG·time-slicing·MPS**
  격리 수준(메모리·장애·QoS) 비교표, MIG 프로필과 single/mixed 전략, time-slicing의 `replicas` 의미와 메모리 비격리, MPS 제어 데몬. 언제 무엇을 쓰고 무엇을 하면 안 되나.
- [ ] **05. DRA(Dynamic Resource Allocation)**
  `DeviceClass`·`ResourceClaim`·`ResourceClaimTemplate`·`ResourceSlice`, CEL로 장치 고르기, 장치 공유. device plugin 모델과 무엇이 다른가, NVIDIA DRA 드라이버 현황.
  [근거] 핵심 API가 v1.34에서 GA(<https://kubernetes.io/blog/2025/09/01/kubernetes-v1-34-dra-updates/>, 2026-10-10 확인), 공식 문서 기능 상태는 "Stable since v1.35"로 기능 게이트가 잠김(<https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>, 2026-10-10 확인).

### Part 2. 여러 노드에 걸친 분산 잡

- [ ] **06. 멀티노드 분산 학습 기초**
  데이터 병렬(DDP)과 모델 병렬 개관, `torchrun`과 rendezvous(c10d), `MASTER_ADDR`·`WORLD_SIZE`·`RANK`, NCCL이 하는 일(all-reduce), Headless Service로 서로 찾기. 일반 `Job`(Indexed Job)만으로 2노드 DDP 띄워 보기.
- [ ] **07. Kubeflow Trainer**
  v1 Training Operator의 `PyTorchJob`·`MPIJob`과 v2의 `TrainJob`·`TrainingRuntime`. 무엇이 바뀌었고 새로 시작하면 어느 쪽을 쓰나.
  [근거] 최신 릴리스는 v2.3.0, v1 계열은 v1.9.4로 유지보수 릴리스 중(<https://github.com/kubeflow/trainer/releases>, 2026-10-10 확인).
- [ ] **08. KubeRay로 분산 학습·추론**
  `RayCluster`·`RayJob`·`RayService`의 GPU 워커 그룹, Ray Train과 Ray Serve에서 GPU 지정, 오토스케일링과 GPU 노드 비용. Kubeflow Trainer와 언제 갈리나.
- [ ] **09. 갱 스케줄링과 큐: Volcano·Kueue**
  기본 스케줄러가 Pod를 하나씩 놓아 생기는 부분 배치 교착, all-or-nothing 배치, 큐·쿼터·선점·공정 분배. Volcano(`PodGroup`)와 Kueue(`ClusterQueue`·`LocalQueue`·`Workload`, TopologyAwareScheduling) 비교, Trainer·KubeRay와 연동.

### Part 3. 성능과 운영

- [ ] **10. 노드 간 통신: RDMA·InfiniBand·GPUDirect RDMA**
  왜 TCP로는 부족한가, InfiniBand와 RoCEv2, GPUDirect RDMA, NVIDIA Network Operator(MOFED·RDMA shared device plugin·SR-IOV device plugin), Multus 보조 네트워크, Pod에서 `rdma/...` 리소스 요청.
- [ ] **11. 토폴로지 인지 배치**
  NVLink·NVSwitch와 PCIe, NUMA, GPU-NIC 짝짓기. kubelet Topology Manager 정책(`single-numa-node` 등)·CPU Manager·Memory Manager, `nvidia-smi topo -m` 읽기, 노드 간 배치(같은 랙·같은 스위치) 힌트.
- [ ] **12. 관측과 장애 대응**
  dcgm-exporter 지표와 Prometheus/Grafana, XID 오류 읽기, ECC·throttling, NCCL 디버그(`NCCL_DEBUG=INFO`, 타임아웃, hang), 잡 재시작·체크포인트와의 관계.

## 이어 볼 자료

겹치는 주제는 여기서 다시 쓰지 않고 출처나 별도 노트로 잇는다.

- 이 리포: [`../k8s-worker-components.md`](../k8s-worker-components.md)(kubelet·containerd), [`../containerd/`](../containerd/), [`../cgroup_namespace/`](../cgroup_namespace/), [`../k8s-logging-monitoring/`](../k8s-logging-monitoring/)
- 별도 스터디 노트(비공개): KubeRay 스터디(08절과 겹침), Kubeflow 스터디의 Training Operator 장(07절과 겹침), GPU·AI·LLM 인프라 커리큘럼(하드웨어·네트워크 심화, 10·11절과 겹침), NVIDIA Run:ai 가이드(09절의 스케줄러 비교에 참고)

## 공식 문서 시작점 (2026-10-10 확인)

- Kubernetes, GPU 스케줄링: <https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/>
- Kubernetes, device plugin: <https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/>
- Kubernetes, DRA: <https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>
- NVIDIA GPU Operator: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/>
- NVIDIA Network Operator(클라우드 오케스트레이션 문서 목록): <https://docs.nvidia.com/networking/software/cloud-orchestration/index.html>
- Kubeflow Trainer: <https://www.kubeflow.org/docs/components/trainer/>
- KubeRay: <https://docs.ray.io/en/latest/cluster/kubernetes/index.html>
- Kueue: <https://kueue.sigs.k8s.io/docs/> · Volcano: <https://volcano.sh/en/docs/>
- NCCL: <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/>

## 진행 기록

| 날짜 | 절 | 비고 |
|------|----|------|
| 2026-10-10 | 목차 | 12절 확정, 버전 기준 확인 |
