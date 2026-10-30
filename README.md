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

---

## 10. 오래된 순으로 하나씩 올리기 (이미지 v12 / 릴스 v5)

`episode`, 컷 수, 표지 유무를 직접 입력하지 않는다. 서버에 쌓인 폴더 중 **아직 안 올린 가장 오래된 하나**를 실행할 때마다 올린다. 날짜와 상관없으니 에피소드를 몰아서 만들어 둬도 된다. 제목은 선택이다.

**설정 노드에는 고정값 4개만 한 번 입력한다**

| 필드 | 값 |
|---|---|
| `ig_user_id` | 인스타 계정 숫자 ID |
| `base_url` | `https://<도메인>/media` |
| `series` | 캐릭터 이름 (캡션의 `[<series> N화]`) |
| `hashtags` | 해시태그 |

**에피소드 폴더의 파일**

```
local-files/media/2026-10-30_001/
├── 00.jpg  01.jpg  02.jpg ...   (이미지, JPEG. 표지가 없으면 01.jpg부터)
├── reel.mp4                     (릴스를 올릴 때)
├── title.txt                    (선택. UTF-8, 첫 줄이 제목. 없으면 캡션은 [<series> N화]만)
└── ready.txt                    (준비 완료 표시)
```

- `ready.txt`는 11번의 동기화 스크립트가 복사를 모두 마친 뒤 자동으로 만든다. 서버에 직접 올릴 때는 파일을 다 올린 **마지막에** 빈 파일로 만든다.
- 제목에 `#숫자`(예: `#3`)가 있으면 해시태그로 변환되니 오류로 멈춘다.

**동작 순서**

| 단계 | 하는 일 |
|---|---|
| 파일 목록 읽기 | n8n이 `/files/media/*/ready.txt`를 찾아 준비된 폴더를 모두 얻는다 (폴더 목록을 공개하지 않아도 된다) |
| 에피소드 정렬 | 폴더 이름(`YYYY-MM-DD_NNN`)을 오래된 순으로 정렬. 형식이 다른 폴더(`test` 등)는 무시 |
| 이미 올렸나? 확인 | `posted` 표에 없는 것만 남긴다 |
| 올릴 파일 확인 | 이미지는 `00.jpg` 또는 `01.jpg`, 릴스는 `reel.mp4`가 있는 폴더만 남긴다 (영상만 있는 폴더가 이미지 순서를 막지 않는다) |
| 첫 번째만 | 남은 것 중 가장 오래된 **하나**만 진행 |
| 이후 | 컷 수 계산(이미지), 제목 읽기(없으면 생략), 게시, `posted`에 기록, 폴더에 표시 파일(`posted_cuts.marker` 또는 `posted_reel.marker`) 쓰기 |

- 이미지가 중간에 비면(`02.jpg`만 없음) 오류로 멈춘다. 후보가 없으면 오류 없이 끝난다. 이미 올린 폴더는 `posted`가 막는다.
- n8n 컨테이너가 `/files/media`를 읽고 쓸 수 있어야 한다 (11번 스크립트가 복사한 파일은 n8n 사용자 소유라 문제없다).

**예약 실행으로 바꾸기**: 시작 노드 `수동 실행`을 Schedule 노드로 교체한다.

---

## 11. 구글 드라이브로 올리고, 게시 후 자동 정리 (rclone + cron)

PC에서 서버로 `scp` 하지 않고 구글 드라이브에 올리면 서버가 알아서 가져오고, 게시가 끝나면 지운다.

| 단계 | 하는 일 | 누가 |
|---|---|---|
| 1 | 드라이브 `n8n-instagram/inbox/<episode>/`에 이미지나 `reel.mp4`(와 선택으로 `title.txt`)를 올린다 | 사용자 |
| 2 | 10분마다 서버가 `inbox/`를 서버 `media`로 복사하고 마지막에 `ready.txt`를 만든다 | 서버 cron |
| 3 | n8n이 가장 오래된 안 올린 에피소드 하나를 게시한다 | n8n |
| 4 | 게시 성공 후 n8n이 폴더에 `posted_cuts.marker` / `posted_reel.marker`를 쓴다 | n8n |
| 5 | 표시 후 30분이 지나면 서버 폴더를 삭제하고, 드라이브 폴더를 `inbox/` → `done/`으로 옮긴다 | 서버 cron |

**복사 규칙**
- 이미지(`.jpg`)나 `reel.mp4`가 있고, 폴더 안 파일 목록(이름+크기)이 **직전 실행과 같을 때만** 복사한다. 구글 드라이브는 업로드 순서가 제멋대로라서, 한 번 더 지켜보고 변화가 없으면 끝난 것으로 본다. 미디어가 없는 폴더는 건드리지 않는다.
- 복사를 모두 마친 뒤에 `ready.txt`를 만든다. n8n은 `ready.txt`가 있는 폴더만 본다.
- 삭제는 폴더에 있는 종류마다(이미지=`cuts`, 영상=`reel`) 표시 파일이 **모두** 있을 때만 한다. 이미지만 게시되고 영상은 아직이면 지우지 않는다. `ready.txt`가 없는 폴더는 지우지 않는다.

**서버 설정 (한 번만)** — 서비스 계정 방식. 로그인 토큰이 만료되지 않고, 공유해 준 폴더 하나에만 접근한다.

1. 드라이브에 `n8n-instagram/inbox`, `n8n-instagram/done` 폴더를 만든다.
2. 구글 클라우드 콘솔에서 프로젝트를 만들고 `Google Drive API`를 사용 설정한다.
3. IAM 및 관리자 → 서비스 계정을 만들고(역할 없음), 키 → 새 키 → JSON을 내려받는다.
   ⚠ 이 키 파일은 비밀이다. 저장소 폴더 안에 두지 않고, 저장소나 채팅에 절대 올리지 않는다. 서버에 올린 뒤 PC의 파일은 지워도 된다(필요하면 다시 만들 수 있다).
4. 서비스 계정 이메일(`...@...iam.gserviceaccount.com`)에 드라이브 `n8n-instagram` 폴더를 **편집자**로 공유한다. 폴더를 열었을 때 주소의 `folders/` 뒤 문자열이 폴더 ID다.
5. 서버에 rclone을 설치한다 (rclone 공식 설치 스크립트).

```bash
curl -fsSL https://rclone.org/install.sh | sudo bash
```

6. 키 파일을 서버로 올리고 root만 읽게 설치한다.

```powershell
scp -i 키파일 .\내려받은키.json ubuntu@서버:~/sa.json
```

```bash
sudo install -m 600 -o root -g root ~/sa.json /root/rclone-sa.json && rm ~/sa.json
```

7. rclone을 설정한다.

```bash
sudo rclone config
```

| 질문 | 입력 |
|---|---|
| name / Storage | `gdrive` / `drive` |
| client_id, client_secret | 비워 두고 Enter |
| scope | `1` |
| service_account_file | `/root/rclone-sa.json` |
| Edit advanced config | `y` → `root_folder_id`에 4번의 폴더 ID 입력, 나머지(`auth_owner_only` `false`, `use_trash` `true` 등)는 Enter |
| Shared Drive | `n` |

8. 연결을 확인한다. `inbox`, `done`이 보이면 된다.

```bash
sudo rclone lsd gdrive:
sudo rclone lsf gdrive:/inbox
```

9. 스크립트를 서버로 올려 설치하고 두 번 실행해 본다. 첫 실행은 `업로드 확인 중`, 두 번째에서 `복사`가 나와야 한다.

```bash
sudo install -m 755 ~/sync-media.sh /usr/local/bin/sync-media.sh
sudo /usr/local/bin/sync-media.sh
```

10. 10분마다 돌도록 root cron에 등록한다 (`sudo crontab -e`에 아래 한 줄).

```
*/10 * * * * /usr/local/bin/sync-media.sh >> /var/log/sync-media.log 2>&1
```

**설정값 (환경변수, 기본값이면 따로 안 해도 된다)**

| 이름 | 기본값 | 뜻 |
|---|---|---|
| `REMOTE` | `gdrive:` | rclone remote. 서비스 계정 설정에서 폴더 ID를 루트로 지정했으므로 `inbox/`, `done/`이 바로 아래에 있다 |
| `MEDIA` | `/home/ubuntu/n8n-server/local-files/media` | 서버의 media 폴더 |
| `OWNER` | `1000:1000` | 복사한 파일의 소유자 (n8n 컨테이너 사용자) |
| `DELETE_AFTER_MIN` | `30` | 마지막 표시 파일이 생기고 몇 분 뒤에 삭제할지 |

값을 바꾸려면 cron 줄 앞에 `DELETE_AFTER_MIN=1440`처럼 붙인다.

**알아둘 점**
- 복사된 파일은 n8n 사용자(uid 1000) 소유라서, 서버에서 직접 올릴 때(`scp`)는 `sudo`가 필요하다. 드라이브로 올리면 신경 쓸 일이 없다.
- 로그는 `/var/log/sync-media.log`에서 본다.
- 삭제된 폴더의 원본은 드라이브 `done/`에 남는다. 필요 없으면 그곳에서 정리한다.
