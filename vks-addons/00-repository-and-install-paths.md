# 00. 패키지 저장소와 두 설치 경로

> 커리큘럼: [CURRICULUM.md](CURRICULUM.md) · 작성 2026-10-27
> 등급: **[근거]** 출처에 그대로 있는 것, **[추론]** 여러 출처를 엮어 직접 내린 결론.
> 기준 판: VKS Add-ons `3.8.0+20261021` (9.1 VKS Add-ons Release Notes, 2026-10-27 확인, 페이지 표기 Last Updated October 26, 2026). 판 호환은 이 문서에서 정리하지 않는다. [공식 호환 매트릭스](https://interopmatrix.broadcom.com/)와 릴리스 노트를 직접 볼 것.

이 절은 뒤의 01~25절이 모두 기대는 공통 바탕이다. 개별 패키지 이야기는 하지 않고, 「애드온이 어디서 오고, 어떤 리소스로 클러스터에 깔리며, 판을 어떻게 고르고 올리는가」만 다룬다.

---

## 1. 무엇을 하는가

VKS 애드온은 Broadcom 이 오픈소스 쿠버네티스 부가 기능(cert-manager, Contour, Prometheus 등)을 검증해 **Carvel 패키지 저장소** 하나로 묶어 배포하는 것이다.

- [근거] 3.7.0 판부터 예전의 「Core」「Standard」 패키지라는 말을 버리고 **VKS Add-Ons** 라는 하나의 틀로 묶었다. UI·CLI·API 로 깔고 관리한다. (9.1 Release Notes, About VKS Add-ons)
- [근거] 애드온마다 지원 등급이 있다. **Product**(Broadcom 이 패키징·검증, 런타임 장애까지 지원), **Partner**(ISV 가 런타임 담당), **Ecosystem**(Broadcom 은 패키징·서명·수명주기만, 런타임 버그는 업스트림 몫), **Community**(공식 지원 없음). (같은 출처, VKS Add-ons Support Tiers)
- [근거] Product 등급이라도 지원 범위는 Broadcom TechDocs 에 문서화된 값까지다. 업스트림 문서에만 있는 옵션, 사용자가 만든 YTT overlay, 직접 만든 Helm 차트는 지원 밖이다. (같은 출처, Scope of Support Boundaries & Exclusions)

[추론] 그래서 각 절에서 values 를 바꿀 때는 「업스트림 Helm 차트에 이런 값이 있다」가 아니라 「Broadcom 패키지 참조 문서에 이 키가 있다」를 기준으로 삼는다. 업스트림에만 있는 키를 overlay 로 밀어 넣으면 동작하더라도 지원이 끊긴다.

## 2. VKS 에서 어떻게 들어가는가

### 2.1 저장소: 어디서 오는가

[근거] 3.8.0+20261021 저장소 주소(9.1 Release Notes):

```
projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/3.8.0-20261021/vks-addons:3.8.0-20261021
```

- [근거] 3.7.0+20260618 부터 이름은 「Add-ons」로 바뀌었지만, 기존 배포 스크립트·에어갭 동기화·CI 가 깨지지 않도록 **경로는 `vks-standard-packages/...` 그대로** 둔다. (9.1 Release Notes, 3.7.0+20260618 절)
- [근거] Add-on 방식에 쓰는 `AddonRepository` YAML 은 Broadcom Support Portal(Downloads → Supervisor Services → vSphere Kubernetes Service → Drivers & Tools)에서 받는다. VCF Download Tool 로는 `--vcf-version 9.1 --component=VKS_STANDARD_PACKAGES --component-version=3.8.0+20261021` 로 받는다. (9.1 Release Notes, 3.8.0+20261021 절)
- [근거] 3.5 판의 9.0 문서 예시는 경로 모양이 다르다: `projects.packages.broadcom.com/vsphere/supervisor/packages/2025.10.22/vks-standard-packages:3.5.0-20251022`. (Update an Add-on Repository Install, 9.0)

[추론] 경로 규칙이 판마다 바뀌어 왔으므로 주소를 짐작해서 만들지 말고, 쓰려는 판의 릴리스 노트 절에 적힌 주소를 그대로 복사한다.

### 2.2 두 설치 경로 한눈에

| | 레거시 패키지 방식 | Add-on Management 방식 |
|---|---|---|
| 도입 | VKr 에 kapp-controller 가 들어 있던 때부터 | VKS 3.5 부터 |
| 어디에 리소스를 만드나 | **워크로드 클러스터 안** (`PackageRepository`, `PackageInstall`) | **Supervisor** (`AddonInstall`, `AddonConfig` 등) |
| 저장소 설치 | 사용자가 클러스터마다 `vcf package repository add` | VKS 가 내장 저장소를 모든 클러스터에 자동 설치·업그레이드 |
| 설정값 | values 파일 (`--values-file`) | `AddonConfig.spec.values` (스키마 검증) |
| 클러스터 업그레이드 때 | 사용자가 직접 호환 판으로 올림 | 사전 점검 후 필요하면 함께 올리고, 호환 판이 없으면 업그레이드를 막음 |
| 여러 클러스터 | 클러스터마다 반복 | 라벨 선택자로 여러 클러스터에 한 번에 |

근거: [근거] Managing Add-ons in VKS Clusters(9.0), Manage Package Repository(9.0), Managing VKS Standard Packages(9.0). 표의 정리 자체는 [추론].

- [근거] 레거시 방식은 계속 쓸 수 있다. 3.8.0+20261021 릴리스 노트도 「The original package way still works」라고 적고 저장소 주소를 함께 준다.
- [근거] 레거시 저장소 절차(`Manage Package Repository`)에는 「Add-on management 를 쓸 때는 이 절차가 필요 없다」는 안내가 붙어 있다.

### 2.3 레거시 방식: 클러스터 안의 Carvel 리소스

Carvel·kapp-controller 기초는 [`../carvel-kapp.md`](../carvel-kapp.md)의 [6. kapp-controller & App CRD](../carvel-kapp.md#6-kapp-controller--app-crd-gitops)를 먼저 본다. 여기서는 VKS 에 특유한 점만 적는다.
PackageInstall 의 values 스키마 보기·ytt overlay 덧씌우기(와 그것이 VKS 지원 밖이라는 경계)는 [`../carvel-ytt-for-kapp.md`](../carvel-ytt-for-kapp.md) 6·7절.

- [근거] VKr 이미지에 Carvel 패키징 시스템과 kapp-controller 가 들어 있고, VKr 이 자동으로 관리한다. (General Requirements, 9.0)
- [근거] `tkg-system` 네임스페이스는 클러스터 kapp-controller 의 **전역 네임스페이스**다. 저장소를 여기에 추가하면 Package·PackageMetadata 가 다른 모든 네임스페이스에서 보인다. (Manage Package Repository, 9.0)
- [근거] 저장소에 있는 패키지가 모두 VKS 지원 대상은 아니다. 지원 목록은 「Standard Packages for VKS Clusters」 표로 확인한다. (같은 출처)
- [근거] 패키지 구성 요소는 패키지를 설치한 네임스페이스와 다른 시스템 네임스페이스에서 돈다(예: Contour·Envoy 는 `tanzu-system-ingress`, Harbor 는 `tanzu-system-registry`). **`tanzu-system-` 으로 시작하는 네임스페이스에 패키지를 설치하지 말 것.** (Managing VKS Standard Packages, 9.0)
- [근거] 설치 네임스페이스(`-n`)는 미리 있어야 한다. 이 네임스페이스에는 PackageInstall·App 같은 「패키지를 기술하는 리소스」만 들어가고, 실제 Pod·Service 는 패키지 설정의 네임스페이스로 간다. (같은 출처)

### 2.4 Add-on Management 방식: Supervisor 쪽 리소스

[근거] VKS 는 `vmware-system-vks-public` 이라는 공개 네임스페이스를 미리 만들어, 모든 vSphere Namespace 가 공용 리소스를 읽게 한다. (Managing Add-ons in VKS Clusters, 9.0)

| 리소스 | 위치 | 하는 일 |
|---|---|---|
| `Addon` | `vmware-system-vks-public` | Supervisor 에서 쓸 수 있는 애드온 하나 |
| `AddonRepository` | `vmware-system-vks-public` | 워크로드 클러스터에 깔 PackageRepository 정의 |
| `AddonRepositoryInstall` | `vmware-system-vks-public` | AddonRepository 를 어느 클러스터에 깔지 묶음 |
| `AddonRelease` | `vmware-system-vks-public` | 애드온 판 하나의 불변 메타데이터(판, 호환 제약, 다른 애드온 의존) |
| `AddonConfigDefinition` | `vmware-system-vks-public` | 설정 템플릿·스키마. 하위 리소스 `ServiceAccountExport` 로 Supervisor 접근 권한 토큰을 워크로드 클러스터에 만들어 줌(예: Cluster Autoscaler) |
| `AddonInstall` | 클러스터 네임스페이스 또는 공개 네임스페이스 | 「이 애드온을 이 클러스터들에 깔아라」는 원하는 상태 |
| `ClusterAddon` | 클러스터 네임스페이스 | 클러스터 하나에 깔릴 애드온 하나, 상태 보고 |
| `AddonConfig` | 클러스터 네임스페이스 | 스키마 검증을 거치는 설정값 |

근거: [근거] Managing Add-ons in VKS Clusters(9.0)의 리소스 표를 옮겨 줄였다.

- [근거] 공개 네임스페이스에는 VCF 가 만든 `AddonInstall` 이 들어 있어 여러 네임스페이스의 애드온을 관리한다. 네임스페이스 편집 권한이 있는 사용자는 자기 네임스페이스에 `AddonInstall` 을 만들어 공개 쪽 설정을 덮어쓰거나, 공개 쪽에 없는 애드온을 깔 수 있다. (같은 출처)
- [근거] Starting with VKS 3.7.0, `AddonRepositoryInstall` 을 여러 개 둘 수 있다. (9.1 Release Notes, 3.7.0+20260618 절)

[추론] 흐름을 한 줄로 쓰면: `AddonRepository` → (`AddonRepositoryInstall` 로 배포) → `Addon`·`AddonRelease` 가 보임 → 사용자가 `AddonInstall` 작성 → VKS 가 클러스터마다 `ClusterAddon`·`AddonConfig` 를 만들고 → 워크로드 클러스터 안에서는 결국 kapp-controller 의 PackageInstall 로 설치된다. 마지막 단계는 레거시 방식과 같은 엔진이다.

### 2.5 판 고르기와 업그레이드

- [근거] 레거시: 판을 올리기 전에 보통 저장소부터 새 URL 로 `vcf package repository update` 하고, 그 뒤 `vcf package installed update ... -v <판>` 으로 올린다. 저장소 URL 에 태그를 빼면 최신 VKS 릴리스의 저장소 태그가 쓰인다. (Manage Package Repository, Managing VKS Standard Packages, 9.0)
- [근거] Add-on: VKS 3.5 이상에는 표준 저장소가 내장돼 모든 VKS 클러스터에 깔린다. 다른 저장소 판이나 사설 레지스트리를 쓰려면 새 `AddonRepository` 를 만들고, `default-addon-repo-install` 에 `addons.kubernetes.vmware.com/skip-vks-managed-addon-repository-update` 주석을 단 뒤 `addonRepositoryRef` 를 바꾼다. **이 주석을 지우면 VKS 내장 저장소로 되돌아간다.** 이 작업은 Supervisor Admin 역할이 필요하다. (Update an Add-on Repository Install, 9.0)
- [근거] 클러스터 업그레이드 전에 VKS 는 깔린 애드온이 목표 Kubernetes·KR 판과 맞는지 사전 점검한다. 맞지 않으면 호환되는 다른 AddonRelease 를 찾아 함께 올리고, 없으면 클러스터 업그레이드를 막는다. AddonRelease 가 「업그레이드 중 어느 단계에서 반드시 올라가야 하는지」를 지정할 수 있다. (Managing Add-ons in VKS Clusters, 9.0)
- [근거] 3.8.0+20261021 의 Helm Controller 1.5.5 판에 dry-run·롤백 기능을 위한 `ExtendedHelmRelease` 가 들어왔다. External Secrets Operator 와 Tekton Operator 는 「Helm add-on」으로 처음 들어왔다. (9.1 Release Notes)

[추론] 「Helm add-on」이 Add-on Management 에서 어떤 리소스 모양으로 설치되는지는 2026-10-27 기준 9.1 문서 세트의 Add-on 관리 페이지 주소를 아직 열어 보지 못했다(9.0 경로를 9.1 로 바꾼 주소는 404). 24·25절을 쓸 때 9.1 설치 문서로 확인한다.

## 3. 실습

> 아래 명령은 공식 문서의 예시를 순서대로 엮은 것이다. 이름(`cluster0`, `test`, `my-packages`)은 예시 값이다. 판 번호는 자기 환경의 `AddonRelease`·`vcf package available get` 출력으로 고른다.

### 3.1 Add-on 방식으로 Prometheus 깔기 (Supervisor 컨텍스트)

```bash
# Supervisor API 서버 컨텍스트에서
# 1) 내장 저장소 설치가 준비됐는지
kubectl get addonrepositoryinstall -n vmware-system-vks-public
kubectl get addonrepositoryinstall -n vmware-system-vks-public default-addon-repo-install

# 2) 쓸 수 있는 애드온과 판
kubectl get addons -n vmware-system-vks-public
kubectl get addonreleases -n vmware-system-vks-public \
  -l addon.kubernetes.vmware.com/addon-name=prometheus
```

[근거] 기대 출력(문서 예시, 3.5 시절): `addons` 목록에 `ako`, `cert-manager`, `cluster-autoscaler`, `contour`, `external-dns`, `fluent-bit`, `harbor`, `istio`, `prometheus`, `sriov-network-device-plugin`, `telegraf`, `velero`, `vsphere-pv-csi-webhook`, `windows-gmsa-webhook` 등이 보이고, AddonRelease 이름은 `prometheus.kubernetes.vmware.com.3.5.0-vmware.1-vks.2` 처럼 `<패키지>.<판, +는 ->` 모양이다. (View Available Add-ons Using Kubectl, 9.0)

```yaml
# addoninstall.yaml  (클러스터 네임스페이스에 만든다)
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonInstall
metadata:
  name: cluster0-prometheus
  namespace: test
spec:
  addonRef:
    name: prometheus
  clusters:
  - selector:
      matchLabels:
        cluster.x-k8s.io/cluster-name: cluster0
```

```bash
kubectl apply -f addoninstall.yaml

# 3) 깔렸는지, 설정은 어디 있는지
kubectl get clusteraddon -n test
kubectl get clusteraddon -n test <clusteraddon-name> -ojsonpath='{.status.addonConfigName}'
kubectl get addonconfig -n test <addonconfig-name> -oyaml
```

- [근거] `AddonInstall` 의 뼈대(`addonRef.name`, `clusters[].selector.matchLabels`)는 Install an Add-on Using Kubectl(9.0) 예시 그대로다. 문서 예시의 이름은 `cluster-test0-` 로 끝에 하이픈이 붙어 있는데, 여기서는 읽기 쉬운 이름으로 바꿨다. [추론]
- [근거] Cluster Autoscaler 는 이 일반 절차 대신 「Install Cluster Autoscaler with Add on Management」를 따르라고 한다. (같은 출처) → 04절.

### 3.2 설치할 때부터 값을 넣기 / 깔린 뒤 값 바꾸기

```yaml
# 설치 전에 만든다. 이름 규칙: <클러스터 이름>-<애드온 이름>
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonConfig
metadata:
  name: cluster0-prometheus
  namespace: test
  annotations:
    clusteraddon.addons.kubernetes.vmware.com/owned-for-deletion: "true"
spec:
  values:
    # Prometheus 패키지 참조 문서에 있는 키만 넣는다 (05절)
```

- [근거] 설치 전 설정은 `<cluster-name>-<addon-name>` 이름의 AddonConfig 를 클러스터 네임스페이스에 만들고 `spec.values` 에 덮어쓸 값을 넣는다. `owned-for-deletion` 주석이 없으면 ClusterAddon 을 지워도 AddonConfig 는 남는다. 이미 깔린 애드온에는 이 절차를 쓰지 않는다. (Configure an Add on at Installation Time Using Kubectl, 9.0)
- [근거] 깔린 뒤에는 ClusterAddon 의 `status.addonConfigName` 으로 AddonConfig 를 찾아 `spec.values` 를 고친다. 기본값은 AddonConfigDefinition 에서 온다. (Configure an Installed Add-on Using Kubectl, 9.0)
- [추론] 이 문서는 AddonConfig 를 글로만 설명하고 YAML 예시를 싣지 않는다. 위 YAML 의 `apiVersion` 은 같은 API 그룹의 다른 리소스 예시(`addons.kubernetes.vmware.com/v1alpha1`)에서 가져왔다. 적용 전에 `kubectl api-resources | grep -i addonconfig` 로 확인한다.

### 3.3 레거시 방식으로 같은 일 (워크로드 클러스터 컨텍스트)

```bash
vcf package repository add standard-package-repo \
  --url <쓰려는 판의 릴리스 노트에 적힌 저장소 주소> \
  -n tkg-system
vcf package repository list -n tkg-system
vcf package available list -n tkg-system
vcf package available get prometheus.kubernetes.vmware.com -n tkg-system

kubectl create namespace my-packages
vcf package install prometheus -p prometheus.kubernetes.vmware.com \
  -v <판> --values-file prometheus-values.yaml -n my-packages
vcf package installed list -A
vcf package installed get prometheus -n my-packages --values-file-output current-values.yaml
```

[근거] 명령 모양은 Manage Package Repository·Managing VKS Standard Packages(9.0). 패키지 이름 `prometheus.kubernetes.vmware.com` 은 Update an Add-on Repository Install(9.0) 예시의 `package-offerings` 에 나온 이름이다.

### 3.4 레거시에서 Add-on 으로 옮기기

```bash
# 워크로드 클러스터 컨텍스트: 기존 values 백업
vcf context use <workload-cluster-context>
vcf package installed list -A
vcf package installed get <package-name> -n <package-namespace> --values-file-output values.out

# Supervisor 컨텍스트(클러스터 네임스페이스): 옮기기
vcf context use <supervisor-context>:<workload-cluster-namespace>
vcf addon available list
vcf addon available list <addon-name>
vcf addon install migrate <package-name> --addon-name <addon-name> \
  --cluster-name <workload-cluster-name> -v <addon-version> -f values.out
```

[근거] Migrate a Legacy Package Add-on(9.0). `values.out` 이 비어 있으면 기본 설정이라는 뜻이고 `-f` 를 빼도 된다. 패키지 네임스페이스를 적어 두라고 하는데, 다시 돌릴 때 `--existing-package-install-namespace` 에 쓰기 때문이다.

## 4. 업스트림 Helm 설치와 다른 점

오픈소스 차트를 Helm 으로 직접 까는 방법은 루트 [`../k8s-addon.sh`](../k8s-addon.sh)에 있다. 여기서는 차이만 적는다.

1. [근거] 이미지·차트가 Broadcom 레지스트리(`projects.packages.broadcom.com`)에서 오고, 판 이름에 `+vmware.N-vks.N` 꼬리가 붙는다(예: `1.18.2+vmware.2-vks.2`). (Update an Add-on Repository Install, 9.0)
2. [근거] 설정 키는 Broadcom 패키지 참조 문서에 있는 것만 지원된다. 업스트림 차트에만 있는 값이나 사용자 YTT overlay 는 지원 밖이다. (9.1 Release Notes)
3. [근거] Add-on 방식은 클러스터 업그레이드와 애드온 판을 묶어 사전 점검한다. Helm 으로 깐 것은 VKS 가 모르므로 이 점검에 들어가지 않는다. (Managing Add-ons in VKS Clusters, 9.0) [추론] 업그레이드 뒤 깨지는지는 사람이 따로 봐야 한다.
4. [추론] `helm list` 에는 보이지 않는다. 레거시는 `vcf package installed list -A`·`kubectl get packageinstall -A`, Add-on 은 Supervisor 쪽 `kubectl get clusteraddon -n <ns>` 로 본다.

## 5. 흔한 실수

1. **9.0 문서 페이지의 판을 「최신」으로 읽기.** [근거] 9.0 VKS Standard Packages Release Notes 는 3.6.0+20260521 까지만 싣는다. 2026-10-27 기준 가장 높은 판(3.8.0+20261021)은 9.1 VKS Add-ons Release Notes 에 있다. 이 커리큘럼도 처음에 이 실수를 했다(커리큘럼 진행 기록 참고).
2. **`tanzu-system-*` 네임스페이스에 패키지 설치.** [근거] 문서가 금지한다(2.3).
3. **덮어쓴 저장소의 주석을 지우기.** [근거] `skip-vks-managed-addon-repository-update` 주석이 없어지면 `AddonRepositoryInstall` 이 VKS 내장 저장소로 돌아간다(2.5). 에어갭 환경이면 [추론] 외부 레지스트리를 못 끌어와 설치가 멈출 수 있다.
4. **`package-offerings` 주석 손대기.** [근거] 사설 레지스트리용으로 `AddonRepository` 를 복사할 때 이름과 URL 외에는 바꾸지 말고, 특히 `addons.kubernetes.vmware.com/package-offerings` 주석은 건드리지 말라고 한다. (Update an Add-on Repository Install, 9.0)
5. **라벨 키를 문서 그대로 복사.** [근거] View Available Add-ons(9.0) 한 쪽 안에서 AddonRelease 라벨 키가 `addon.addons.kubernetes.vmware.com/addon-name`(설명 줄)과 `addon.kubernetes.vmware.com/addon-name`(예시 줄) 두 가지로 적혀 있다. [추론] 결과가 비면 `kubectl get addonreleases -n vmware-system-vks-public --show-labels` 로 실제 키를 먼저 본다.
6. **설치 전용 AddonConfig 를 깔린 뒤에 만들기.** [근거] 이미 깔린 애드온은 「Configure an Installed Add-on」 절차로 기존 AddonConfig 를 고친다(3.2).
7. **기본 StorageClass 없는 클러스터에 저장소가 필요한 패키지 설치.** [근거] Prometheus 는 기본 StorageClass 가 필요하고, 기본 PVC 크기는 Prometheus Server 150Gi, Alertmanager 2Gi 다. vSphere Namespace 의 저장소 한도가 PVC 합계보다 커야 한다. (General Requirements, 9.0)

## 6. 확인 문제

1. Add-on Management 방식에서 사용자가 직접 만드는 리소스와 VKS 가 만들어 주는 리소스를 하나씩 들고, 각각 어느 네임스페이스에 있는지 말해 보라.
<details><summary>답</summary>

사용자가 만드는 것: `AddonInstall`(클러스터 네임스페이스 또는 공개 네임스페이스), 필요하면 설치 전 `AddonConfig`(클러스터 네임스페이스). VKS 가 만드는 것: 클러스터마다의 `ClusterAddon`(클러스터 네임스페이스), 기본 `AddonRepositoryInstall`·`Addon`·`AddonRelease`(`vmware-system-vks-public`). [근거] Managing Add-ons in VKS Clusters.
</details>

2. 클러스터를 새 VKr 로 올리려는데, 깔려 있는 애드온 판이 새 VKr 과 맞지 않는다. Add-on 방식이면 무슨 일이 일어나고, 호환 판이 아예 없으면 어떻게 되는가?
<details><summary>답</summary>

VKS 가 사전 점검에서 호환되는 다른 AddonRelease 를 찾아 클러스터 업그레이드 중에 함께 올린다. 호환 판이 없으면 클러스터 업그레이드가 막힌다. [근거] Managing Add-ons in VKS Clusters, Add-on Compatibility Checks.
</details>

3. 레거시 방식에서 저장소를 `tkg-system` 에 추가하는 이유는 무엇이고, 패키지는 어느 네임스페이스에 설치하면 안 되는가?
<details><summary>답</summary>

`tkg-system` 은 kapp-controller 의 전역 네임스페이스라 그곳의 Package·PackageMetadata 가 모든 네임스페이스에서 보인다. 패키지는 `tanzu-system-` 으로 시작하는 네임스페이스에 설치하면 안 된다(그곳은 패키지 구성 요소가 도는 시스템 네임스페이스). [근거] Manage Package Repository, Managing VKS Standard Packages.
</details>

## 7. 출처 (모두 2026-10-27 확인)

- VKS Add-ons Release Notes (9.1, Last Updated October 26, 2026): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html>
- Managing Add-ons in VKS Clusters (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters.html>
- Update an Add-on Repository Install (9.0, Last Updated October 6, 2026): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/install-an-addon-repository.html>
- View Available Add-ons Using Kubectl (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/view-available-addons.html>
- Install an Add-on Using Kubectl (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/install-an-add-on.html>
- Configure an Installed Add-on Using Kubectl (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/configure-an-add-on.html>
- Configure an Add on at Installation Time Using Kubectl (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/configure-an-add-on-at-installation-time.html>
- Migrate a Legacy Package Add-on (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/migrate-a-legacy-package-add-on.html>
- General Requirements for Installing Packages on VKS clusters (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/general-requirements.html>
- Manage Package Repository (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/create-the-package-repository.html>
- Managing VKS Standard Packages (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/manage-vks-standard-packages.html>
- Broadcom 호환 매트릭스: <https://interopmatrix.broadcom.com/>
