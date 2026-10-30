#!/usr/bin/env bash
# 구글 드라이브 inbox → 서버 media 복사, 게시가 끝난 폴더는 드라이브 done으로 옮기고 서버에서 삭제한다.
# root cron으로 실행한다 (복사한 파일의 소유자를 n8n 컨테이너 사용자로 바꾸기 위해).
set -uo pipefail

REMOTE="${REMOTE:-gdrive:n8n-instagram}"   # rclone remote:경로. 그 아래에 inbox/ 와 done/ 이 있다
MEDIA="${MEDIA:-/home/ubuntu/n8n-server/local-files/media}"
OWNER="${OWNER:-1000:1000}"                # n8n 컨테이너 사용자
DELETE_AFTER_MIN="${DELETE_AFTER_MIN:-30}" # 마지막 표시 파일이 생기고 이 시간이 지나면 삭제
STATE="${STATE:-/var/tmp/sync-media}"      # 업로드가 끝났는지 확인하는 기록
RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{3}$'

mkdir -p "$STATE" "$MEDIA"
exec 9>"$STATE/lock"
flock -n 9 || exit 0
log() { echo "$(date '+%F %T') $*"; }

# 1) inbox → 서버. 파일 목록(이름+크기)이 직전 실행과 같을 때만 업로드가 끝났다고 보고 복사한다.
rclone lsf --dirs-only "$REMOTE/inbox" 2>/dev/null | sed 's#/$##' | while read -r ep; do
  [[ $ep =~ $RE ]] || continue
  [ -f "$MEDIA/$ep/title.txt" ] && continue                  # 이미 받음
  src="$REMOTE/inbox/$ep"
  list=$(rclone lsf -R --files-only --format "ps" "$src" 2>/dev/null | sort)
  if [ -z "$list" ] || ! grep -q '^title.txt;' <<<"$list"; then continue; fi
  sum=$(md5sum <<<"$list" | cut -d' ' -f1)
  if [ "$(cat "$STATE/$ep.sum" 2>/dev/null)" != "$sum" ]; then
    echo "$sum" > "$STATE/$ep.sum"; log "$ep 업로드 확인 중 (다음 실행까지 변화가 없으면 복사)"; continue
  fi
  log "$ep 복사"
  # title.txt(준비 완료 표시)는 맨 마지막에 복사한다
  if rclone copy "$src" "$MEDIA/$ep" --exclude title.txt && rclone copy "$src" "$MEDIA/$ep" --include title.txt; then
    chown -R "$OWNER" "$MEDIA/$ep"
  else
    log "$ep 복사 실패 (다음 실행에서 다시 시도)"
  fi
done

# 2) 게시가 끝난 폴더 정리. 폴더에 있는 종류(이미지=cuts, 영상=reel)마다 표시 파일이 모두 있어야 한다.
for dir in "$MEDIA"/*/; do
  ep=$(basename "$dir"); [[ $ep =~ $RE ]] || continue
  [ -f "$dir/title.txt" ] || continue
  need=0; ok=1
  if ls "$dir"/*.jpg >/dev/null 2>&1; then need=1; [ -f "$dir/posted_cuts.marker" ] || ok=0; fi
  if [ -f "$dir/reel.mp4" ]; then need=1; [ -f "$dir/posted_reel.marker" ] || ok=0; fi
  { [ $need -eq 1 ] && [ $ok -eq 1 ]; } || continue
  [ -z "$(find "$dir" -maxdepth 1 -name 'posted_*.marker' -mmin "-$DELETE_AFTER_MIN")" ] || continue
  log "$ep 정리: 드라이브 done으로 이동 후 서버 폴더 삭제"
  if rclone moveto "$REMOTE/inbox/$ep" "$REMOTE/done/$ep" 2>/dev/null || ! rclone lsf "$REMOTE/inbox/$ep" >/dev/null 2>&1; then
    rm -rf "${MEDIA:?}/$ep"; rm -f "$STATE/$ep.sum"
  else
    log "$ep 드라이브 이동 실패, 서버 폴더는 그대로 둠"
  fi
done
