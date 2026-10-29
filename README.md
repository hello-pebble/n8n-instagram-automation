# OCI 서버에 n8n 설치 (Docker Compose + Caddy)

완성되면 이렇게 된다.

| 주소 | 하는 일 |
|---|---|
| `https://내도메인.duckdns.org` | n8n 화면 |
| `https://내도메인.duckdns.org/media/2026-10-28_001/00.jpg` | 인스타가 가져갈 컷 이미지 (고정 주소) |

> **서버에 이미 caddy가 80/443을 쓰고 있다면** (이 저장소의 실제 배포 방식)
> - compose에는 caddy가 없고, n8n(`n8n-app`)과 이미지 서버(`n8n-media`)만 기존 caddy의 Docker 네트워크(`.env`의 `PROXY_NETWORK`)에 붙는다.
> - 2·3번(보안 목록, iptables)은 이미 열려 있으면 건너뛴다.
> - `Caddyfile`은 compose가 읽는 파일이 아니라, 서버의 기존 Caddyfile에 **추가할 블록**이다 (아래 5-1).

---

## 0. 준비물

| 항목 | 확인 |
|---|---|
| OCI 인스턴스 | Ubuntu 22.04/24.04 기준 (Oracle Linux면 4번 방화벽 명령만 다름) |
| SSH 접속 | `ssh -i 키파일 ubuntu@공인IP` 가 되는지 |
| 공인 IP | OCI 콘솔 → 인스턴스 상세 → Public IP |

---

## 1. DuckDNS 무료 주소 만들기

1. https://www.duckdns.org 로그인
2. sub domain 입력 (예: 계정과 상관없는 이름) → **add domain**
3. current ip 칸에 **OCI 공인 IP** 입력 → **update ip**
4. 확인: PC PowerShell에서 `nslookup 내도메인.duckdns.org` → 공인 IP가 나오면 OK

---

## 2. OCI 콘솔에서 80·443 열기 (보안 목록)

OCI 콘솔 → 네트워킹 → 가상 클라우드 네트워크 → 해당 VCN → 서브넷 → **보안 목록(Security List)** → **수신 규칙 추가**

| 소스 CIDR | IP 프로토콜 | 대상 포트 |
|---|---|---|
| `0.0.0.0/0` | TCP | `80` |
| `0.0.0.0/0` | TCP | `443` |

> 5678 포트는 열지 않는다. n8n은 Caddy를 통해서만 접속한다.

---

## 3. 서버 안 방화벽 열기 (이걸 자주 빼먹는다)

**Ubuntu (OCI 기본 이미지는 iptables가 막고 있음)**

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

**Oracle Linux인 경우**

```bash
sudo firewall-cmd --permanent --add-service=http --add-service=https
sudo firewall-cmd --reload
```

---

## 4. Docker 설치

```bash
# 이미 있으면 건너뛰기
docker --version && docker compose version

# 없으면
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit   # 다시 SSH 접속해야 docker 그룹이 적용됨
```

다시 접속 후 `docker ps` 가 sudo 없이 되면 OK.

> 서버에 이미 80/443을 쓰는 다른 프로그램(nginx 등)이 있으면 충돌한다.
> `sudo ss -tlnp | grep -E ':80|:443'` 로 먼저 확인.

---

## 5. 파일 올리고 실행

PC PowerShell에서 `compose.example.yaml`을 서버의 `compose.yaml`로 복사 (`.env`는 서버에서 만든다. 저장소에는 예시 파일만 있고 실제 `compose.yaml`은 올리지 않는다):

```powershell
scp -i 키파일 .\compose.yaml ubuntu@공인IP:~/n8n-server/
```

서버에서:

```bash
cd ~/n8n-server
cp .env.example .env
nano .env            # N8N_DOMAIN=내도메인.duckdns.org 로 수정 후 저장

mkdir -p local-files/media
sudo chown -R 1000:1000 local-files   # n8n(uid 1000)이 쓸 수 있게

docker compose up -d
docker compose ps                     # caddy, n8n 둘 다 running
docker compose logs -f caddy          # "certificate obtained successfully" 나오면 HTTPS 완료 (Ctrl+C로 빠져나오기)
```

---

### 5-1. 기존 caddy에 연결 (서버에 caddy가 이미 있을 때)

위 5번에서 `caddy` 서비스는 없으니 `docker compose logs -f caddy`는 건너뛴다. `n8n-app`, `n8n-media`가 running이면 된다.

서버의 기존 Caddyfile 맨 아래에 이 저장소의 `Caddyfile` 블록을 **이어 붙인다** (도메인만 실제 주소로).

```bash
cp /home/ubuntu/caddy/Caddyfile /home/ubuntu/caddy/Caddyfile.bak   # 백업
sudo docker exec caddy caddy validate --config /etc/caddy/Caddyfile   # 문법 검사
sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile     # 재시작 없이 반영
```

주의
- 기존 Caddyfile이 `{$DOMAIN}` 줄 아래에 중괄호 없이 설정이 이어지는 단일 사이트 형식이면, 사이트를 추가하기 전에 기존 내용을 `{ }`로 감싸야 한다 (아니면 `unrecognized directive` 오류).
- 마운트된 파일이라 `sed -i`나 `mv`로 바꾸지 말고 `tee`로 같은 파일에 덮어쓰거나 이어 쓴다. 안 그러면 컨테이너가 옛 내용을 계속 읽는다.

---

## 6. 확인

| 확인 | 방법 | 정상 |
|---|---|---|
| n8n 화면 | 브라우저에서 `https://내도메인.duckdns.org` | n8n 계정 만들기 화면 (자물쇠 표시) |
| 이미지 공개 | 서버에 테스트 이미지 하나 넣고 시크릿 창에서 열기 | 이미지가 바로 보임 |
| 폴더 목록 숨김 | `https://내도메인.duckdns.org/media/` 열기 | 404 (목록이 안 보여야 정상) |

테스트 이미지:

```bash
mkdir -p ~/n8n-server/local-files/media/test
# PC에서: scp -i 키파일 아무거나.jpg ubuntu@공인IP:~/n8n-server/local-files/media/test/00.jpg
```

→ `https://내도메인.duckdns.org/media/test/00.jpg`

> n8n 계정은 **처음 접속한 사람이 관리자**가 된다. 화면이 열리면 바로 계정부터 만들 것.

---

## 7. 자주 쓰는 명령

| 하고 싶은 것 | 명령 (`~/n8n-server` 에서) |
|---|---|
| 상태 | `docker compose ps` |
| 로그 | `docker compose logs -f n8n` |
| 재시작 | `docker compose restart` |
| n8n 업데이트 | `docker compose pull && docker compose up -d` |
| Caddy 설정 검사 | `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile` |

## 8. 막히기 쉬운 곳

| 증상 | 원인 | 해결 |
|---|---|---|
| 브라우저에서 접속 시간 초과 | 2번(보안 목록) 또는 3번(iptables) 중 하나 빠짐 | 둘 다 열렸는지 확인 |
| caddy 로그에 인증서 발급 실패 | DuckDNS IP가 틀렸거나 80 포트가 막힘 | `nslookup`, 2·3번 재확인 |
| `port is already allocated` | 80/443을 다른 프로그램이 사용 중 | `sudo ss -tlnp` 로 찾아서 정리 |
| n8n이 파일을 못 씀 | local-files 권한 | `sudo chown -R 1000:1000 local-files` |

---

## 9. 중복 게시 방지 (n8n Data Table)

같은 에피소드가 두 번 올라가는 것을 막는다. 올린 에피소드를 n8n Data Table `posted`에 기록하고, 시작할 때 이미 있으면 이후 단계(등록·게시)가 실행되지 않는다.

**한 번만 준비**

1. n8n 프로젝트의 Overview → **Data tables** 탭에서 새 테이블을 만든다. (워크플로의 Data table 노드 목록에서 **Create new**로도 된다.)
2. 이름은 `posted`, 컬럼은 문자열(string) 두 개: `episode`, `kind`
3. 워크플로 JSON을 가져온 뒤, `이미 올렸나? 확인`과 `올린 기록 남기기` 노드에 Data table `posted`가 선택되어 있는지 확인한다.

**동작**

| 상황 | 결과 |
|---|---|
| 처음 올리는 에피소드 | 통과 → 게시 → 게시 성공 후 `posted`에 `episode`와 `kind`(릴스는 `reel`, 이미지는 `cuts`)를 기록 |
| 이미 올린 에피소드 | `이미 올렸나? 확인` 노드에서 항목 0개로 끝나고, 등록·게시는 실행되지 않는다 |
| 처리 중 오류로 멈춤 (`ERROR` 등) | 게시 전이라 기록이 남지 않으므로 그대로 다시 실행하면 된다 |
| 같은 에피소드를 일부러 다시 올림 | `posted` 표에서 그 행을 지우고 실행 |

- 이미지(`cuts`)와 릴스(`reel`)는 같은 에피소드 번호여도 각각 한 번씩 올릴 수 있다.
- 막는 것은 같은 `episode`로 다시 시작하는 경우다. `게시하기` 노드만 따로 실행(Execute step)하는 것은 막지 못하니, 실행은 처음부터 전체로 한다.
