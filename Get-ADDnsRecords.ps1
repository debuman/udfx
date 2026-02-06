<#
.SYNOPSIS
    UDFX - Ultimate Domain Finder X
    AD 통합 DNS 레코드를 LDAP으로 직접 조회하는 에어갭 환경용 도구
.DESCRIPTION
    도메인 사용자 권한으로 Active Directory에 저장된 DNS 레코드를 조회합니다.
    인터넷 연결 없이 에어갭 환경에서 사용 가능합니다.
.EXAMPLE
    .\Get-ADDnsRecords.ps1 -Domain corp.example.com
    .\Get-ADDnsRecords.ps1 -Domain corp.example.com -Output results
.NOTES
    Version: 1.0.0
    Author: UDFX Project
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [string]$Output = "dns_records",

    [switch]$ShowDebug
)

$banner = @"

    __  ______  _________  __
   / / / / __ \/ ____/ |/ /
  / / / / / / / /_   |   /
 / /_/ / /_/ / __/  /   |
 \____/_____/_/    /_/|_|

 ╔═══════════════════════════════════════════════════╗
 ║  Ultimate Domain Finder X                         ║
 ║  Air-Gap AD DNS Enumeration Tool v1.0             ║
 ╠═══════════════════════════════════════════════════╣
 ║  [*] LDAP-based AD DNS Record Extraction          ║
 ║  [*] No Internet Connection Required              ║
 ║  [*] Domain User Privileges Only                  ║
 ╚═══════════════════════════════════════════════════╝

"@

Write-Host $banner -ForegroundColor Cyan

# 루트 도메인 추출 함수
function Get-RootDomain {
    param([string]$domain)

    $parts = $domain.Split(".")
    if ($parts.Count -lt 2) { return $domain }

    # .co.kr, .or.kr, .go.kr, .ac.kr 등 3단계 TLD 처리
    if ($parts.Count -ge 3) {
        $sld = $parts[-2]
        $tld = $parts[-1]
        if ($tld -eq "kr" -and $sld -match "^(co|or|go|ac|ne|re|pe|hs|ms|es|sc|kg)$") {
            return "$($parts[-3]).$($parts[-2]).$($parts[-1])"
        }
        if ($tld -eq "uk" -and $sld -match "^(co|org|ac|gov)$") {
            return "$($parts[-3]).$($parts[-2]).$($parts[-1])"
        }
        if ($tld -eq "jp" -and $sld -match "^(co|or|ac|go|ne)$") {
            return "$($parts[-3]).$($parts[-2]).$($parts[-1])"
        }
    }

    # 일반 도메인: example.com, example.io
    return "$($parts[-2]).$($parts[-1])"
}

# DNS 이름 파싱 함수
function Get-DnsNameFromRecord {
    param(
        [byte[]]$data,
        [int]$offset
    )

    $nameParts = @()
    $pos = $offset

    try {
        while ($pos -lt $data.Length) {
            $len = $data[$pos]
            if ($len -eq 0) { break }
            if ($len -gt 63) { break }
            if (($pos + 1 + $len) -gt $data.Length) { break }

            $label = [System.Text.Encoding]::ASCII.GetString($data, $pos + 1, $len)
            $nameParts += $label
            $pos += $len + 1
        }
    } catch {
        return "unknown"
    }

    if ($nameParts.Count -eq 0) { return "" }
    return ($nameParts -join ".")
}

# DNS 레코드 변환 함수
function Convert-DNSRecord {
    param([byte[]]$RecordData)

    if ($RecordData.Length -lt 24) { return $null }

    $recordType = [BitConverter]::ToUInt16($RecordData, 2)

    $typeName = switch ($recordType) {
        1 { "A" }
        2 { "NS" }
        5 { "CNAME" }
        6 { "SOA" }
        12 { "PTR" }
        15 { "MX" }
        16 { "TXT" }
        28 { "AAAA" }
        33 { "SRV" }
        default { "TYPE$recordType" }
    }

    $result = @{
        Type = $typeName
        TypeId = $recordType
        Data = ""
    }

    try {
        switch ($recordType) {
            1 { # A Record
                if ($RecordData.Length -ge 28) {
                    $ip = "{0}.{1}.{2}.{3}" -f $RecordData[24], $RecordData[25], $RecordData[26], $RecordData[27]
                    $result.Data = $ip
                }
            }
            28 { # AAAA Record
                if ($RecordData.Length -ge 40) {
                    $ipv6Bytes = $RecordData[24..39]
                    $ip = [System.Net.IPAddress]::new($ipv6Bytes).ToString()
                    $result.Data = $ip
                }
            }
            2 { # NS Record
                $result.Data = Get-DnsNameFromRecord $RecordData 24
            }
            5 { # CNAME Record
                $result.Data = Get-DnsNameFromRecord $RecordData 24
            }
            12 { # PTR Record
                $result.Data = Get-DnsNameFromRecord $RecordData 24
            }
            15 { # MX Record
                if ($RecordData.Length -ge 28) {
                    $priority = [BitConverter]::ToUInt16($RecordData, 24)
                    $exchange = Get-DnsNameFromRecord $RecordData 26
                    $result.Data = "[$priority] $exchange"
                }
            }
            6 { # SOA Record
                $result.Data = Get-DnsNameFromRecord $RecordData 24
            }
            16 { # TXT Record
                if ($RecordData.Length -gt 24) {
                    $txtLen = $RecordData[24]
                    if ($txtLen -gt 0 -and $RecordData.Length -ge (25 + $txtLen)) {
                        $result.Data = [System.Text.Encoding]::ASCII.GetString($RecordData, 25, $txtLen)
                    }
                }
            }
            33 { # SRV Record
                if ($RecordData.Length -ge 32) {
                    $priority = [BitConverter]::ToUInt16($RecordData, 24)
                    $weight = [BitConverter]::ToUInt16($RecordData, 26)
                    $port = [BitConverter]::ToUInt16($RecordData, 28)
                    $target = Get-DnsNameFromRecord $RecordData 30
                    $result.Data = "${target}:$port (pri:$priority wt:$weight)"
                }
            }
            default {
                $result.Data = "Binary (type:$recordType)"
            }
        }
    } catch {
        $result.Data = "Parse error"
    }

    return $result
}

# 메인 실행
Write-Host "[*] Target Domain: $Domain" -ForegroundColor White
Write-Host ""

# 도메인 DN 생성
$domainParts = $Domain.Split(".")
$domainDN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","

Write-Host "[*] Searching for DNS Zones in Active Directory..." -ForegroundColor Cyan

# DNS 영역 검색
$zones = @()
$searchBase = "LDAP://DC=DomainDnsZones,$domainDN"

try {
    $searcher = New-Object DirectoryServices.DirectorySearcher
    $searcher.SearchRoot = [ADSI]$searchBase
    $searcher.Filter = "(objectClass=dnsZone)"
    $searcher.PageSize = 1000

    $results = $searcher.FindAll()
    foreach ($result in $results) {
        $zoneName = $result.Properties["name"][0]
        if ($zoneName -and $zoneName -ne "RootDNSServers") {
            $zones += @{
                Name = $zoneName
                Path = $result.Path
            }
        }
    }
} catch {
    Write-Host "[!] Error accessing DNS zones: $_" -ForegroundColor Red
    exit 1
}

if ($zones.Count -eq 0) {
    Write-Host "[!] No DNS zones found." -ForegroundColor Red
    exit 1
}

Write-Host "[+] Found $($zones.Count) DNS zone(s)" -ForegroundColor Green
Write-Host ""

# 모든 레코드 수집
$allRecords = @()

foreach ($zone in $zones) {
    Write-Host "[*] Dumping: $($zone.Name)" -ForegroundColor Cyan

    try {
        $zoneSearcher = New-Object DirectoryServices.DirectorySearcher
        $zoneSearcher.SearchRoot = [ADSI]$zone.Path
        $zoneSearcher.Filter = "(objectClass=dnsNode)"
        $zoneSearcher.PageSize = 1000
        $zoneSearcher.PropertiesToLoad.AddRange(@("name", "dnsRecord"))

        $nodeResults = $zoneSearcher.FindAll()
        $zoneRecordCount = 0

        foreach ($node in $nodeResults) {
            $nodeName = $node.Properties["name"][0]
            $dnsRecords = $node.Properties["dnsRecord"]

            if ($nodeName -eq "@") {
                $fqdn = $zone.Name
            } else {
                $fqdn = "$nodeName.$($zone.Name)"
            }

            foreach ($recordData in $dnsRecords) {
                $parsed = Convert-DNSRecord -RecordData $recordData
                if ($parsed -and $parsed.Data -and $parsed.Type -ne "SOA") {
                    # Zone 유형 분류
                    $zoneType = "External"
                    if ($zone.Name -eq $Domain) {
                        $zoneType = "Primary"
                    } elseif ($zone.Name.EndsWith(".$Domain")) {
                        $zoneType = "Subdomain"
                    }

                    # 루트 도메인 추출
                    $rootDomain = Get-RootDomain $zone.Name

                    $record = [PSCustomObject]@{
                        Domain = $fqdn
                        RecordType = $parsed.Type
                        Value = $parsed.Data
                        Zone = $zone.Name
                        ZoneType = $zoneType
                        RootDomain = $rootDomain
                    }
                    $allRecords += $record
                    $zoneRecordCount++

                    if ($ShowDebug) {
                        Write-Host "    [$($parsed.Type)] $fqdn -> $($parsed.Data)" -ForegroundColor Gray
                    }
                }
            }
        }

        Write-Host "    Found $zoneRecordCount records" -ForegroundColor Gray

    } catch {
        Write-Host "    [!] Error: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "[*] Saving results..." -ForegroundColor Cyan

# JSON 출력
$jsonOutput = @{
    Target = $Domain
    ScanTime = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    TotalRecords = $allRecords.Count
    ZoneCount = $zones.Count
    Zones = $zones | ForEach-Object { $_.Name }
    Records = $allRecords
} | ConvertTo-Json -Depth 10
$jsonOutput | Out-File -FilePath "$Output.json" -Encoding UTF8

# CSV 출력
$allRecords | Export-Csv -Path "$Output.csv" -NoTypeInformation -Encoding UTF8

# Root Domain CSV 출력 (중복 제거)
$uniqueRootDomains = $allRecords | Select-Object -ExpandProperty RootDomain -Unique | Sort-Object | ForEach-Object {
    [PSCustomObject]@{
        RootDomain = $_
    }
}
$uniqueRootDomains | Export-Csv -Path "${Output}_root_domains.csv" -NoTypeInformation -Encoding UTF8

# TXT 출력
$txtContent = @"
# AD DNS Record Dump
# Target: $Domain
# Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Total Records: $($allRecords.Count)
# Zones: $($zones.Count)
#
# Format: RootDomain | ZoneType | Type | Domain | Value | Zone
# =============================================================

"@
foreach ($record in $allRecords) {
    $txtContent += "$($record.RootDomain) | $($record.ZoneType) | $($record.RecordType) | $($record.Domain) | $($record.Value) | $($record.Zone)`n"
}
$txtContent | Out-File -FilePath "$Output.txt" -Encoding UTF8

Write-Host ""
Write-Host "========== SCAN COMPLETE ==========" -ForegroundColor Green
Write-Host "Total Zones: $($zones.Count)" -ForegroundColor White
Write-Host "Total Records: $($allRecords.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Results saved to:" -ForegroundColor White
Write-Host "    - $Output.json" -ForegroundColor Cyan
Write-Host "    - $Output.csv" -ForegroundColor Cyan
Write-Host "    - ${Output}_root_domains.csv (unique root domains)" -ForegroundColor Cyan
Write-Host "    - $Output.txt" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Green

# 루트 도메인 목록
Write-Host ""
Write-Host "Root Domains Found:" -ForegroundColor White
$allRecords | Select-Object -ExpandProperty RootDomain -Unique | Sort-Object | ForEach-Object {
    Write-Host "    $_" -ForegroundColor Gray
}

# Zone 유형별 통계
Write-Host ""
Write-Host "Records by Zone Type:" -ForegroundColor White
$allRecords | Group-Object ZoneType | Sort-Object Count -Descending | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Count)" -ForegroundColor Gray
}

# 레코드 타입별 통계
Write-Host ""
Write-Host "Records by Record Type:" -ForegroundColor White
$allRecords | Group-Object RecordType | Sort-Object Count -Descending | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Count)" -ForegroundColor Gray
}

# 상위 도메인 출력
Write-Host ""
Write-Host "Sample Records (first 20):" -ForegroundColor White
$allRecords | Select-Object -First 20 | ForEach-Object {
    Write-Host "    [$($_.RecordType)] $($_.Domain) -> $($_.Value)" -ForegroundColor Gray
}
