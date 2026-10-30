# n8n Instagram 자동 업로드 — 서버 배포

## 목표
로컬(PC Docker)에서 동작 확인한 n8n 인스타 업로드를 OCI 서버로 옮긴다.
- n8n + 컷 이미지 서버를 Docker Compose로 운영. HTTPS(80/443)는 서버에 이미 있는 caddy를 공유
- 컷 이미지를 `https://<도메인>/media/<episode>/00.jpg` 고정 주소로 공개 → 워크플로 `base_url` 고정
- 이후: 토큰 자동 갱신(장기 토큰 60일), 매일 예약 실행, 유튜브 쇼츠 업로드 추가

## 현재 상태
- [x] 로컬 n8n에서 표지+4컷 캐러셀 게시 성공 (Cloudflare 임시 터널 사용)
- [x] 서버용 compose.example.yaml / Caddyfile / .env.example / README.md 작성
- [x] DuckDNS 주소 (80/443은 기존 서버 설정으로 이미 열려 있음)
- [x] 서버에 docker compose up, HTTPS 확인 (기존 caddy에 블록 추가 후 reload)
- [x] 워크플로 JSON 서버로 가져오기, Credentials 재생성
- [x] PC 컷 폴더 → 서버 local-files/media 전송: `scp`로 에피소드 폴더 복사
- [x] 릴스 게시 성공 (upload-reel-v1.json)
- [x] 이미지 캐러셀 서버에서 실행 확인 (표지+5컷, 2026-10-30_001 게시 성공)
- [x] 중복 게시 방지: Data Table `posted`(episode, kind)에 기록하고 시작 시 검사. 같은 episode를 다시 실행하면 `이미 올렸나? 확인`에서 멈추는 것까지 서버에서 확인 (이미지 워크플로 기준)
- [x] 이미지 자동 탐색 버전(upload-cuts-v9) 서버 실행 확인
- [ ] 오래된 순 하나씩 버전(upload-cuts-v12, upload-reel-v5) 서버 실행 확인. `파일 목록 읽기`·`표시 파일 쓰기`(Read/Write Files) 노드를 쓰므로 서버 n8n에서 폴더가 보이고 표시 파일이 써지는지 먼저 확인. 모의 시험만 통과
- [ ] 구글 드라이브 동기화(scripts/sync-media.sh) 서버 설정과 실제 확인 (rclone 연결, cron 등록, 복사·삭제 동작). 모의 시험 12개는 통과
- [ ] 릴스 자동 탐색 버전(upload-reel-v2) 서버 실행 확인 (모의 시험은 통과, 실제 n8n에서는 아직)
- [ ] 토큰 자동 갱신(장기 토큰 60일), 매일 예약 실행 (시작 노드를 Schedule로 교체)
- [ ] 유튜브 쇼츠 업로드 (별도 워크플로)

## 구조
| 파일 | 역할 |
|---|---|
| compose.example.yaml | 예시 파일. 서버에서 `compose.yaml`로 복사해 쓴다. n8n(127.0.0.1:5678만) + 컷 이미지 서버, 기존 caddy 네트워크에 연결, 볼륨 n8n_data |
| compose.yaml | 서버에서 실제로 쓰는 파일 (커밋 금지, 내부 이름이 들어 있음) |
| Caddyfile | 서버의 기존 Caddyfile에 추가할 블록: `/media/*` → 컷 이미지 서버(browse 없음), 나머지 → n8n |
| upload-reel-v5.json | 릴스 업로드 워크플로. 서버의 `ready.txt`가 있는 폴더를 오래된 순으로 보고 `reel.mp4`가 있고 아직 안 올린 첫 에피소드 하나를 올린 뒤 `posted_reel.marker`를 씀. 제목(`title.txt`)은 선택 (설정 노드는 플레이스홀더) |
| upload-cuts-v12.json | 이미지(캐러셀) 업로드 워크플로. 안 올린 가장 오래된 폴더 하나를 고르고 표지 유무·컷 수를 자동 계산, 게시 후 `posted_cuts.marker`를 씀. 제목은 선택. v7에서 캐릭터 이름을 `series` 설정값으로 뺀 공개용. 원본 v7은 로컬에만 |
| scripts/sync-media.sh | 서버 root cron용. 구글 드라이브 `inbox/`를 서버 media로 복사(미디어가 있고 업로드가 끝난 폴더만)한 뒤 `ready.txt` 생성, 게시 표시 후 30분이 지난 폴더는 드라이브 `done/`으로 옮기고 서버에서 삭제 |
| .env | `N8N_DOMAIN`, `PROXY_NETWORK` (커밋 금지) |
| local-files/media/<episode>/ | 컷 이미지 (커밋 금지) |

## 워크플로 규칙 (이미 로컬에서 확정)
- 폴더명 `YYYY-MM-DD_NNN`, 파일명 `00.jpg`(표지) `01.jpg`~, JPEG만
- 설정 노드(고정값, 한 번만 입력): ig_user_id, base_url(`https://<도메인>/media`), series(캐릭터 이름), hashtags
- episode, cut_count, has_cover는 입력하지 않고 자동: `/files/media/*/ready.txt`로 폴더를 찾아 오래된 순으로 안 올린 하나 선택, `00.jpg`~`20.jpg` 조회로 표지 유무와 컷 수 계산. 제목은 폴더의 `title.txt`가 있으면 읽고 없으면 생략(캡션 `[<캐릭터이름> N화]`)
- `ready.txt`가 준비 완료 표시다. 드라이브 동기화 스크립트가 복사를 마친 뒤 만든다 (서버에 직접 올리면 마지막에 빈 파일로 만든다). `title.txt`는 선택(UTF-8, 첫 줄이 제목, `#숫자` 금지)
- 이미지 번호가 중간에 비면(`02.jpg` 없음, `03.jpg` 있음) 오류로 멈춘다. 이미 올린 episode는 Data Table `posted`가 막는다
- 게시 성공 후 n8n이 폴더에 `posted_cuts.marker`(이미지) / `posted_reel.marker`(영상)를 쓴다. 서버 cron이 폴더 안 종류마다 표시가 모두 있고 30분이 지나면 서버 폴더를 삭제하고 드라이브 폴더를 `inbox/` → `done/`으로 옮긴다
- 1장이면 일반 이미지, 2장 이상이면 CAROUSEL. `is_ai_generated=true`는 최종 컨테이너에만
- 캡션 형식 `[<캐릭터이름> N화] 제목` — `#N` 금지(해시태그로 변환됨)
- 토큰은 n8n Credentials(Query Auth, name `access_token`)에만. 워크플로·파일에 절대 넣지 않음
- 호출은 HTTP Request 노드로 `graph.instagram.com` 직접 (내장 Facebook Graph 노드 사용 안 함)

## 반드시 지킬 것
- 커밋 금지: `.env`, `compose.yaml`(예시만 커밋), `local-files/`, 이미지, 토큰, 실제 도메인, 서버 IP, ig_user_id 숫자, 캐릭터·계정 이름, 캐릭터 이름이 든 워크플로 원본(upload-cuts-v7.json), 벨로그 초안, rclone.conf(구글 드라이브 토큰)
- 커밋 작성자 이메일은 GitHub noreply 주소만 (개인 이메일 금지)
- 커밋 전 `git diff --cached`로 위 값이 없는지 확인
- 공개 글(벨로그 "한번해봅시다" 시리즈)에도 위 값은 대체 단어로
- 서버에서 5678 포트는 외부에 열지 않는다
- 게시물에 위치 정보 넣지 않는다
- 사용자에게는 결과를 표로 정리해서 보고
