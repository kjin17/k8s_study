# 05. CSI 드라이버 전체 비교 및 선택 가이드

## 1. 전체 비교표

### 1.1 기능 비교

| CSI 드라이버 | 프로토콜 | RWO | ROX | RWX | RWOP | VolumeSnapshot | 동적 프로비저닝 | Resize | Topology |
|--------------|----------|:---:|:---:|:---:|:----:|:--------------:|:--------------:|:------:|:--------:|
| **vSphere CSI** | VMDK / NFS | ✅ | ✅ | ✅¹ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **NetApp Trident (NAS)** | NFS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **NetApp Trident (SAN)** | iSCSI/NVMe | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **AWS EBS CSI** | EBS (NVMe/SCSI) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **GCE PD CSI** | Persistent Disk | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Azure Disk CSI** | Managed Disk | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rook-Ceph RBD** | Ceph RBD | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rook-Ceph CephFS** | CephFS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **NFS Subdir** | NFS | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |

> ¹ vSphere RWX는 vSAN File Service 또는 vSAN 7.0+ 필요

---

### 1.2 환경별 적합성

| CSI 드라이버 | 온프레미스 (VMware) | 온프레미스 (물리) | AWS | GCP | Azure | 하이브리드 |
|--------------|:------------------:|:----------------:|:---:|:---:|:-----:|:----------:|
| vSphere CSI | ⭐⭐⭐⭐⭐ | ❌ | ❌ | ❌ | ❌ | △ (Tanzu) |
| NetApp Trident | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ (FSx) | ⭐⭐⭐ (GCV) | ⭐⭐⭐ (ANF) | ⭐⭐⭐⭐⭐ |
| AWS EBS CSI | ❌ | ❌ | ⭐⭐⭐⭐⭐ | ❌ | ❌ | △ (Outposts) |
| GCE PD CSI | ❌ | ❌ | ❌ | ⭐⭐⭐⭐⭐ | ❌ | △ (GDC) |
| Azure Disk CSI | ❌ | ❌ | ❌ | ❌ | ⭐⭐⭐⭐⭐ | △ (Arc) |
| Rook-Ceph | △ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| NFS Subdir | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | △ | △ | △ | ⭐⭐⭐ |

---

### 1.3 성능 및 운영 복잡도

| CSI 드라이버 | 읽기/쓰기 성능 | 지연 시간 | 운영 복잡도 | 초기 설정 난이도 |
|--------------|:-------------:|:--------:|:-----------:|:---------------:|
| vSphere CSI | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ (낮음) | ⭐⭐ (낮음) |
| NetApp Trident | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ (중간) | ⭐⭐⭐ (중간) |
| AWS EBS CSI | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐ (매우 낮음) | ⭐ (매우 낮음) |
| GCE PD CSI | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐ (매우 낮음) | ⭐ (매우 낮음) |
| Azure Disk CSI | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐ (매우 낮음) | ⭐ (매우 낮음) |
| Rook-Ceph | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ (매우 높음) | ⭐⭐⭐⭐⭐ (매우 높음) |
| NFS Subdir | ⭐⭐⭐ | ⭐⭐⭐ | ⭐ (매우 낮음) | ⭐ (매우 낮음) |

---

### 1.4 엔터프라이즈 기능 비교

| CSI 드라이버 | HA/Failover | 데이터 복제 | 암호화 | 멀티테넌시 | SLA/지원 |
|--------------|:-----------:|:-----------:|:------:|:----------:|:--------:|
| vSphere CSI | ✅ (vSAN HA) | ✅ (vSAN) | ✅ (vSAN) | △ | VMware |
| NetApp Trident | ✅ (ONTAP HA) | ✅ (SnapMirror) | ✅ (NVE/NAE) | ✅ | NetApp |
| AWS EBS CSI | ✅ (EBS Multi-AZ) | ✅ (EBS 스냅샷) | ✅ (KMS) | ✅ (IAM) | AWS |
| GCE PD CSI | ✅ (Regional PD) | ✅ (PD 스냅샷) | ✅ (CMEK) | ✅ (IAM) | Google |
| Azure Disk CSI | ✅ (Zone) | ✅ (스냅샷) | ✅ (DES) | ✅ (RBAC) | Microsoft |
| Rook-Ceph | ✅ (OSD 복제) | ✅ (RBD mirroring) | ✅ (Ceph 암호화) | ✅ | 커뮤니티 |
| NFS Subdir | △ (NFS 서버 의존) | ❌ | ❌ | ❌ | 커뮤니티 |

---

## 2. 사용 사례별 선택 가이드

### 2.1 환경별 권장 CSI

#### VMware vSphere 온프레미스 환경

```
권장: vSphere CSI Driver (1순위) + NetApp Trident (NFS 추가 필요 시)

이유:
- vSphere 환경에 최적화된 네이티브 드라이버
- vSAN과 완벽 통합 (Storage Policy 기반 프로비저닝)
- Tanzu 환경에서 기본 제공
- NFS/RWX가 필요하다면 Trident NAS 추가

단점:
- vSAN File Service 없으면 RWX 미지원
- vSphere 라이선스에 의존
```

#### NetApp 스토리지 환경 (온프레미스/하이브리드)

```
권장: NetApp Trident

이유:
- ONTAP, Element, SolidFire 등 NetApp 전 제품 지원
- NFS(RWX), iSCSI(RWO) 모두 지원
- Volume Import, QoS, 고급 스냅샷 기능
- AWS FSx, Azure ANF, GCP GCV 등 클라우드 NetApp도 지원 → 하이브리드 클라우드 일관성

단점:
- NetApp 스토리지 없으면 사용 불가
- 초기 Backend 설정 복잡
```

#### AWS EKS 환경

```
권장: AWS EBS CSI Driver (블록) + Amazon EFS CSI Driver (NFS/RWX)

이유:
- AWS 공식 드라이버, EKS Add-on으로 쉽게 설치
- IAM Role 기반 인증 (IRSA)
- gp3 볼륨으로 성능/비용 최적화

RWX가 필요한 경우:
- Amazon EFS CSI Driver (완전 관리형 NFS)
- 또는 Amazon FSx for NetApp ONTAP + Trident
```

#### GCP GKE 환경

```
권장: GCE PD CSI Driver (블록) + Filestore CSI Driver (NFS/RWX)

이유:
- GKE에 기본 내장, 별도 설치 불필요
- Regional PD로 Zone 장애 대응
- Workload Identity로 보안 강화
```

#### Azure AKS 환경

```
권장: Azure Disk CSI Driver (블록) + Azure File CSI Driver (NFS/RWX)

이유:
- AKS에 기본 내장
- Ultra Disk로 초고성능 요구 사항 대응
- Azure File로 SMB/NFS RWX 지원
```

#### 온프레미스 (베어메탈, 자체 스토리지 없음)

```
권장: Rook-Ceph (소규모~대규모) 또는 NFS Subdir (소규모)

Rook-Ceph:
- 자체 분산 스토리지 필요 시 최선
- 높은 설치/운영 난이도
- 엔터프라이즈 기능 (RBD mirroring, CephFS)
- 최소 3개 노드 + 3개 OSD 디스크 필요

NFS Subdir:
- 기존 NFS 서버 활용 시
- 가장 단순한 구성
- VolumeSnapshot 미지원, 성능 제한
```

---

### 2.2 워크로드별 권장 스토리지

| 워크로드 | 권장 AccessMode | 권장 CSI | 이유 |
|----------|:--------------:|---------|------|
| 데이터베이스 (MySQL, PostgreSQL) | RWO | EBS / vSphere VMDK / Trident iSCSI | 낮은 지연, 단독 접근 |
| 메시지 큐 (Kafka, RabbitMQ) | RWO | EBS / vSphere / Trident iSCSI | 순차 쓰기 성능 중요 |
| 공유 파일 (CMS, NAS 마운트) | RWX | NFS Subdir / CephFS / Trident NAS | 다중 Pod 동시 접근 |
| 머신러닝 학습 데이터셋 | RWX | EFS / Trident NAS / CephFS | 대용량 읽기, 공유 필요 |
| CI/CD 빌드 캐시 | RWX | NFS / CephFS | 다수 워커 동시 접근 |
| StatefulSet (ZooKeeper, etcd) | RWO | EBS / vSphere / Trident iSCSI | 각 Pod 전용 볼륨 |
| 웹 서버 정적 파일 | RWX or ROX | CephFS / NFS | 여러 Pod에서 읽기 |
| 개발/테스트 환경 | RWO | NFS Subdir / Rook-Ceph | 빠른 구성, 비용 절감 |

---

### 2.3 성능 기준 선택

#### 초저지연 / 고IOPS (데이터베이스, 금융 트랜잭션)

```
1순위: NetApp Trident + ONTAP AFF (NVMe-TCP / iSCSI)
2순위: AWS EBS io2 Block Express
3순위: Azure Disk UltraSSD
4순위: vSphere CSI + vSAN All-Flash
```

#### 대용량 처리량 (빅데이터, ML/AI)

```
1순위: NetApp Trident + ONTAP AFF (병렬 NFS)
2순위: Rook-Ceph RBD (클러스터 확장 가능)
3순위: AWS EBS gp3 (throughput 최대 1000 MiB/s)
```

#### 비용 효율 (일반 워크로드)

```
1순위: NFS Subdir (기존 NFS 서버 활용)
2순위: AWS EBS gp3 / GCE pd-balanced
3순위: Rook-Ceph (하드웨어 비용만, 소프트웨어 무료)
```

---

## 3. 결정 트리

```
내 환경은?
│
├─ VMware vSphere → vSphere CSI Driver
│    └─ RWX 필요? → vSAN File Service 또는 Trident NAS 추가
│
├─ NetApp 스토리지 보유 → NetApp Trident
│    ├─ ONTAP NAS → NFS, RWX 가능
│    └─ ONTAP SAN → iSCSI, RWO만
│
├─ AWS → EBS CSI (블록) + EFS CSI (NFS RWX)
│
├─ GCP → GCE PD CSI (블록) + Filestore CSI (NFS RWX)
│
├─ Azure → Azure Disk CSI (블록) + Azure File CSI (NFS/SMB RWX)
│
└─ 온프레미스 (자체 스토리지 없음)
     ├─ 기존 NFS 서버 있음 → NFS Subdir External Provisioner
     ├─ 3+ 노드, 전용 디스크 → Rook-Ceph
     └─ 소규모, 빠른 구성 → Longhorn (Rancher)
```

---

## 4. 비교 요약

| 항목 | vSphere CSI | Trident NAS | Trident SAN | EBS CSI | Rook-Ceph | NFS Subdir |
|------|:-----------:|:-----------:|:-----------:|:-------:|:---------:|:----------:|
| 설치 난이도 | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐⭐ | ⭐ |
| RWX 지원 | △ | ✅ | ❌ | ❌ | ✅ (CephFS) | ✅ |
| 스냅샷 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Resize | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 비용 | 라이선스 | 라이선스 | 라이선스 | 사용량 | 오픈소스 | 오픈소스 |
| 기업 지원 | VMware | NetApp | NetApp | AWS | 커뮤니티 | 커뮤니티 |
| 성능 | 높음 | 매우 높음 | 매우 높음 | 높음 | 중간~높음 | 중간 |
