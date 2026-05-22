# Pod Security Admission (PSA) — 요약 및 실습 가이드

본 문서는 Kubernetes의 Pod Security Admission(이하 PSA)에 대한 개념, 네임스페이스에 적용하는 방법, 권장 설정, 실습 예시 및 PodSecurityPolicy(PSP)에서의 마이그레이션 가이드를 정리합니다.

요약
- PSA는 네임스페이스 단위로 Pod 보안 수준을 강제(enforce), 감사(audit), 경고(warn)할 수 있는 내장 Admission Controller입니다.
- 보안 수준(level): `privileged`, `baseline`, `restricted` (권한 엄격도 최저→최고 순: privileged < baseline < restricted)
- 동작 모드(mode): `enforce`, `audit`, `warn` (각 모드별로 적용 수준이 다름)
- 적용 방법: 네임스페이스 주석(annotation)으로 설정 (pod-security.kubernetes.io/*)

기본 개념
- Levels
  - privileged: 최소 제약. 대부분의 보안 제약 해제. (기본 동작에 가깝게 모든 권한 허용)
  - baseline: 보안 취약점이 흔한 설정(특권 컨테이너, hostNetwork, hostPID 등)을 차단하지만, 대부분의 일반 애플리케이션은 동작 가능하도록 설계
  - restricted: 가장 엄격한 프로파일. 가능한 모든 보안 경계(읽기전용 루트, 비루트 실행 등)를 요구

- Modes
  - enforce: 해당 레벨을 실제로 거부(Reject)합니다. 위반 Pod는 생성/업데이트 불가.
  - audit: 위반을 거부하지 않고 이벤트/로그로 기록합니다.
  - warn: API 요청에 경고 헤더/응답을 붙여 사용자에게 알립니다.

네임스페이스에 적용하는 주석 예시

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-ns
  annotations:
    pod-security.kubernetes.io/enforce: "restricted"
    pod-security.kubernetes.io/enforce-version: "latest"
    pod-security.kubernetes.io/audit: "baseline"
    pod-security.kubernetes.io/warn: "privileged"
```

- `enforce-version`: PSA의 규칙 버전을 지정. 일반적으로 `latest` 또는 `v1.25` 등으로 고정 가능.
- 권장: 신규 네임스페이스는 `enforce: baseline`로 시작하여, 테스트 후 `restricted`로 승격.

간단한 테스트 (기본적인 검증 흐름)

1. 네임스페이스 생성 및 주석 추가
```bash
kubectl apply -f ns-secure.yaml
```
2. 권한 위반 Pod 생성 시도 (예: hostPath 마운트 또는 privileged: true)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  namespace: secure-ns
spec:
  containers:
  - name: busy
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
```
# 생성 시도
kubectl apply -f privileged-test.yaml
# enforce 모드일 경우 API에서 거절됩니다.
```

PSP에서 PSA로 마이그레이션
- PSP(Deprecated)는 Cluster-wide 정책 엔진으로 동작했으나 PSA는 네임스페이스 단위 주석 방식입니다. 완전한 기능 대체가 불가능할 수 있으므로 단계별 전환 권장.
- 권장 전략
  1. 클러스터에서 현재 PSP 규칙(사용되는 룰 목록) 파악
  2. 네임스페이스별로 PSA 수준(baseline/restricted) 매핑 계획 수립
  3. 먼저 `audit` 모드로 적용하여 위반 리포트 수집
  4. 적합성 확보 후 `warn` → `enforce`로 전환
- 대체 솔루션: 정책이 더 세밀하거나 네임스페이스 외 범위(예: 라벨 기반) 적용이 필요하면 Kyverno 또는 OPA Gatekeeper 사용 고려

권장 설정 예
- 개발: `audit=baseline`, `warn=baseline`, `enforce=baseline` (점진적 강화)
- 스테이징: `audit=restricted`, `warn=restricted`, `enforce=baseline`
- 프로덕션(민감): `enforce=restricted`, `audit=restricted`, `warn=baseline`

참고 명령 요약
- 현재 네임스페이스 PSA 주석 확인
```bash
kubectl get ns -o custom-columns=NAME:.metadata.name,ENFORCE:.metadata.annotations.\"pod-security.kubernetes.io/enforce\"\n
# 또는 개별 네임스페이스
kubectl get ns secure-ns -o yaml
```
- 위반 이벤트 보기 (audit logs/서버 이벤트)
  - `kubectl get events -A --field-selector reason=FailedCreate` 등으로 확인

추가 리소스
- 공식 문서: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- PSA 정책 사양 및 CSV 차이: Kubernetes 릴리스별 문서 참조

마지막 메모
- PSA는 간단하고 운영 부담이 적지만, 세밀한 정책(이미지 서명, 레이블 기반 제약 등)이 필요하면 Kyverno/OPA의 병행 사용이 실제 운영에서 흔합니다.
