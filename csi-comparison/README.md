# Kubernetes CSI (Container Storage Interface) 비교 스터디

## 개요

이 스터디 자료는 Kubernetes에서 사용되는 다양한 CSI(Container Storage Interface) 드라이버를 이해하고 비교하기 위해 작성되었습니다.
CSI 표준 아키텍처부터 주요 벤더 구현체까지, 실무에서 활용 가능한 수준의 내용을 다룹니다.

## 목차

| 파일 | 내용 |
|------|------|
| [01_csi_overview.md](./01_csi_overview.md) | CSI 개념, 아키텍처, 컴포넌트 |
| [02_vsphere_csi.md](./02_vsphere_csi.md) | vSphere CSI Driver 상세 |
| [03_trident_csi.md](./03_trident_csi.md) | NetApp Trident CSI 상세 |
| [04_other_csi.md](./04_other_csi.md) | 기타 대표 CSI 드라이버 |
| [05_comparison.md](./05_comparison.md) | 전체 비교표 및 선택 가이드 |
| [06_hands_on.md](./06_hands_on.md) | 통합 실습 YAML 예제 |

## 학습 순서

1. **CSI 기초** → `01_csi_overview.md`: CSI가 무엇인지, 왜 필요한지 이해
2. **주요 드라이버** → `02_vsphere_csi.md`, `03_trident_csi.md`: 실무에서 많이 쓰이는 드라이버 심화
3. **클라우드 드라이버** → `04_other_csi.md`: AWS/GCP/Azure 등 퍼블릭 클라우드 CSI
4. **비교 분석** → `05_comparison.md`: 어떤 환경에 어떤 CSI를 쓸지 판단 기준
5. **실습** → `06_hands_on.md`: 직접 YAML 작성 및 적용 실습

## 사전 지식

- Kubernetes 기본 개념 (Pod, Deployment, StatefulSet)
- PV/PVC(PersistentVolume / PersistentVolumeClaim) 개념
- StorageClass 기본 이해
- kubectl 사용법

## 환경

- Kubernetes 1.24+
- kubectl 설치 및 클러스터 접근 권한
- 각 드라이버별 사전 요구사항은 해당 파일 참고

## 참고 자료

- [Kubernetes CSI 공식 문서](https://kubernetes-csi.github.io/docs/)
- [CSI Spec GitHub](https://github.com/container-storage-interface/spec)
- [vSphere CSI Driver 공식 문서](https://docs.vmware.com/en/VMware-vSphere-Container-Storage-Plug-in/index.html)
- [NetApp Trident 공식 문서](https://docs.netapp.com/us-en/trident/)
