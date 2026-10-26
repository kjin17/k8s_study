# VKS 애드온(Standard Packages) 교육 커리큘럼

> 시작: 2026-10-26. 한 회차에 한 절씩 `vks-addons/NN-<패키지>.md`로 채운다. 채운 절은 `[x]`로 바꾸고 파일 링크를 단다.
> 공개된 1차 출처(Broadcom TechDocs, 각 업스트림 공식 문서)만 쓴다.
> 주장마다 등급을 붙인다. **[근거]** 는 출처에 그대로 있는 것, **[추론]** 은 여러 출처를 엮어 직접 내린 결론이다.
> 출처 링크 옆에는 확인한 날짜를 적는다.

## 이 과정의 전제

- 대상: 이 리포의 [`../vks-cluster-management.md`](../vks-cluster-management.md), [`../carvel-kapp.md`](../carvel-kapp.md)를 읽은 사람. VKS 클러스터를 만들 줄 알고 kapp-controller가 무엇인지 안다고 본다.
- 범위: Broadcom이 **VKS Standard Packages** 저장소로 배포하는 패키지. 클러스터 생성 때 기본으로 깔리는 구성 요소(Antrea CNI, vSphere CSI, kapp-controller 자체 등)는 다루지 않는다.
- **판 호환은 이 과정에서 정리하지 않는다.** 패키지 판과 VKr(Kubernetes 판)의 짝은 공식 문서를 직접 볼 것.
  - VKS Standard Packages Release Notes: <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/release-notes/vks-standard-packages-release-notes.html> (2026-10-26 확인)
  - Broadcom 호환 매트릭스: <https://interopmatrix.broadcom.com/> (2026-10-26 확인)
- 오픈소스 업스트림을 Helm으로 까는 방법은 루트 [`../k8s-addon.sh`](../k8s-addon.sh)에 있다. 겹치는 패키지는 해당 절에서 그 스크립트로 링크만 하고 내용을 옮기지 않는다.

## 패키지 목록을 어디서 확정했나

[근거] 「Standard Packages for VKS Clusters」 표에 실린 패키지는 Cert Manager, Cluster Autoscaler, Contour, External DNS, External CSI Snapshot Validation Webhook·vSphere PV CSI Webhook, Fluent Bit, Harbor, Istio, Telegraf, Prometheus, Velero, Windows gMSA Webhook, SR-IOV Network Device Plugin 이다.
<https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-packages-for-tkg-service-clusters.html> (2026-10-26 확인, 페이지 표기 Last Updated October 6, 2026)

[근거] 릴리스 노트의 가장 최근 저장소 `3.6.0+20260521` 지원 표에는 위에 더해 AKO, Cilium, Gatekeeper, Helm Controller, Vault Injector 가 있다. 같은 표에 External CSI Snapshot Validation Webhook 은 없고, 이전 판(`3.6.0+20260211`)의 「Packages Removed」 목록에 들어 있다. (위 릴리스 노트, 2026-10-26 확인)

[근거] 「Standard Package Reference」 목차: Cert Manager, Contour, ExternalDNS, Fluent Bit, Prometheus, Harbor, Windows gMSA Webhook, Telegraf, Istio, AKO, Gatekeeper, Helm Controller, SR-IOV Network Device Plugin.
<https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference.html> (2026-10-26 확인)

[근거] Grafana, Alertmanager, Multus, Whereabouts, Calico, Pinniped 는 2026-10-26 기준 위 세 문서의 패키지 목록에 이름으로 나오지 않는다. 예전 TKG 문서에서 보던 이름이라도 여기서 절로 만들지 않는다. Alertmanager 가 Prometheus 패키지 안에 들어 있는지는 05절에서 Prometheus 패키지 참조 문서로 확인한다.

## 설치 경로 두 가지

[근거] VKS 3.5부터 **Add-on Management**(Supervisor 쪽 `AddonRepository`·`AddonRepositoryInstall`·`AddonRelease`·`AddonConfigDefinition` 등, `vmware-system-vks-public` 네임스페이스)가 생겼다. 저장소를 VKS가 자동으로 설치·업그레이드하고, 업그레이드 전 의존성 사전 점검을 한다. 기존 방식(클러스터 안에 PackageRepository·PackageInstall을 직접 만드는 방식)도 계속 쓸 수 있고, 기존 패키지를 새 방식으로 옮기는 절차가 따로 있다.
<https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters.html> (2026-10-26 확인)

[추론] 그래서 각 절의 「VKS에서 어떻게 들어가는가」는 두 경로를 나란히 적는다. 패키지마다 공식 문서가 어느 경로를 안내하는지가 다르므로(예: Gatekeeper·Cilium 은 Add-on 경로 안내) 절마다 출처로 확인한다.

## 각 절의 틀

1. 무엇을 하는가
2. VKS에서 어떻게 들어가는가: 패키지 저장소, Carvel kapp-controller의 `PackageInstall`과 values(데이터 값), Add-on Management 경로, 판 고르기와 업그레이드 흐름. Carvel 기초는 [`../carvel-kapp.md`](../carvel-kapp.md)로 잇는다
3. 실습: `PackageInstall`(또는 `AddonInstall`)·values YAML·확인 명령과 기대 출력
4. 업스트림 Helm 설치와 다른 점 (겹치면 [`../k8s-addon.sh`](../k8s-addon.sh) 링크)
5. 흔한 실수
6. 확인 문제 3개(답은 접어서)
7. 출처(링크 + 확인 날짜)

## 절 목록

순서는 설치 의존(인증서를 먼저 깔아야 하는 것부터)과 자주 쓰는 순으로 잡았다. [추론] 정확한 사전 조건은 각 절을 쓸 때 해당 설치 문서의 Prerequisites 로 다시 확인한다.

### Part 0. 공통

- [ ] **00. 패키지 저장소와 두 설치 경로**
  `vks-standard-packages` 저장소, `PackageRepository`·`PackageInstall`·values Secret, Add-on Management 리소스, 판 목록 보는 법, 업그레이드와 롤백, 레거시 패키지를 Add-on 방식으로 옮기기.
  출처: Installing VKS Add-ons on a VKS Cluster Using VKr for vSphere <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x.html>, Managing Add-ons(위 링크) (2026-10-26 확인)

### Part 1. 기반

- [ ] **01. Cert Manager** — 인증서 발급·갱신. 다른 패키지(웹훅·인그레스)가 기대는 기반. 업스트림 설치는 `k8s-addon.sh`.
  출처: Install Cert Manager <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-cert-manager.html>, Cert Manager Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/cert-manager-package-reference.html> (2026-10-26 확인)
- [ ] **02. Contour (Envoy 인그레스)** — 인그레스 컨트롤러·리버스 프록시. 업스트림 설치는 `k8s-addon.sh`.
  출처: Install Contour <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-contour-with-envoy(1).html>, Contour Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/contour-package-reference.html> (2026-10-26 확인)
- [ ] **03. ExternalDNS** — Service·Ingress 이름을 외부 DNS 레코드로 자동 등록.
  출처: Install ExternalDNS <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-externaldns.html>, ExternalDNS Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/externaldns-package-reference.html> (2026-10-26 확인)
- [ ] **04. Cluster Autoscaler** — 워커 노드 수 자동 조절. 공식 문서는 설치를 「Autoscaling VKS Clusters」 절에서 안내한다. 루트 [`../vks-cluster-management.md`](../vks-cluster-management.md)의 오토스케일링 부분과 잇는다.
  출처: Standard Packages for VKS Clusters 표의 Instructions 칸(위 링크) (2026-10-26 확인)

### Part 2. 관측

- [ ] **05. Prometheus** — 메트릭 수집·경보. 루트 [`../k8s-logging-monitoring/`](../k8s-logging-monitoring/)와 잇는다. 업스트림 설치는 `k8s-addon.sh`.
  출처: Install Prometheus <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus.html>, Prometheus Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/prometheus-package-reference.html> (2026-10-26 확인)
- [ ] **06. Fluent Bit** — 로그 전달. 업스트림 설치는 `k8s-addon.sh`.
  출처: Fluent Bit Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/fluent-bit-package-reference.html> (2026-10-26 확인)
- [ ] **07. Telegraf** — 메트릭 수집 에이전트. Prometheus와 무엇이 다른지.
  출처: Install Telegraf <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-telegraf.html>, Telegraf Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/telegraf-package-reference.html> (2026-10-26 확인)

### Part 3. 데이터 보호·저장소

- [ ] **08. Velero** — 백업·복구. 루트 [`../velero-csi-backup/`](../velero-csi-backup/)와 잇는다. 업스트림 설치는 `k8s-addon.sh`.
  출처: Standard Packages for VKS Clusters 표의 Instructions 칸(Backing Up and Restoring Cluster Workloads) (2026-10-26 확인)
- [ ] **09. vSphere PV CSI Webhook (와 스냅숏 검증 웹훅)** — 영구 볼륨 스냅숏. External CSI Snapshot Validation Webhook 이 최신 저장소에서 빠진 경위를 함께 본다.
  출처: Standard Packages for VKS Clusters 표의 Instructions 칸(Creating Snapshots in a VKS Cluster), 릴리스 노트의 Packages Removed (2026-10-26 확인)
- [ ] **10. Harbor** — 컨테이너 레지스트리. 루트 [`../harbor-registry.md`](../harbor-registry.md)와 잇는다.
  출처: Install the Harbor Registry <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-the-harbor-registry-using-the-tanzu-cli.html>, Harbor Components, Configuration, Data Values <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/harbor-components--configuration--data-values.html> (2026-10-26 확인)

### Part 4. 트래픽·정책·배포

- [ ] **11. Istio** — 서비스 메시. 루트 [`../istio-gateway-api.md`](../istio-gateway-api.md)와 잇는다. 업스트림 설치는 `k8s-addon.sh`.
  출처: Install Istio <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/installaing-and-using-istio/install-istio.html>, Istio Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/istio-package-reference.html> (2026-10-26 확인)
- [ ] **12. Gatekeeper (OPA)** — 승인 웹훅 기반 정책. [근거] 3.6.0+20260521 에서 처음 들어왔고 정책은 미리 넣지 않는다(릴리스 노트). 업스트림 설치는 `k8s-addon.sh`.
  출처: Install Gatekeeper Add-on Using Kubectl <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-gatekeeper/install-gatekeeper-addon-using-kubectl.html>, Gatekeeper Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/gatekeeper-addon-reference.html> (2026-10-26 확인)
- [ ] **13. Helm Controller** — Flux helm-controller(source-controller 포함)로 HelmRelease 배포. 루트 [`../helm.md`](../helm.md)·[`../k8s-cicd.md`](../k8s-cicd.md)와 잇는다.
  출처: Helm Controller Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/helm-controller-package-reference(2).html> (2026-10-26 확인)
- [ ] **14. Vault Injector** — Supervisor의 secret store와 통신해 Pod에 비밀값을 주입하는 agent injector. [근거] 클러스터 생성 때 Add-on 관리로 자동 설치를 지원한다(릴리스 노트).
  출처: VKS Standard Packages Release Notes(위 링크) (2026-10-26 확인)

### Part 5. 네트워크 확장·특수 노드

- [ ] **15. AKO (Avi Kubernetes Operator)** — Avi 로드밸런서 연동.
  출처: AKO Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/ako-package-reference.html> (2026-10-26 확인)
- [ ] **16. Cilium (대체 CNI)** — [근거] 표준 패키지 Add-on 틀로 대체 CNI 를 지원하며, 클러스터 생성 **전에** 저장소 설치와 AddonInstall 생성이 필요하다(릴리스 노트 3.6.0+20260320). 루트 [`../cni-comparison/`](../cni-comparison/)와 잇는다.
  출처: VKS Standard Packages Release Notes(위 링크) (2026-10-26 확인)
- [ ] **17. SR-IOV Network Device Plugin** — 노드의 SR-IOV 네트워크 자원을 찾아 광고.
  출처: SR-IOV Network Device Plugin Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/sriov-network-device-plugin-package-reference.html> (2026-10-26 확인)
- [ ] **18. Windows gMSA Webhook** — Windows 워커의 gMSA 신원.
  출처: Install Windows GMSA Webhook <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-windows-gmsa-webhook.html>, Windows gMSA Webhook Package Reference <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/windows-gmsa-webhook-package-reference.html> (2026-10-26 확인)

## 진행 기록

- 2026-10-26: 커리큘럼 작성. 공식 표·릴리스 노트(최신 저장소 3.6.0+20260521)·참조 목차 세 곳을 대조해 19절(00~18)로 확정.
