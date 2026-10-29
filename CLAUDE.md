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
- [ ] 이미지 캐러셀(upload-cuts) 서버에서 실행 확인
- [ ] 중복 게시 방지: Data Table `posted`(episode, kind)에 기록하고 시작 시 검사. 워크플로 반영 완료, 서버 n8n에서 표 생성과 동작 확인 전
- [ ] 토큰 자동 갱신(장기 토큰 60일), 매일 예약 실행
- [ ] 유튜브 쇼츠 업로드 (별도 워크플로)

## 구조
| 파일 | 역할 |
|---|---|
| compose.example.yaml | 예시 파일. 서버에서 `compose.yaml`로 복사해 쓴다. n8n(127.0.0.1:5678만) + 컷 이미지 서버, 기존 caddy 네트워크에 연결, 볼륨 n8n_data |
| compose.yaml | 서버에서 실제로 쓰는 파일 (커밋 금지, 내부 이름이 들어 있음) |
| Caddyfile | 서버의 기존 Caddyfile에 추가할 블록: `/media/*` → 컷 이미지 서버(browse 없음), 나머지 → n8n |
| upload-reel-v1.json | 릴스 업로드 워크플로 (설정 노드는 플레이스홀더) |
| upload-cuts-v8.json | 이미지(캐러셀) 업로드 워크플로. v7에서 캐릭터 이름을 `series` 설정값으로 뺀 공개용 사본. 원본 v7은 로컬에만 |
| .env | `N8N_DOMAIN`, `PROXY_NETWORK` (커밋 금지) |
| local-files/media/<episode>/ | 컷 이미지 (커밋 금지) |

## 워크플로 규칙 (이미 로컬에서 확정)
- 폴더명 `YYYY-MM-DD_NNN`, 파일명 `00.jpg`(표지) `01.jpg`~, JPEG만
- 설정 노드: ig_user_id, base_url, episode, cut_count(표지 제외), has_cover(yes/no), title, hashtags
- 1장이면 일반 이미지, 2장 이상이면 CAROUSEL. `is_ai_generated=true`는 최종 컨테이너에만
- 캡션 형식 `[<캐릭터이름> N화] 제목` — `#N` 금지(해시태그로 변환됨)
- 토큰은 n8n Credentials(Query Auth, name `access_token`)에만. 워크플로·파일에 절대 넣지 않음
- 호출은 HTTP Request 노드로 `graph.instagram.com` 직접 (내장 Facebook Graph 노드 사용 안 함)

## 반드시 지킬 것
- 커밋 금지: `.env`, `compose.yaml`(예시만 커밋), `local-files/`, 이미지, 토큰, 실제 도메인, 서버 IP, ig_user_id 숫자, 캐릭터·계정 이름, 캐릭터 이름이 든 워크플로 원본(upload-cuts-v7.json), 벨로그 초안
- 커밋 작성자 이메일은 GitHub noreply 주소만 (개인 이메일 금지)
- 커밋 전 `git diff --cached`로 위 값이 없는지 확인
- 공개 글(벨로그 "한번해봅시다" 시리즈)에도 위 값은 대체 단어로
- 서버에서 5678 포트는 외부에 열지 않는다
- 게시물에 위치 정보 넣지 않는다
- 사용자에게는 결과를 표로 정리해서 보고
