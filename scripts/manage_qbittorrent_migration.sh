#!/bin/bash

# --- CONFIGURATION ---
SOURCE_ID="121" # Source LXC ID
TARGET_IP="192.168.50.173" # Target LXC (125) IP address
TARGET_PORT="8090" # Target WebUI Port
WEBUI_USER="admin" # Target WebUI Username
WEBUI_PASS="adminadmin" # Target WebUI Password

# Relative source path to the backup torrent files
BT_BACKUP_PATH="root/.local/share/qBittorrent/BT_backup"
# --- CONFIGURATION END ---

COOKIE_JAR="/tmp/qbit_cookie.txt"
SOURCE_ROOT="/var/lib/lxc/${SOURCE_ID}/rootfs"
SRC_BT_DIR="${SOURCE_ROOT}/${BT_BACKUP_PATH}"
MAP_FILE="/tmp/qbit_true_map.txt"
CHUNK_SIZE=30

echo "=================================================="
echo " qBittorrent Native Bencode Category Patch Tool "
echo "=================================================="

# 1. Mount source container filesystem
echo "[*] Mounting Source LXC ${SOURCE_ID} storage volume..."
pct mount $SOURCE_ID >/dev/null 2>&1

if [ ! -d "$SRC_BT_DIR" ]; then
 echo "[-] Error: Source backup directory not found at ${SRC_BT_DIR}"
 pct unmount $SOURCE_ID >/dev/null 2>&1
 exit 1
fi

# 2. Authenticate against target API
echo "[*] Authenticating with Target WebUI API..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -i \
 --cookie-jar "$COOKIE_JAR" \
 --header "Referer: http://${TARGET_IP}:${TARGET_PORT}" \
 --data "username=${WEBUI_USER}&password=${WEBUI_PASS}" \
 "http://${TARGET_IP}:${TARGET_PORT}/api/v2/auth/login")

if [ "$HTTP_STATUS" != "200" ] && [ "$HTTP_STATUS" != "204" ]; then
 echo "[-] Error: API Login failed with status code ${HTTP_STATUS}."
 pct unmount $SOURCE_ID >/dev/null 2>&1
 exit 1
fi
echo "[+] API Session authenticated successfully."

# 3. Parse Bencoded files natively using Python
echo "[*] Parsing .fastresume binary structures natively..."
python3 -c "
import os
src_dir = '$SRC_BT_DIR'
out_file = '$MAP_FILE'

def extract_category(filepath):
 try:
 with open(filepath, 'rb') as f:\n data = f.read()\n key = b'qBt-category'\n if key in data:
 idx = data.index(key) + len(key)
 if data[idx:idx+1] == b':':
 return 'uncategorized'

 colon_idx = data.index(b':', idx)
 length = int(data[idx:colon_idx])
 cat_start = colon_idx + 1
 cat_name = data[cat_start:cat_start+length].decode('utf-8', errors='ignore')
 return cat_name.strip() if cat_name.strip() else 'uncategorized'
 except Exception:
 pass
 return 'uncategorized'

with open(out_file, 'w') as out:
 for f in os.listdir(src_dir):
 if f.endswith('.fastresume'):
 hash_id = f.replace('.fastresume', '')
 torrent_file = hash_id + '.torrent'
 if os.path.exists(os.path.join(src_dir, torrent_file)):
 cat = extract_category(os.path.join(src_dir, f))
 # Using a plain comma as a single-character delimiter
 out.write(f'{torrent_file},{cat}\n')
"

if [ ! -f "$MAP_FILE" ]; then
 echo "[-] Error: Failed to extract structural mapping metadata."
 pct unmount $SOURCE_ID >/dev/null 2>&1
 exit 1
fi

# 4. Provision unique detected real categories on the target server
echo "[*] Extracting unique category labels..."
declare -A TARGET_CATS
while IFS="," read -r torrent cat; do
 if [ -n "$cat" ] && [ "$cat" != "uncategorized" ]; then
 TARGET_CATS["$cat"]=1
 fi
done < "$MAP_FILE"

if [ ${#TARGET_CATS[@]} -gt 0 ]; then
 echo "[*] Provisioning real category indices on target application..."
 for target_cat in "${!TARGET_CATS[@]}"; do
 echo " -> Creating category: '$target_cat'"
 curl -s -o /dev/null --cookie "$COOKIE_JAR" \
 --data "category=${target_cat}" \
 "http://${TARGET_IP}:${TARGET_PORT}/api/v2/torrents/createCategory"
 done
 sleep 1
else
 echo "[*] All files identified as uncategorized or default. Continuing..."
fi

# 5. Group files by exact category and dispatch chunked transfers
echo "[*] Beginning localized chunk processing batches..."
cd "$SRC_BT_DIR" || exit 1

for current_cat in "uncategorized" "${!TARGET_CATS[@]}"; do
 MAP_MATCHES=()
 while IFS="," read -r torrent cat; do
 if [ "$cat" == "$current_cat" ]; then
 MAP_MATCHES+=( "$torrent" )
 fi
 done < "$MAP_FILE"

 total_matches=${#MAP_MATCHES[@]}
 if [ $total_matches -eq 0 ]; then continue; fi

 echo "[*] Processing real category '$current_cat' ($total_matches torrents)..."

 for ((i=0; i<total_matches; i+=CHUNK_SIZE)); do
 CURL_CMD=( curl -s -o /dev/null -w "%{http_code}" --cookie "$COOKIE_JAR" )

 for ((j=i; j<i+CHUNK_SIZE && j<total_matches; j++)); do
 CURL_CMD+=( -F "torrents=@${MAP_MATCHES[j]}" )
 done

 if [ "$current_cat" != "uncategorized" ]; then
 CURL_CMD+=( -F "category=$current_cat" )
 fi
 CURL_CMD+=( -F "paused=true" "http://${TARGET_IP}:${TARGET_PORT}/api/v2/torrents/add" )

 STATUS=$("${CURL_CMD[@]}")
 echo " -> Chunk $(( (i/CHUNK_SIZE)+1 )): Status $STATUS"
 sleep 0.5
 done
done

# 6. Safety Cleanup
rm -f "$COOKIE_JAR" "$MAP_FILE"
echo "[*] Unmounting Source Container..."
pct unmount $SOURCE_ID >/dev/null 2>&1
echo "[+] Done! Check your WebUI now."
echo "=================================================="
