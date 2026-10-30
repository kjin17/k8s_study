# 05. Prometheus

> 커리큘럼: [CURRICULUM.md](CURRICULUM.md) · 앞 절: [04. Cluster Autoscaler](04-cluster-autoscaler.md) · 작성 2026-10-31
> 등급: **[근거]** 출처에 그대로 있는 것, **[추론]** 여러 출처를 엮어 직접 내린 결론.
> 기준 판: VKS Add-ons `3.8.0+20261021` (9.1 VKS Add-ons Release Notes, 페이지 표기 Last Updated October 26, 2026, 2026-10-31 확인). 판 호환은 이 문서에서 정리하지 않는다. [공식 호환 매트릭스](https://interopmatrix.broadcom.com/)와 릴리스 노트를 직접 볼 것.

VKS 의 Prometheus 애드온은 Prometheus 서버 하나만이 아니라 **Alertmanager·kube-state-metrics·node-exporter·Pushgateway 를 한 패키지로** 깐다. 3.5.0+vmware.3-vks.1 부터는 **Prometheus Operator** 도 같은 패키지 안에서 켤 수 있다. Grafana 는 들어 있지 않다.

이 절의 중심 주제는 「패키지가 직접 띄우는 Prometheus(레거시 모드)」와 「Operator 가 CR 로 띄우는 Prometheus(Operator 모드)」를 어떻게 고르고, 옮길 때 무엇을 잃는가다. 모니터링 자체의 원리(골든 시그널·RED·USE, 경보 설계)는 루트 [`../k8s-logging-monitoring/`](../k8s-logging-monitoring/)의 [03](../k8s-logging-monitoring/03_monitoring_best_practices.md)·[04](../k8s-logging-monitoring/04_alerting_best_practices.md)를 본다.

---

## 1. 무엇을 하는가

### 패키지에 든 구성 요소

| 구성 요소 | 리소스 | 기본 복제 수 | 하는 일 |
|---|---|---|---|
| `prometheus-server` | Deployment | 1 | 스크레이프·규칙 평가·경보 전송 |
| `alertmanager` | Deployment | 1 | 경보 묶기·전달 |
| `prometheus-kube-state-metrics` | Deployment | 1 | 오브젝트 상태(Pod·Job·replica 수·requests/limits) 메트릭 |
| `prometheus-node-exporter` | DaemonSet | 노드 수 | 노드 OS·하드웨어 메트릭 |
| `prometheus-pushgateway` | Deployment | 1 | 스크레이프할 수 없는 배치 작업이 메트릭을 밀어 넣는 곳 |
| `prometheus-operator` | Deployment | 1 | 선택. CR 로 Prometheus·Alertmanager 를 관리 |
| `admission-webhook` | Deployment | 2 | 선택. Operator 의 하위 구성 요소, `operator.webhook.enabled` 로 켬 |

- [근거] 위 표는 Prometheus Package Reference 의 「Prometheus Components」 표다(node-exporter 칸은 문서에 `6` 으로 적혀 있는데, DaemonSet 이므로 예시 클러스터의 노드 수다 [추론]). 컨테이너 이미지는 Package Repository 에 지정된 VMware 공개 레지스트리에서 받는다. (Prometheus Package Reference, 9.0, Last Updated October 6, 2026)
- [근거] Operator 가 깔리면 CRD 10개가 생긴다: `alertmanagerconfigs`, `alertmanagers`, `podmonitors`, `probes`, `prometheusagents`, `prometheuses`, `prometheusrules`, `scrapeconfigs`, `servicemonitors`, `thanosrulers` (모두 `monitoring.coreos.com`). (Prometheus Operator Reference, 9.0)
- [근거] 9.0 설치·참조 문서 여덟 쪽 어디에도 Grafana 는 나오지 않는다. 3.8.0+20261021 지원 표에도 Grafana 애드온은 없다. (각 문서, `grep -i grafana` 0건, 2026-10-31)
- [추론] 대시보드가 필요하면 Grafana 는 따로 깔아야 한다. VKS 애드온 목록 안에서는 3.7.0+20260618 에 들어온 Headlamp 가 Prometheus 서비스를 자동 감지하도록 라벨이 붙었다(아래 판 표). 그래도 Headlamp 는 클러스터 대시보드이지 Grafana 대체품이 아니다(19절에서 다룬다).

### 판과 지원 등급 (3.8.0+20261021 기준)

- [근거] 3.8.0+20261021 에서 Prometheus 는 **Product** 등급이고 `3.13.3+vmware.1-vks.1` **한 판**이며, 지원 표의 VKr 다섯 칸 모두 「Yes」다. 업그레이드 경로는 「Smooth upgrade from 3.5.0+vmware.2-vks.1 and later」다. (9.1 VKS Add-ons Release Notes)
- [근거] 이 판에 함께 든 하위 구성 요소 판: Prometheus-Operator 0.94.0, Alertmanager 0.34.0, kube-state-metrics 2.20.0, **Thanos 0.42.4**, node-exporter 1.12.1, Pushgateway 1.11.3, configmap-reload 0.15.0. (같은 출처)
- [추론] 패키지 판 번호의 앞부분은 **Prometheus 서버 판**이다(3.13.3 → 업스트림 v3.13.3 노트에 링크). cert-manager·Contour 처럼 판 번호만 보고 「무엇이 바뀌었는지」를 알 수 있지만, 하위 구성 요소 판은 같은 칸의 「Sub-components version info」를 따로 봐야 한다.

Prometheus 서버 판이 묶음마다 어떻게 움직였는지 (모두 같은 9.1 릴리스 노트):

| 묶음 | Prometheus 애드온 판 | 눈에 띄는 변화 |
|---|---|---|
| 3.6.0+20260211 | 3.5.0 계열 | **Prometheus Operator(0.88.0) 를 선택 하위 구성 요소로 추가**, `deploycomponents.prometheus-operator` 깃발, 선택 admission webhook |
| 3.6.0+20260521 | 3.5.2 계열 | Alertmanager FQDN 지정 지원 |
| 3.7.0+20260618 | 3.5.3+vmware.1-vks.1 | NodePort·Web-Config(TLS)·readiness/liveness probe 지정·Alertmanager FQDN 지정, VKr 1.34 이상에서 PriorityClass 강제, Thanos 0.41.0 |
| 3.7.0+20260723 | 3.5.4+vmware.1-vks.1 | Operator 0.91.0 유지 |
| 3.7.0+20260827 | 3.13.2+vmware.1-vks.1 | **3.5 → 3.13 으로 올림**, Operator 0.93.0, Thanos 0.42.4, Thanos 충돌 수정, Headlamp 자동 감지용 서비스 라벨 |
| 3.7.0+20260924 | 3.13.2+vmware.2-vks.1 | Alertmanager 0.34.0, kube-state-metrics 2.20.0, Operator 0.93.1 |
| 3.8.0+20261021 | 3.13.3+vmware.1-vks.1 | Operator 0.94.0, 취약점 수정 |

- [추론] 9.0 설치 문서의 예시 판 `3.5.0+vmware.3-vks.1` 은 위 표의 맨 윗줄 무렵 판이다. 문서 예시를 그대로 치면 3.5 계열 Prometheus 가 깔린다. 판은 반드시 자기 환경의 `vcf addon available list prometheus` 출력에서 고른다.

## 2. VKS 에서 어떻게 들어가는가

두 경로의 공통 바탕은 [00절](00-repository-and-install-paths.md)에, Carvel 기초는 [`../carvel-kapp.md`](../carvel-kapp.md)에 있다.

| | 레거시 패키지 (VCF CLI) | Add-on Management (VCF CLI) | Add-on Management (kubectl) |
|---|---|---|---|
| 컨텍스트 | 워크로드 클러스터 | Supervisor, 클러스터 네임스페이스 | Supervisor, 클러스터 네임스페이스 |
| 패키지·애드온 이름 | `prometheus.kubernetes.vmware.com` | `prometheus` | `addonRef.name: prometheus` |
| 판 지정 | `-v 3.5.0+vmware.3-vks.1` | `--addon-release-name prometheus.kubernetes.vmware.com.3.5.0-vmware.3-vks.1` | `releaseFilter.ref.name` 에 같은 AddonRelease 이름 |
| 설정값 | `--values-file` | `--values-config-file` | `AddonConfig.spec.values` |
| PackageInstall·AddonInstall 위치 | 새 네임스페이스(예: `my-packages`) | 클러스터 네임스페이스 | 클러스터 네임스페이스 |
| 구성 요소가 뜨는 곳 | `tanzu-system-monitoring` | 같음 | 같음 |

근거: [근거] Install Prometheus Package, Install Prometheus Addon using VCF CLI, Install Prometheus Addon using Kubectl (모두 9.0, 2026-10-31 확인). 표로 묶은 것은 [추론].

- [근거] 패키지 이름이 판에 따라 다르다. **Prometheus 2.53.4 이후는 `prometheus.kubernetes.vmware.com`**, 그 전은 `prometheus.tanzu.vmware.com` 으로 찾는다. (Install Prometheus Package, 9.0)
- [근거] 레거시 경로에서 `--namespace` 를 안 주면 VCF CLI 는 `tanzu-system-monitoring` 을 쓰는데, 문서는 **패키지(PackageInstall)를 이 네임스페이스에 두지 말라**고 한다. 구성 요소는 `tanzu-system-monitoring` 에, PackageInstall 은 따로 만든 네임스페이스에 둔다. (같은 출처)
- [근거] 사전 조건은 General Requirements, 패키지 저장소, **cert-manager**, 그리고 대시보드를 인그레스로 열려면 **Contour** 다. (같은 출처의 Prerequisites)
- [근거] Add-on 경로의 kubectl 방식에서 `AddonConfig` 이름은 `<클러스터 이름>-<애드온 이름>`(예: `wl-antrea-prometheus`), `AddonInstall` 이름은 예시상 `<애드온 이름>-<클러스터 이름>`(예: `prometheus-wl-antrea`)이다. (Install Prometheus Addon using Kubectl, 9.0)
- [근거] 레거시 경로를 kubectl 로만 하는 Prometheus 전용 문서는 9.0 목차에 없다(VCF CLI 레거시·Add-on VCF CLI·Add-on kubectl 세 쪽). [추론] 레거시 kubectl 방식은 [00절](00-repository-and-install-paths.md)의 PackageInstall 틀에 패키지 이름만 바꿔 쓴다.

### 레거시 모드와 Operator 모드

같은 패키지 안에서 두 가지 방식으로 Prometheus 를 띄울 수 있다. 이 구분이 이 절에서 가장 중요하다.

| | 레거시 모드 (기본) | Operator 모드 |
|---|---|---|
| `deploycomponents.prometheus` | `true` | `false` |
| `deploycomponents.alertmanager` | `true` | `false` |
| `deploycomponents.prometheus-operator` | `false` | `true` |
| Prometheus 를 띄우는 주체 | Carvel 템플릿(Deployment) | `Prometheus` CR → Operator 가 StatefulSet |
| 스크레이프 대상 정의 | values 의 `prometheus.config.prometheus_yml` | `ServiceMonitor`·`PodMonitor`·`ScrapeConfig` CR |
| 경보 규칙 | values 의 `alerting_rules_yml` 등 | `PrometheusRule` CR |
| 대시보드 노출 | values 의 `ingress`(Contour HTTPProxy) | 공식 예시는 NodePort Service `30090` |

근거: [근거] Prometheus Operator Reference 의 「Key Concept: Legacy vs. Operator-Managed」 표와 Operator 모드 data values 예시, Access the Prometheus Dashboard (모두 9.0). 표로 묶은 것은 [추론].

- [근거] **Operator 는 CR 로 만든 Prometheus·Alertmanager 만 관리한다.** 레거시 모드로 떠 있던 인스턴스는 Operator 가 손대지 못한다. (Prometheus Operator Reference, 「Attention」)
- [근거] Operator 모드로 옮길 때는 레거시 `prometheus`·`alertmanager` 깃발을 `false` 로 둬서 자원 충돌을 피하라고 한다. 이렇게 하면 「모니터링 기능이 없어지는 것이 아니라 레거시 Carvel Pod 를 내려 Operator 인스턴스에 자리를 내주는 것」이라고 적는다. (같은 출처)
- [근거] 그런데 Package Reference 의 `deploycomponents` 칸에는 **「업그레이드 중에 구성 요소를 false 로 두면(특히 prometheus·alertmanager) 그 구성 요소와 데이터가 영구히 지워진다」** 는 경고가 있다. (Prometheus Package Reference, 9.0)
- [추론] 두 문장을 합치면, 레거시 → Operator 전환은 **레거시 Prometheus 의 TSDB(`prometheus-server` PVC)와 Alertmanager 상태를 버리는 일**이다. Operator 가 만드는 `Prometheus` CR 은 자기 `volumeClaimTemplate` 으로 새 PVC 를 만들므로 옛 시계열은 따라오지 않는다. 보관 기간 안의 메트릭이 필요하면 전환 전에 원격 저장소(remote_write)나 스냅숏으로 따로 옮긴다. Broadcom 문서에는 옮기는 절차가 없다.
- [근거] Operator 모드에서는 사용자가 RBAC(ClusterRole·ClusterRoleBinding·ServiceAccount `prometheus`)와 `Prometheus`·`Alertmanager` CR 을 직접 만든다. 문서 예시 값은 Prometheus 복제 2·보관 42d·PVC 40Gi, Alertmanager 복제 3·PVC 10Gi 다. (Install Prometheus and Alertmanager instances using the Operator, 9.0)
- [근거] admission webhook 은 Operator 를 켰을 때만 깔 수 있고 **cert-manager 패키지에 기댄다**. 기본은 꺼짐이다. (Prometheus Operator Reference 의 data values 주석)
- [근거] `userProvidedResources` 칸에 Certificate·ServiceMonitor·Secret 같은 추가 리소스를 넣으면 패키지와 함께 배포된다. 리소스는 **의존 순서(Issuer → Certificate → Secret)로** 적어야 reconcile 이 실패하지 않는다. (Prometheus Package Reference·Operator Reference, 9.0)
- [추론] `userProvidedResources` 를 쓰면 ServiceMonitor 같은 CR 이 패키지 reconcile 에 묶인다. 애드온을 지우면 그 CR 도 같이 지워지고, 손으로 고친 값은 다음 reconcile 에 되돌아간다. 팀별로 자주 바뀌는 ServiceMonitor 는 패키지 밖에서 따로 관리하는 편이 덜 엉킨다.

## 3. 실습

> 이름(`wl-antrea`, `test-ns`, `my-packages`)은 공식 문서의 예시 값이다. 판 `3.5.0+vmware.3-vks.1` 도 문서 예시 그대로이고 3.8.0+20261021 의 판(`3.13.3+vmware.1-vks.1`)이 아니다. 자기 환경의 `vcf addon available list prometheus` 출력에서 고른다.
> cert-manager([01절](01-cert-manager.md))가 먼저 깔려 있어야 하고, 인그레스로 열려면 Contour([02절](02-contour.md))도 필요하다.

### 3.1 values 파일 만들기

```bash
# Add-on 경로
vcf addon available list prometheus
vcf addon available get prometheus -v 3.5.0+vmware.3-vks.1 -o prometheus-data-values.yaml

# 레거시 경로
vcf package available get prometheus.kubernetes.vmware.com -n tkg-system
vcf package available get prometheus.kubernetes.vmware.com/3.5.0+vmware.3-vks.1 \
  --default-values-file-output prometheus-data-values.yaml
```

[근거] Install Prometheus Addon using VCF CLI, Install Prometheus Package (9.0).

레거시 모드에서 처음 손볼 값만 추린 예 (문서의 필수 항목 표 기준):

```yaml
namespace: tanzu-system-monitoring
deploycomponents:
  kube-state-metrics: true
  node-exporter: true
  pushgateway: true
  prometheus: true
  alertmanager: true
  prometheus-operator: false
prometheus:
  pvc:
    storageClassName: <vSphere 스토리지 정책 이름>
    storage: 20Gi
  deployment:
    containers:
      args:
        - --storage.tsdb.retention.time=42d
        - --config.file=/etc/config/prometheus.yml
        - --storage.tsdb.path=/data
        - --web.console.libraries=/etc/prometheus/console_libraries
        - --web.console.templates=/etc/prometheus/consoles
        - --web.enable-lifecycle
alertmanager:
  pvc:
    storageClassName: <vSphere 스토리지 정책 이름>
    storage: 2Gi
ingress:
  enabled: true
  virtual_host_fqdn: prometheus.example.internal
  prometheus_prefix: /
  alertmanager_prefix: /alertmanager/
  prometheusServicePort: 80
  alertmanagerServicePort: 80
  # tlsCertificate 를 비우면 cert-manager 가 발급한다
```

- [근거] 문서가 「대시보드에 접근하려면 설정하라」고 꼽은 값은 `namespace`, `deploycomponents`, `ingress.enabled`(기본 false), `ingress.virtual_host_fqdn`(기본 `prometheus.system.tanzu`), `ingress.tlsCertificate.*`, `alertmanager.pvc.storageClassName`, `prometheus.pvc.storageClassName` 이다. (Install Prometheus Package, 9.0)
- [근거] 보관 기간은 별도 칸이 아니라 `prometheus.deployment.containers.args` 의 `--storage.tsdb.retention.time=42d` 로 정한다. 이 배열을 고치면 기본 인자 전체를 덮어쓰므로 나머지 인자도 함께 적는다 [추론]. (Prometheus Package Reference 의 args 기본값)
- [근거] 스크레이프는 values 의 `prometheus_yml` 에 정의된 job 들로 돈다: prometheus 자신, pushgateway, kube-state-metrics, node-exporter, `kubernetes-pods`(Pod 어노테이션 기반), `kubernetes-nodes-cadvisor`, `kubernetes-apiservers`. (같은 출처의 예시)
- [근거] `kubernetes-pods` job 은 Pod 의 `prometheus.io/scrape`·`prometheus.io/path`·`prometheus.io/port`·`prometheus.io/scheme` 어노테이션을 본다. 이 어노테이션은 **Pod 메타데이터에** 있어야 하고 Service·DaemonSet 오브젝트에 달면 효과가 없다. (같은 출처의 「Prometheus Pod Annotations」)

### 3.2 Add-on 방식, VCF CLI

```bash
vcf context use supervisor:test-ns
vcf addon install create prometheus -n test-ns --cluster-name wl-antrea \
  --values-config-file prometheus-data-values.yaml \
  --addon-release-name prometheus.kubernetes.vmware.com.3.5.0-vmware.3-vks.1 -y

vcf addon install list -n test-ns --cluster-name wl-antrea
# 기대: prometheus  test-ns  false  True  Allowed

# 지우기 (AddonInstall·ClusterAddon·AddonConfig 순서로 지워진다)
vcf addon install delete prometheus --cluster-name wl-antrea -n test-ns -y
```

[근거] Install Prometheus Addon using VCF CLI (9.0).

### 3.3 Add-on 방식, kubectl

```yaml
# addonconfig.yaml — 이름은 <cluster-name>-<addon-name>
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonConfig
metadata:
  name: wl-antrea-prometheus
  namespace: test-ns
  annotations:
    clusteraddon.addons.kubernetes.vmware.com/owned-for-deletion: "true"
spec:
  clusterName: wl-antrea
  values:
    # 3.1 의 prometheus-data-values.yaml 내용을 여기에
---
# addoninstall.yaml
apiVersion: addons.kubernetes.vmware.com/v1alpha1
kind: AddonInstall
metadata:
  name: prometheus-wl-antrea
  namespace: test-ns
spec:
  releaseFilter:
    ref:
      name: prometheus.kubernetes.vmware.com.3.5.0-vmware.3-vks.1
      namespace: vmware-system-vks-public
  addonRef:
    name: prometheus
  clusters:
    - selector:
        matchLabels:
          cluster.x-k8s.io/cluster-name: wl-antrea
```

```bash
kubectl config use-context supervisor:test-ns
kubectl get addonreleases -n vmware-system-vks-public | grep prometheus
kubectl apply -f addonconfig.yaml
kubectl apply -f addoninstall.yaml
kubectl get clusteraddon -n test-ns
```

[근거] Install Prometheus Addon using Kubectl (9.0). 원문은 YAML 들여쓰기가 페이지에서 무너져 있어 위처럼 다시 맞췄다 [추론].

### 3.4 레거시 방식

```bash
kubectl create ns my-packages
vcf package install prometheus -p prometheus.kubernetes.vmware.com \
  -v 3.5.0+vmware.3-vks.1 --values-file prometheus-data-values.yaml -n my-packages
vcf package installed list -n my-packages
vcf package installed get prometheus -n my-packages
```

[근거] Install Prometheus Package (9.0).

### 3.5 깔린 뒤 확인 (워크로드 클러스터 컨텍스트)

```bash
kubectl get pod -n tanzu-system-monitoring
# 레거시 모드 기대: prometheus-server, alertmanager, prometheus-kube-state-metrics,
#                   prometheus-node-exporter(노드마다), prometheus-pushgateway

kubectl get pvc -n tanzu-system-monitoring
# 기대: alertmanager 2Gi Bound, prometheus-server 20Gi Bound

# 대시보드 (ingress.enabled: true 일 때)
kubectl get svc -n tanzu-system-ingress envoy   # Envoy LB 의 외부 IP
# DNS 에 virtual_host_fqdn → Envoy IP 를 등록한 뒤 브라우저로 연다

# 인그레스 없이 잠깐 보기 [추론]
kubectl -n tanzu-system-monitoring port-forward svc/prometheus-server 9090:80
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'
```

- [근거] PVC·Pod 기대 출력은 Install Prometheus Package 와 Add-on kubectl 문서의 예시 출력이다. Add-on kubectl 문서의 예시 Pod 목록에는 `prometheus-server`·`alertmanager` 가 없고 `prometheus-operator`·`prometheus-operator-admission-webhook` 이 있다. 즉 그 예시는 Operator 모드로 깔린 화면이다 [추론].
- [추론] `port-forward` 의 서비스 이름·포트는 values 기본값(`prometheus.service.port: 80`, `targetPort: 9090`)에서 짐작한 것이다. 먼저 `kubectl get svc -n tanzu-system-monitoring` 으로 실제 이름을 본다.

### 3.6 Operator 모드로 깔기

```yaml
# values 에서
deploycomponents:
  prometheus-operator: true
  kube-state-metrics: true
  node-exporter: true
  pushgateway: true
  prometheus: false        # CR 로 관리할 것이므로
  alertmanager: false
operator:
  webhook:
    enabled: true          # cert-manager 필요
    replicas: 2
```

그 뒤 RBAC 과 CR 을 만든다(공식 예시를 줄인 것):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: tanzu-system-monitoring
spec:
  serviceAccountName: prometheus      # ClusterRole·ClusterRoleBinding 은 공식 문서 예시대로 따로 만든다
  replicas: 2
  securityContext: {fsGroup: 65534, runAsGroup: 65534, runAsNonRoot: true, runAsUser: 65534}
  scrapeInterval: 1m
  evaluationInterval: 1m
  retention: 42d
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
  podMonitorSelector: {}
  ruleSelector: {}
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: <vSphere 스토리지 정책 이름>
        resources: {requests: {storage: 40Gi}}
  alerting:
    alertmanagers:
      - {namespace: tanzu-system-monitoring, name: alertmanager, port: web, scheme: http}
---
# 내 앱을 긁게 하기 [추론: Prometheus Operator API 의 ServiceMonitor 형식]
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-app
spec:
  selector:
    matchLabels: {app: my-app}
  endpoints:
    - port: metrics
      interval: 30s
```

```bash
kubectl get prometheus -A
# 기대: tanzu-system-monitoring  prometheus  2  2  True  True
kubectl get pod -n tanzu-system-monitoring | grep -E 'prometheus-prometheus|alertmanager-alertmanager'
```

- [근거] 위 Prometheus CR·기대 출력은 「Install Prometheus and Alertmanager instances using the Operator」 예시를 줄인 것이다. 빈 셀렉터 `{}` 는 「모든 ServiceMonitor·PodMonitor·Rule 을 고른다」는 뜻이다(업스트림 Prometheus Operator API 문서). (9.0, 2026-10-31 확인)
- [추론] 위 예시의 `serviceMonitorNamespaceSelector: {}` 는 **모든 네임스페이스**의 ServiceMonitor 를 줍는다. 그래서 RBAC 이 ClusterRole 이어야 하고, 아무 팀이나 ServiceMonitor 를 만들면 그대로 스크레이프 대상이 된다. 다중 테넌트 클러스터면 라벨 셀렉터로 좁힌다.

## 4. 업스트림 Helm 설치와 다른 점

| | VKS Prometheus 애드온 | 업스트림 `kube-prometheus-stack` (루트 [`../k8s-addon.sh`](../k8s-addon.sh)) |
|---|---|---|
| 기본 방식 | Carvel 템플릿이 Deployment 로 직접 띄움(레거시 모드) | 처음부터 Operator + CR |
| Operator | 선택, 기본 꺼짐 | 항상 켜짐 |
| Grafana | 없음 | 차트에 포함(스크립트는 끔) |
| 기본 경보 규칙·대시보드 | apiserver 가용성·burn rate 녹화 규칙 정도 | kubernetes-mixin 규칙·대시보드 묶음 |
| 스크레이프 정의 | values 의 `prometheus_yml` 문자열 | ServiceMonitor·PodMonitor |
| 대시보드 노출 | Contour HTTPProxy(ingress 칸) | 차트의 Ingress 값 |
| 지원 | Product 등급, 문서에 실린 파라미터만 | 커뮤니티 |

근거: [근거] Prometheus Package Reference 의 예시 values(녹화 규칙 `apiserver_request:burnrate*`·`availability30d`), 9.1 릴리스 노트 Support Tiers, 루트 `k8s-addon.sh` 의 `addon_prometheus`(kube-prometheus-stack, `grafana.enabled=false`). kubernetes-mixin 이 차트에 든다는 것은 [추론](차트 README 를 이번에 다시 확인하지 않음).

- [추론] 업스트림 차트에 익숙하면 VKS 레거시 모드가 낯설다. ServiceMonitor 를 만들어도 레거시 모드에서는 아무 일도 일어나지 않는다(Operator 가 없으니까). 반대로 values 의 `prometheus_yml` 을 고쳐도 Operator 모드 인스턴스에는 반영되지 않는다.
- 업스트림 설치 방법은 [`../k8s-addon.sh`](../k8s-addon.sh) 1번 메뉴를 그대로 쓴다. 여기로 옮겨 적지 않는다.

## 5. 흔한 실수

1. **패키지를 `tanzu-system-monitoring` 에 깐다.** [근거] 레거시 경로에서 `-n` 을 빠뜨리면 그렇게 되는데, 문서는 하지 말라고 한다. PackageInstall 은 따로 만든 네임스페이스에.
2. **Operator 모드로 바꾸면서 옛 메트릭이 남을 거라 믿는다.** [근거] 업그레이드 중 `deploycomponents.prometheus: false` 는 구성 요소와 데이터를 영구히 지운다. [추론] 전환 전 보관할 시계열을 따로 옮긴다.
3. **레거시 Prometheus 를 Operator 로 관리하려 한다.** [근거] Operator 는 CR 로 만든 인스턴스만 다룬다.
4. **둘 다 켠다.** [근거] Operator 를 켜면서 레거시 깃발을 `true` 로 두면 자원 충돌이 난다고 문서가 경고한다. [추론] 같은 노드·kube-state-metrics 를 두 Prometheus 가 긁어 메트릭과 경보도 두 벌이 된다.
5. **Service·DaemonSet 에 `prometheus.io/scrape` 를 단다.** [근거] 레거시 모드의 `kubernetes-pods` job 은 Pod 메타데이터의 어노테이션만 본다.
6. **`args` 에 보관 기간 한 줄만 적는다.** [추론] 배열 덮어쓰기라 `--config.file` 등이 빠져 서버가 기본 경로로 뜨거나 실패한다. 기본 여섯 줄을 다 적는다.
7. **Alertmanager 가 `Failed to get final advertise address: No private IP address found, and explicit IP not provided` 로 죽는다.** [추론] Alertmanager 의 클러스터(gossip) 기능이 광고할 사설 IP 를 Pod 주소에서 찾지 못할 때 나는 오류로 보인다. [근거] 문서의 처방: 레거시 모드는 ytt 오버레이로 `--cluster.listen-address=0.0.0.0:9093` 을 넣고 PackageInstall 에 `ext.packaging.carvel.dev/ytt-paths-from-secret-name.1` 어노테이션을 단다. Operator 모드는 `Alertmanager` CR 의 `args` 에 같은 값을 넣는다. (Troubleshoot Prometheus Installation, 9.0) 오버레이의 원리는 [`../carvel-ytt-for-kapp.md`](../carvel-ytt-for-kapp.md).
8. **공식 문서 예시를 그대로 친다.** [근거] 9.0 문서 안에 서로 어긋나는 곳이 다섯 군데 있다(모두 2026-10-31 확인).
   - Package Reference 의 예시 설명은 「Prometheus Operator 가 배포된다(`prometheus-operator: true`)」인데 바로 아래 YAML 은 `prometheus-operator: false` 다.
   - 같은 문서의 파라미터 표는 `prometheus.pvc.storage` 기본값을 `150Gi` 로, 예시 YAML 과 설치 문서의 출력은 `20Gi` 로 적는다. 깔기 전에 `vcf addon available get ... -o` 로 받은 실제 기본값을 본다.
   - 파라미터 표는 `prometheus.service.type` 지원 값을 `ClusterIP` 하나로 적지만, 9.1 릴리스 노트 3.7.0+20260618 은 「Support NodePort for prometheus deployment」를 적는다. 9.0 표가 늦은 것이다 [추론].
   - Troubleshoot 문서의 「레거시 Carvel」 절차는 PackageInstall 에 어노테이션을 단 뒤 다시 설치하는 명령으로 **Add-on 경로의** `vcf addon install create` 를 적는다. 레거시로 깔았다면 `vcf package install` 로 다시 친다(Install Prometheus Package 문서의 같은 절차는 그렇게 적는다).
   - 예시 판 `3.5.0+vmware.3-vks.1` 은 3.8.0+20261021 의 `3.13.3+vmware.1-vks.1` 보다 한참 옛 판이다.
9. **옛 판에서 바로 올린다.** [근거] 3.8.0+20261021 의 매끄러운 업그레이드 경로는 `3.5.0+vmware.2-vks.1 이후` 다. 그보다 옛 판(예: 패키지 이름이 `prometheus.tanzu.vmware.com` 이던 2.x)은 릴리스 노트의 경로 밖이다. [추론] 이 경우 새로 깔고 옮기는 계획으로 잡는다.

## 6. 확인 문제

1. 레거시 모드로 6개월 돌던 Prometheus 를 Operator 모드로 바꾸려 한다. values 에서 바꿀 깃발 셋과, 바꾸기 전에 꼭 할 일 하나를 근거와 함께 적어라.
2. 팀이 앱 Service 에 `prometheus.io/scrape: "true"` 를 달았는데 레거시 모드 Prometheus 의 targets 에 안 나온다. 이유와 고칠 곳 두 가지를 적어라.
3. 3.8.0+20261021 저장소에서 Prometheus 애드온의 Prometheus 서버·Operator·Thanos 판을 적고, 9.0 설치 문서 예시 판이 왜 그대로 쓰면 안 되는지 한 줄로 적어라.

<details>
<summary>풀이</summary>

1. `deploycomponents.prometheus-operator: true`, `deploycomponents.prometheus: false`, `deploycomponents.alertmanager: false`. 바꾸기 전에 남겨야 할 시계열을 원격 저장소·스냅숏으로 옮긴다. Package Reference 가 업그레이드 중 false 로 두면 구성 요소와 데이터를 영구히 지운다고 경고하고, Operator 는 레거시 인스턴스를 넘겨받지 못하기 때문이다. 그 뒤 RBAC 과 `Prometheus`·`Alertmanager` CR 을 만든다.
2. 레거시 모드의 `kubernetes-pods` job 은 Pod 메타데이터의 어노테이션만 본다. ① Deployment 의 `spec.template.metadata.annotations` 에 달거나 ② Service 를 긁게 하려면 values 의 `prometheus_yml` 에 Service 기반 job 을 추가한다(또는 Operator 모드로 가서 ServiceMonitor 를 쓴다).
3. Prometheus 3.13.3(`3.13.3+vmware.1-vks.1`), Operator 0.94.0, Thanos 0.42.4. 예시 판 `3.5.0+vmware.3-vks.1` 은 3.6.0 묶음 무렵 판이라 그대로 치면 3.5 계열 Prometheus 가 깔리고, 판은 자기 저장소의 `vcf addon available list prometheus` 로 골라야 한다.

</details>

---

## 7. 출처 (모두 2026-10-31 확인)

- Broadcom TechDocs, VCF 9.0 (모두 Last Updated October 6, 2026)
  - [Install Prometheus](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus.html) (하위 여섯 쪽의 목차)
  - [Install Prometheus Addon using VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/test(2).html) (주소가 `test(2).html` 이다)
  - [Install Prometheus Addon using Kubectl](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/install-prometheus-addon-using-kubectl.html)
  - [Install Prometheus and Alertmanager instances using the Operator](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/create-prometheus-and-alertmanager-using-prometheus-operator.html)
  - [Install Prometheus Package](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/install-prometheus-with-alertmanager.html)
  - [Access the Prometheus Dashboard](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/access-the-prometheus-dashboard-with-prometheus-operator-created.html)
  - [Troubleshoot Prometheus Installation](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-prometheus/troubleshoot-prometheus-installation.html)
  - [Prometheus Package Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/prometheus-package-reference.html)
  - [Prometheus Operator Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/prometheus-package-reference/prometheus-operator.html)
- [VKS Add-ons Release Notes (9.1)](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html) — 3.6.0+20260211 ~ 3.8.0+20261021 의 Prometheus 칸, 지원 표, Support Tiers (Last Updated October 26, 2026)
- [Prometheus Operator API reference](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api-reference/api.md) — Broadcom 문서가 CR 설정의 참조로 링크하는 곳
- [Prometheus 업스트림 v3.13.3 릴리스](https://github.com/prometheus/prometheus/releases/tag/v3.13.3) — 릴리스 노트가 링크하는 곳
