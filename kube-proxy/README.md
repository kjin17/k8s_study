kube-proxy 모드 비교

이 폴더에는 kube-proxy의 주요 모드(iptables, ipvs, nftables)에 대한 설명과 각 모드의 장단점 및 차이점을 정리한 문서들이 있습니다.

파일 목록

- iptables.md — kube-proxy의 iptables 모드 설명, 장단점
- ipvs.md — kube-proxy의 IPVS 모드 설명, 장단점
- nftables.md — kube-proxy의 nftables 모드 설명, 장단점

간단 요약

- iptables: 호환성이 높고 설정·디버깅이 비교적 쉬움. 규모가 커지면 규칙 수와 CPU 오버헤드가 증가.
- ipvs: 성능과 확장성이 뛰어남(대규모 서비스에 적합). 커널 모듈 의존성 및 디버깅 난이도 존재.
- nftables: 현대적인 통합 프레임워크로 규칙 업데이트의 원자성·효율성이 높음. 비교적 최신 커널/배포판 의존성 있음.
