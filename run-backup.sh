#!/bin/bash
cd /home/abranscum/ansible || exit 1
set -a; . ./notify.env; set +a
URL=$(sed -E "s/\?.*$//" kuma-push-url 2>/dev/null | tr -d "[:space:]")
RUN=$(mktemp); trap 'rm -f "$RUN"' EXIT
ansible-playbook playbooks/backup.yml > "$RUN" 2>&1; RC=$?
{ echo "=== $(date -Is) rc=$RC"; cat "$RUN"; } >> logs/backup-run.log
RECAP=$(sed -n '/PLAY RECAP/,$p' "$RUN" | tail -n +2 | sed -E 's/ +/ /g; /^$/d')
ERR=$(grep -E 'fatal:|ERROR|Not backed up' "$RUN" | cut -c1-200 | head -5)
N=$(printf '%s\n' "$RECAP" | grep -c .)
GOOD=$(printf '%s\n' "$RECAP" | awk '/failed=0/ && /unreachable=0/{print $1}' | paste -sd, - | sed 's/,/, /g')
BAD=$(printf '%s\n' "$RECAP" | awk '!(/failed=0/ && /unreachable=0/){print $1}' | paste -sd, - | sed 's/,/, /g')
if [ "$RC" -eq 0 ]; then
  S=up; HEAD="Server backup OK"
  MSG="Sir, the nightly backup run is complete. All ${N} servers are secured on konoha: ${GOOD}. The cloud snapshot follows at 0300, as scheduled."
else
  S=down; HEAD="Server backup FAILED"
  MSG="Sir, I regret to report the nightly backup did not go cleanly. Trouble with: ${BAD:-the run itself}. Secured: ${GOOD:-none}.
${ERR}"
fi
echo "$HEAD (rc=$RC)"; echo "$RECAP"; echo "$ERR"
[ -n "$URL" ] && { curl -fsS -m 20 -G "$URL" --data-urlencode "status=$S" --data-urlencode "msg=$HEAD" >/dev/null || echo "Kuma ping failed"; }
[ -n "$DISCORD_WEBHOOK" ] && { printf '%s' "$MSG" | python3 -c 'import json,sys;print(json.dumps({"username":"JARVIS","content":sys.stdin.read()[:1900]}))' | curl -fsS -m 20 -H 'Content-Type: application/json' -d @- "$DISCORD_WEBHOOK" >/dev/null || echo "Discord send failed"; }
[ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ] && { curl -fsS -m 20 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" --data-urlencode "chat_id=$TG_CHAT" --data-urlencode "text=JARVIS: ${MSG:0:3500}" >/dev/null || echo "Telegram send failed"; }
[ "$S" = up ]
