# UDFX - Ultimate Domain Finder X

Active Directory 통합 DNS에서 도메인 및 DNS 레코드를 수집하는 에어갭 환경용 도구입니다.

## 개요

- **목적**: AD DNS에 등록된 모든 도메인/서브도메인 및 레코드 수집
- **환경**: Windows 도메인 환경 (에어갭 지원)
- **권한**: 일반 도메인 사용자 권한으로 실행 가능
- **방식**: LDAP을 통한 AD DNS 직접 조회

## 요구사항

- Windows PowerShell 5.1 이상
- Active Directory 도메인 가입된 시스템
- 도메인 사용자 계정

## 사용법

### 기본 실행

```powershell
.\Get-ADDnsRecords.ps1 -Domain <도메인명>
```

### 예시

```powershell
# 기본 실행
.\Get-ADDnsRecords.ps1 -Domain corp.example.com

# 출력 파일명 지정
.\Get-ADDnsRecords.ps1 -Domain corp.example.com -Output scan_results

# 디버그 모드 (상세 출력)
.\Get-ADDnsRecords.ps1 -Domain corp.example.com -ShowDebug
```

### 파라미터

| 파라미터 | 필수 | 설명 | 기본값 |
|----------|------|------|--------|
| `-Domain` | O | 대상 AD 도메인명 | - |
| `-Output` | X | 출력 파일 기본명 | dns_records |
| `-ShowDebug` | X | 상세 출력 활성화 | False |

## 출력 파일

| 파일 | 설명 |
|------|------|
| `dns_records.csv` | 전체 DNS 레코드 (CSV) |
| `dns_records_root_domains.csv` | 루트 도메인 목록 (중복 제거) |
| `dns_records.json` | 전체 DNS 레코드 (JSON) |
| `dns_records.txt` | 전체 DNS 레코드 (텍스트) |

## 출력 필드

| 필드 | 설명 | 예시 |
|------|------|------|
| Domain | FQDN | vcsa.example.com |
| RecordType | DNS 레코드 타입 | A, NS, CNAME, MX, SRV, TXT |
| Value | 레코드 값 | 10.1.10.100 |
| Zone | DNS 영역명 | vcsa.example.com |
| ZoneType | 영역 분류 | Primary, Subdomain, External |
| RootDomain | 루트 도메인 | example.com |

### ZoneType 분류

| 타입 | 설명 |
|------|------|
| Primary | 메인 AD 도메인 |
| Subdomain | 메인 도메인의 서브도메인 |
| External | 외부 도메인 |

## 지원 레코드 타입

- **A**: IPv4 주소
- **AAAA**: IPv6 주소
- **NS**: 네임서버
- **CNAME**: 별칭
- **MX**: 메일 서버
- **SRV**: 서비스 레코드
- **TXT**: 텍스트 레코드
- **PTR**: 역방향 DNS

## 활용 예시

### 내부 IP 호스트만 필터링

```powershell
Import-Csv .\dns_records.csv | Where-Object {
    $_.RecordType -eq "A" -and
    ($_.Value -match "^10\." -or $_.Value -match "^172\.(1[6-9]|2[0-9]|3[01])\." -or $_.Value -match "^192\.168\.")
} | Export-Csv .\internal_hosts.csv -NoTypeInformation
```

### 특정 도메인만 필터링

```powershell
Import-Csv .\dns_records.csv | Where-Object {
    $_.RootDomain -eq "example.com"
} | Export-Csv .\filtered_records.csv -NoTypeInformation
```

### 루트 도메인 목록 확인

```powershell
Import-Csv .\dns_records_root_domains.csv
```

## 제한사항

- AD 통합 DNS만 지원 (독립 DNS 서버 미지원)
- NS, SRV 레코드의 대상 호스트명에 점(.)이 누락될 수 있음
- Zone Transfer가 허용되지 않은 환경에서는 LDAP 방식으로 대체

## 라이선스

MIT License
