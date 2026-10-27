# 01. Cert Manager

> 커리큘럼: [CURRICULUM.md](CURRICULUM.md) · 앞 절: [00. 패키지 저장소와 두 설치 경로](00-repository-and-install-paths.md) · 작성 2026-10-28
> 등급: **[근거]** 출처에 그대로 있는 것, **[추론]** 여러 출처를 엮어 직접 내린 결론.
> 기준 판: VKS Add-ons `3.8.0+20261021` (9.1 VKS Add-ons Release Notes, 2026-10-28 확인, 페이지 표기 Last Updated October 26, 2026). 판 호환은 이 문서에서 정리하지 않는다. [공식 호환 매트릭스](https://interopmatrix.broadcom.com/)와 릴리스 노트를 직접 볼 것.

cert-manager 는 VKS 애드온 가운데 가장 먼저 까는 것이다. 다른 애드온 여럿이 이것에 기대기 때문이다.

---

## 1. 무엇을 하는가

- [근거] cert-manager 는 쿠버네티스 워크로드용 TLS 인증서를 만들고, 만료되기 전에 갱신한다. (Cert Manager Package Reference, 9.0)
- [근거] Broadcom 문서는 cert-manager 를 「Contour, ExternalDNS, Prometheus, Harbor 를 포함한 대부분 애드온의 선행 조건」이라고 적는다. (Install Cert Manager, 9.0)
- [근거] 패키지가 까는 구성 요소는 세 개이고, 모두 `cert-manager` 네임스페이스에 Deployment 로 뜬다. (Cert Manager Package Reference, 9.0)

| 구성 요소 | 하는 일 |
|---|---|
| `cert-manager` | Certificate·Issuer·ClusterIssuer CRD 를 보고 발급·갱신·폐기를 일으키는 컨트롤러 |
| `cert-manager-cainjector` | Mutating/ValidatingWebhookConfiguration 에 CA 인증서를 자동으로 넣음 |
| `cert-manager-webhook` | API 서버가 부르는 웹훅. Certificate·Issuer 를 검증하고 기본값을 채움 |

[추론] cainjector 가 있다는 점이 「다른 애드온의 선행 조건」인 이유와 이어진다. 웹훅을 가진 패키지는 API 서버가 그 웹훅을 믿게 할 CA 묶음이 필요한데, 이를 cert-manager 가 발급하고 cainjector 가 웹훅 설정에 넣어 준다. 개별 패키지가 정말 그렇게 쓰는지는 각 절에서 해당 참조 문서로 확인한다.

### 판 (3.8.0+20261021 기준)

- [근거] 3.8.0+20261021 지원 표에 cert-manager 는 **Product** 등급으로 `1.21.2+vmware.1-vks.1`, `1.20.4+vmware.1-vks.1`, `1.19.6+vmware.4-vks.1` 세 판이 있다. 업그레이드 경로는 각각 「1.20.x 에서」「1.19.x 에서」「1.18.x 에서」 매끄럽게 올라간다고 적혀 있다. (9.1 VKS Add-ons Release Notes, 2026-10-28 확인)
- [근거] cert-manager 를 Add-on Management 로 깔 수 있게 된 것은 `1.18.2+vmware.2-vks.2` 판부터다(「Support cert-manager package on Addon management system」). 같은 판에서 네임스페이스 LimitRange 와 컨테이너 단위 CPU·메모리 설정이 들어왔다. (같은 출처)
- [근거] 업스트림 cert-manager 는 LTS 를 내지 않고, 2026-10-28 기준 지원 중인 판은 1.21(2026-07-08 출시)과 1.20(2026-03-10 출시) 둘이다. 1.22 는 2026년 11월 무렵 예정이다. (cert-manager Supported Releases)
- [추론] 그러니 VKS 저장소의 1.19.6 판은 업스트림에서는 이미 지원이 끝난 줄기다. Broadcom Product 등급 지원은 받지만, 업스트림 보안 수정이 1.19 로 백포트되지는 않는다. 새로 깐다면 1.21 이나 1.20 을 고르는 편이 낫다. 판마다 어떤 VKr 에서 돌 수 있는지는 릴리스 노트의 Supported VKr Versions 표를 직접 본다.

## 2. VKS 에서 어떻게 들어가는가

두 경로의 공통 바탕(저장소, `PackageInstall`, `AddonInstall`, 판 고르기)은 [00절](00-repository-and-install-paths.md)에, Carvel 기초는 [`../carvel-kapp.md`](../carvel-kapp.md)에 있다. 여기서는 cert-manager 에 특유한 것만 적는다.

| | 레거시 패키지 | Add-on Management (VCF CLI) | Add-on Management (kubectl) |
|---|---|---|---|
| 컨텍스트 | 워크로드 클러스터 | Supervisor, 클러스터 네임스페이스 | Supervisor, 클러스터 네임스페이스 |
| 패키지·애드온 이름 | `cert-manager.kubernetes.vmware.com` | `cert-manager` | `addonRef.name: cert-manager` |
| 판 지정 | `--version 1.18.2+vmware.2-vks.2` | `--addon-release-name cert-manager.kubernetes.vmware.com.1.19.2-vmware.1-vks.1` | `releaseFilter.ref.name` 에 같은 AddonRelease 이름 |
| 설정값 | `--values-file` | `--values-config-file` | `AddonConfig.spec.values` |

근거: [근거] Install Cert Manager Package, Install Cert Manager Addon using VCF CLI, Install Cert Manager Addon using Kubectl (모두 9.0, 2026-10-28 확인). 표로 묶은 것은 [추론].

- [근거] 패키지 이름이 판에 따라 다르다. 옛 판은 `cert-manager.tanzu.vmware.com`, **1.17.2 이후는 `cert-manager.kubernetes.vmware.com`** 으로 찾는다. (Install Cert Manager Package, 9.0)
- [근거] 패키지가 `cert-manager` 라는 네임스페이스를 스스로 만들어 쓰므로, `PackageInstall` 리소스는 **다른 이름의 네임스페이스**(문서 예시 `package-installed`)에 둔다. (같은 출처)
- [근거] Add-on 판 이름은 패키지 판의 `+` 를 `-` 로 바꾸고 앞에 패키지 이름을 붙인 꼴이다. 예: 패키지 판 `1.19.2+vmware.1-vks.1` → AddonRelease `cert-manager.kubernetes.vmware.com.1.19.2-vmware.1-vks.1`. (Install Cert Manager Addon using VCF CLI 의 `vcf addon available list` 출력)

## 3. 실습

> 이름(`wl-calico`, `test-ns`, `package-installed`)은 공식 문서의 예시 값이다. 판은 자기 환경의 `vcf addon available list cert-manager` 나 `vcf package available get` 출력에서 고른다. 아래 판 번호는 문서 예시 그대로이고 3.8.0+20261021 의 판이 아니다.

### 3.1 values 파일 만들기

```bash
# Add-on 경로(Supervisor 컨텍스트)
vcf addon available list cert-manager
vcf addon available get cert-manager -v 1.19.2+vmware.1-vks.1 -o cert-manager-data-values.yaml

# 레거시 경로(워크로드 클러스터 컨텍스트)
vcf package available get cert-manager.kubernetes.vmware.com/1.18.3+vmware.1-vks.1 \
  --default-values-file-output cert-manager-values.yaml
```

[근거] 참조 문서가 예로 드는 values 의 모양:

```yaml
certManager:
  pspNames:
  - vmware-system-privileged
deploymentMode:
  resources:
    limits:
      cpu: ""
      memory: ""
    requests:
      cpu: 10m
      memory: 64Mi
issuers: []
kubernetes_distribution: ""
kubernetes_version: ""
namespace: cert-manager
nsLimitRange:
  defaultLimits:
    cpu: ""
    memory: ""
  defaultRequests:
    cpu: 10m
    memory: 64Mi
priorityClassName: ""
```

- [근거] 설정표에 실린 키는 `namespace`, `priorityClassName`, `certManager.pspNames`, `controller.feature_gates`(기능 게이트 12개, 모두 기본 false. 예: `ExperimentalGatewayAPISupport`, `ServerSideApply`, `ValidateCAA`), `deploymentMode.resources.*`, `nsLimitRange.*` 이다. `deploymentMode`·`nsLimitRange` 는 1.18.2 이상에서 생겼다. (Cert Manager Package Reference, 9.0)
- [추론] 예시 YAML 의 `issuers: []`, `kubernetes_distribution`, `kubernetes_version` 은 설정표에 설명이 없다. 설명 없는 키는 건드리지 않는다. 지원 범위는 「문서화된 값까지」이기 때문이다([00절 1](00-repository-and-install-paths.md#1-무엇을-하는가)).

### 3.2 Add-on 방식, VCF CLI

```bash
vcf cluster list -A
vcf context use supervisor:test-ns

vcf addon install create cert-manager --cluster-name wl-calico -n test-ns \
  --addon-release-name cert-manager.kubernetes.vmware.com.1.19.2-vmware.1-vks.1 \
  --values-config-file cert-manager-data-values.yaml -y
# values 를 안 바꿀 거면 --values-config-file 을 뺀다

vcf addon install list --cluster-name wl-calico -n test-ns
# 기대: cert-manager ... PAUSED false  READY True  DELETE/UPGRADE Allowed
```

[근거] Install Cert Manager Addon using VCF CLI(9.0). 지울 때는 `vcf addon install delete cert-manager --cluster-name wl-calico -n test-ns -y` 이고, 이 명령이 AddonInstall·ClusterAddon·AddonConfig 를 차례로 지운다고 출력한다.

### 3.3 Add-on 방식, kubectl

```yaml
# addonconfig.yaml — 이름은 반드시 <클러스터 이름>-<애드온 이름>
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonConfig
metadata:
  annotations:
    clusteraddon.addons.kubernetes.vmware.com/owned-for-deletion: "true"
  name: wl-calico-cert-manager
  namespace: test-ns
spec:
  clusterName: wl-calico
  values: {}   # 3.1 의 values 내용을 붙이거나, 비워 두면 기본값
---
# addoninstall.yaml
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonInstall
metadata:
  name: wl-calico-cert-manager
  namespace: test-ns
spec:
  releaseFilter:
    ref:
      name: cert-manager.kubernetes.vmware.com.1.18.3-vmware.1-vks.1
      namespace: vmware-system-vks-public
  addonRef:
    name: cert-manager
  clusters:
  - selector:
      matchLabels:
        cluster.x-k8s.io/cluster-name: wl-calico
```

```bash
kubectl config use-context supervisor:test-ns
kubectl get addonreleases -n vmware-system-vks-public | grep cert-manager
kubectl apply -f addonconfig.yaml
kubectl apply -f addoninstall.yaml
kubectl get clusteraddon
# 기대: wl-calico-cert-manager ... cert-manager.kubernetes.vmware.com.1.18.3-vmware.1-vks.1  True
```

- [근거] 위 두 YAML 은 Install Cert Manager Addon using Kubectl(9.0) 예시다. 문서는 `spec.values` 아래에 주석만 두는데, 그대로 두면 값이 null 이 되므로 여기서는 `{}` 로 적었다 [추론].
- [근거] 00절의 Prometheus 예시와 달리 이 문서는 `spec.clusterName` 과 `releaseFilter.ref` 로 **판을 못박는다**. `releaseFilter` 를 빼면 어떤 판이 골라지는지는 이 문서에 나와 있지 않다. [추론] 클러스터 업그레이드 때 판이 함께 올라가는 흐름(00절 2.5)과 판 고정이 어떻게 맞물리는지는 문서에서 확인하지 못했다.

### 3.4 레거시 방식

```bash
vcf package available get cert-manager.kubernetes.vmware.com -n tkg-system
kubectl create ns package-installed
vcf package install cert-manager -p cert-manager.kubernetes.vmware.com \
  --namespace package-installed --version 1.18.2+vmware.2-vks.2 \
  --values-file cert-manager-values.yaml
vcf package installed get cert-manager -n package-installed

# 올리기
vcf package installed update cert-manager -p cert-manager.kubernetes.vmware.com \
  -v 1.18.3+vmware.1-vks.1 --namespace package-installed

# 문제가 생기면
kubectl get pkgi -A
kubectl describe pkgi cert-manager -n package-installed
```

[근거] Install Cert Manager Package(9.0).

### 3.5 깔린 뒤 확인 (워크로드 클러스터 컨텍스트)

```bash
kubectl -n cert-manager get deploy,svc
# 기대: deployment cert-manager, cert-manager-cainjector, cert-manager-webhook 모두 1/1
#       service cert-manager(9402), cert-manager-cainjector(9402), cert-manager-webhook(443, 9402)
```

[근거] 세 설치 문서의 기대 출력이 모두 이 모양이다.

그다음 실제로 인증서가 나오는지 본다. 아래는 업스트림 문서의 자체 서명 Issuer 로 CA 를 만들고, 그 CA 로 인증서를 받는 흐름이다.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: demo-ca
  secretName: demo-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: demo-ca
spec:
  ca:
    secretName: demo-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo-web
  namespace: default
spec:
  secretName: demo-web-tls
  dnsNames:
  - web.example.test
  issuerRef:
    name: demo-ca
    kind: ClusterIssuer
```

```bash
kubectl apply -f issuers.yaml
kubectl get certificate -A          # READY True 를 기다린다
kubectl get secret demo-web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -issuer -subject -enddate
```

- [근거] 자체 서명 Issuer 로 CA 를 만들고 CA Issuer 를 세우는 방식은 업스트림 SelfSigned 문서의 bootstrapping 예시를 따랐다. ClusterIssuer 의 CA Secret 은 cert-manager 의 「클러스터 리소스 네임스페이스」(기본 `cert-manager`)에 있어야 한다. (cert-manager SelfSigned, CA 문서)
- [추론] VKS 패키지가 이 「클러스터 리소스 네임스페이스」를 바꾸는 값을 노출하지 않으므로, values 의 `namespace` 를 바꿨다면 CA Secret 도 그 네임스페이스에 둬야 한다고 본다. 실제로 바꾸기 전에 `kubectl -n <ns> get deploy cert-manager -o yaml | grep cluster-resource-namespace` 로 확인한다.

## 4. 업스트림 Helm 설치와 다른 점

업스트림 차트로 직접 까는 방법은 루트 [`../k8s-addon.sh`](../k8s-addon.sh)의 「12. cert-manager」(`addon_cert_manager`)에 있다. 여기서는 차이만 적는다.

1. [근거] Helm 차트의 values 와 VKS 패키지의 values 는 키가 다르다. VKS 쪽은 `deploymentMode.resources`·`nsLimitRange`·`certManager.pspNames` 같은 자체 키를 쓰고, 지원 범위는 Broadcom 문서에 실린 키까지다. (Cert Manager Package Reference, 9.0; 9.1 Release Notes 의 지원 범위 절)
2. [근거] VKS 패키지는 cert-manager 네임스페이스에 LimitRange 를 함께 둔다(`nsLimitRange`, 기본 요청 CPU 10m·메모리 64Mi). (같은 출처) [추론] 그래서 이 네임스페이스에 직접 띄우는 다른 Pod 도 이 기본 요청을 받는다.
3. [근거] 판 이름에 `+vmware.N-vks.N` 꼬리가 붙고 이미지는 Broadcom 저장소에서 온다(00절 4). 업스트림이 1.19 지원을 끝냈어도 VKS 저장소에는 1.19.6+vmware.4 가 남아 있다(1절).
4. [추론] 같은 클러스터에 Helm 판과 VKS 판을 함께 깔면 CRD 와 웹훅이 겹친다. 하나만 깐다. 이미 Helm 으로 깔았다면 지우고 CRD 정리 여부를 업스트림 제거 문서로 확인한 뒤 VKS 판을 깐다.

## 5. 흔한 실수

1. **`PackageInstall` 을 `cert-manager` 네임스페이스에 두기.** [근거] 패키지가 그 이름의 네임스페이스를 스스로 만들기 때문에 문서는 다른 이름을 쓰라고 한다(2절).
2. **옛 패키지 이름으로 찾기.** [근거] 1.17.2 이후 판은 `cert-manager.tanzu.vmware.com` 이 아니라 `cert-manager.kubernetes.vmware.com` 이다. 옛 이름으로 찾으면 새 판이 안 보인다.
3. **AddonConfig 이름을 마음대로 짓기.** [근거] `<클러스터 이름>-<애드온 이름>`(예: `wl-calico-cert-manager`)이어야 한다. (Install Cert Manager Addon using Kubectl)
4. **`pspNames` 기본값을 표만 보고 믿기.** [근거] 같은 참조 문서 안에서 예시 YAML 은 `vmware-system-privileged`, 설정표의 기본값 칸은 `vmware-system-restricted` 로 다르다. [추론] PodSecurityPolicy 는 쿠버네티스 1.25 에서 없어졌으므로 지금의 VKr 에서는 이 값이 실제로 쓰이지 않을 가능성이 높다. 직접 생성한 기본 values(3.1)를 정본으로 삼는다.
5. **지원 끝난 업스트림 줄기를 새로 깔기.** [추론] 1.19 는 업스트림 지원이 끝났다. 새 클러스터는 1.21·1.20 중에서 고른다(1절).
6. **cert-manager 를 지우고 다른 애드온을 남겨 두기.** [근거] cert-manager 는 Contour·ExternalDNS·Prometheus·Harbor 의 선행 조건이다. [추론] 지우기 전에 이 애드온들이 깔려 있는지 `vcf addon install list` 나 `kubectl get pkgi -A` 로 먼저 본다.
7. **AddonInstall 이름이 문서마다 다르다고 헷갈리기.** [근거] kubectl 문서는 `wl-calico-cert-manager` 로 직접 짓고, VCF CLI 의 삭제 출력에는 `AddonInstall cert-manager-wl-calico` 가 나온다. [추론] CLI 가 짓는 이름과 손으로 지은 이름이 다를 수 있으니, 지울 때는 이름을 짐작하지 말고 `kubectl get addoninstall -n <ns>` 로 확인한다.

## 6. 확인 문제

1. cert-manager 패키지가 까는 세 Deployment 를 들고, 그중 다른 애드온의 웹훅과 가장 직접 이어지는 것은 무엇인지 말해 보라.
<details><summary>답</summary>

`cert-manager`(컨트롤러), `cert-manager-cainjector`, `cert-manager-webhook`. 다른 애드온의 웹훅과 직접 이어지는 것은 cainjector 다. Mutating/ValidatingWebhookConfiguration 에 CA 인증서를 넣어 API 서버가 그 웹훅을 믿게 한다. [근거] Cert Manager Package Reference. 「다른 애드온과 이어진다」는 연결은 [추론].
</details>

2. 레거시 방식으로 cert-manager 를 깔 때 `PackageInstall` 을 둘 네임스페이스로 `cert-manager` 를 쓰면 안 되는 이유는?
<details><summary>답</summary>

패키지가 `cert-manager` 네임스페이스를 스스로 만들어 구성 요소를 그곳에 띄우기 때문에, PackageInstall 은 다른 이름의 네임스페이스(예: `package-installed`)에 둔다. [근거] Install Cert Manager Package.
</details>

3. 3.8.0+20261021 저장소에 있는 cert-manager 판 셋 가운데, 2026-10-28 기준 업스트림 지원이 끝난 줄기는 무엇이고, 그 판의 지원은 누가 하는가?
<details><summary>답</summary>

1.19 줄기(`1.19.6+vmware.4-vks.1`). 업스트림은 1.21·1.20 만 지원한다. 이 판은 VKS 저장소에서 Product 등급이라 Broadcom 지원 대상이지만 업스트림 보안 수정 백포트는 없다. [근거] 9.1 VKS Add-ons Release Notes, cert-manager Supported Releases. 결론 부분은 [추론].
</details>

## 7. 출처 (모두 2026-10-28 확인)

- VKS Add-ons Release Notes (9.1, Last Updated October 26, 2026): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html>
- Install Cert Manager (9.0, Last Updated October 6, 2026): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-cert-manager.html>
- Install Cert Manager Package (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-cert-manager/install-cert-manager-package1.html>
- Install Cert Manager Addon using VCF CLI (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-cert-manager/install-cert-manager-addon.html>
- Install Cert Manager Addon using Kubectl (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-cert-manager/install-cert-manager-addon-using-kubectl.html>
- Cert Manager Package Reference (9.0): <https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/cert-manager-package-reference.html>
- cert-manager Supported Releases: <https://cert-manager.io/docs/releases/>
- cert-manager SelfSigned Issuer: <https://cert-manager.io/docs/configuration/selfsigned/>
- cert-manager CA Issuer: <https://cert-manager.io/docs/configuration/ca/>
- Broadcom 호환 매트릭스: <https://interopmatrix.broadcom.com/>
