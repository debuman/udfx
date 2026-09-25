# UDFX - Ultimate Domain Finder X 개발 명세서

## 프로젝트 정보

| 항목 | 내용 |
|------|------|
| 프로젝트명 | UDFX (Ultimate Domain Finder X) |
| 버전 | 1.0.0 |
| 개발일 | 2025-02-06 |
| 개발언어 | PowerShell |
| 대상환경 | Windows Server / Windows 10+ |

## 개발 배경

- 에어갭(Air-Gap) 환경에서 사용 가능한 도메인 탐색 도구 필요
- 기존 도구(usfx 등)는 인터넷 연결 또는 DNS 브루트포스 방식에 의존
- AD 통합 DNS의 경우 LDAP을 통해 직접 레코드 조회 가능

## 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                 UDFX (Get-ADDnsRecords.ps1)             │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ Zone 검색   │→ │ Record 수집 │→ │ 결과 출력       │  │
│  │ (LDAP)      │  │ (dnsRecord) │  │ (CSV/JSON/TXT)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Active Directory      │
              │  DC=DomainDnsZones     │
              │  (LDAP Query)          │
              └────────────────────────┘
```

## 핵심 함수

### Get-RootDomain

루트 도메인 추출 함수

```powershell
function Get-RootDomain {
    param([string]$domain)
    # .co.kr, .or.kr 등 3단계 TLD 처리
    # 일반 도메인: example.com → example.com
    # 한국 도메인: example.co.kr → example.co.kr
}
```

**지원 TLD:**
- 일반: .com, .net, .org, .io 등
- 한국: .co.kr, .or.kr, .go.kr, .ac.kr 등
- 영국: .co.uk, .org.uk 등
- 일본: .co.jp, .or.jp 등

### Get-DnsNameFromRecord

AD DNS 바이너리 레코드에서 도메인명 추출

```powershell
function Get-DnsNameFromRecord {
    param(
        [byte[]]$data,
        [int]$offset
    )
    # DNS wire format (길이-프리픽스) 파싱
    # 라벨별로 분리 후 점(.)으로 결합
}
```

**DNS 레코드 바이너리 구조:**
```
Offset  | Size | Field
--------|------|------------------
0-1     | 2    | Data Length
2-3     | 2    | Record Type
4-7     | 4    | Version/Serial
8-11    | 4    | TTL
12-15   | 4    | Reserved
16-19   | 4    | Timestamp
20-23   | 4    | Reserved
24+     | N    | Record Data
```

### Convert-DNSRecord

바이너리 DNS 레코드를 파싱하여 구조화된 데이터로 변환

```powershell
function Convert-DNSRecord {
    param([byte[]]$RecordData)
    # Record Type에 따라 적절한 파싱 수행
    # A: IPv4 (4 bytes)
    # AAAA: IPv6 (16 bytes)
    # NS/CNAME: DNS Name
    # MX: Priority(2) + DNS Name
    # SRV: Priority(2) + Weight(2) + Port(2) + DNS Name
}
```

## 레코드 타입 코드

| 타입 | 코드 | 데이터 형식 |
|------|------|-------------|
| A | 1 | 4 bytes (IPv4) |
| NS | 2 | DNS Name |
| CNAME | 5 | DNS Name |
| SOA | 6 | DNS Name + Serial 등 |
| PTR | 12 | DNS Name |
| MX | 15 | 2 bytes (Priority) + DNS Name |
| TXT | 16 | Length-prefixed string |
| AAAA | 28 | 16 bytes (IPv6) |
| SRV | 33 | 6 bytes (Pri/Wt/Port) + DNS Name |

## LDAP 쿼리 구조

### DNS Zone 검색

```
Base DN: DC=DomainDnsZones,DC=corp,DC=example,DC=com
Filter: (objectClass=dnsZone)
```

### DNS Record 검색

```
Base DN: DC=<ZoneName>,CN=MicrosoftDNS,DC=DomainDnsZones,...
Filter: (objectClass=dnsNode)
Attributes: name, dnsRecord
```

## 알려진 이슈

### 1. NS/SRV 레코드 이름 파싱

**현상**: NS, SRV 레코드의 대상 호스트명이 점(.) 없이 출력됨

```
예: hq-dc-01corpexamplecom (실제: hq-dc-01.corp.example.com)
```

**원인**: AD DNS 바이너리 포맷의 첫 바이트(전체 이름 길이)와 라벨 구분 처리 문제

**상태**: 미해결 (A 레코드 IP는 정상 동작)

### 2. SRV 레코드 포트/우선순위 값

**현상**: 포트, 우선순위, 가중치 값이 비정상적으로 표시됨

**원인**: 빅엔디안/리틀엔디안 바이트 순서 문제

**상태**: 부분 해결

## 향후 개선 사항

1. [ ] NS/SRV 레코드 이름 파싱 정확도 개선
2. [ ] Excel 다중 시트 출력 지원 (COM 또는 ImportExcel 모듈)
3. [ ] 역방향 DNS (PTR) 대역 스캔 기능 추가
4. [ ] 결과 비교 기능 (이전 스캔과 차이점 분석)
5. [ ] HTML 리포트 생성 기능

## 파일 구조

```
UDFX/
├── Get-ADDnsRecords.ps1    # 메인 스크립트
├── README.md               # 사용자 매뉴얼
├── DEVELOPMENT.md          # 개발 명세서
└── [출력 파일]
    ├── dns_records.csv
    ├── dns_records_root_domains.csv
    ├── dns_records.json
    └── dns_records.txt
```

## 참고 자료

- [MS-DNSP: Domain Name Service Protocol](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-dnsp/)
- [AD DNS Record Binary Format](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-dnsp/f97756c9-3783-428b-9451-b376f877f238)
- [USFX - Ultimate Subdomain Finder X](https://github.com/sqzer-x/usfx)
