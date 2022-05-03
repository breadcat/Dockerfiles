#!/bin/bash

# functions
function func_dir_find {
	find "$directory_home" -maxdepth 3 -mount -type d -name "$1" 2>/dev/null
}
function func_rclone_remote {
	rclone listremotes | grep "$1"
}
function func_check_running_as_root {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root"
		exit 0
	fi
}
function password_manager {
	case "$1" in
	addr) rbw get --full "$2" | awk '/URI:/ {print $2}' ;;
	full) rbw get --full "$2" ;;
	pass) rbw get "$2" ;;
	sync) rbw sync ;;
	user) rbw get --full "$2" | awk '/Username:/ {print $2}' ;;
	*) rbw get "$2" ;;
	esac
}
function func_backup_archive {
	rclone_remote=$(func_rclone_remote backups)
	working_directory=$(func_dir_find backups)/archives
	echo "$working_directory"
	if [ -z "$*" ]; then
		echo Creating archives...
		# build folder array?
		cd "$(mktemp -d)" || exit
		for i in "config" "vault"; do
			tar -cJf "backup-$i-$(date +%F-%H%M).tar.xz" --ignore-failed-read "$directory_home/$i"
		done
		echo "Sending via rclone..."
		for i in *; do
			du -h "$i"
			rclone move "$i" "$rclone_remote"/archives/
		done
		echo Cleaning up...
		rm -r "$PWD"
		echo Done!
	else
		echo Creating single archive...
		cd "$(mktemp -d)" || exit
		tar -cJf "backup-$1-$(date +%F-%H%M).tar.xz" --ignore-failed-read "$directory_home/$1"
		echo "Sending via rclone..."
		for i in *; do
			du -h "$i" && rclone move "$i" "$rclone_remote"/archives/
		done
		echo Cleaning up...
		rm -r "$PWD"
		echo Done!
	fi
}
function func_backup_borg {
	# https://opensource.com/article/17/10/backing-your-machines-borg
	working_directory=$(func_dir_find backups)/borg
	echo "$working_directory"
}
function func_duolingo_streak {
	# check api is installed
	[[ -d "$(func_dir_find config)/duolingo" ]] || git clone https://github.com/KartikTalwar/Duolingo.git "$(func_dir_find config)/duolingo"
	# cd to git dir to include module
	cd "$(func_dir_find config)/duolingo" || return
	# write script
	password_manager sync
	{
		printf "#!/usr/bin/env python3\\n\\n"
		printf "import duolingo\\n"
		printf "lingo  = duolingo.Duolingo('%s', password='%s')\\n" "$(password_manager user duolingo)" "$(password_manager pass duolingo)"
		printf "lingo.buy_streak_freeze()"
	} >"streak-freeze.py"
	# run and remove script
	python "streak-freeze.py"
	rm "streak-freeze.py"
}
function func_duorank {
	duo_username="$(awk -F'[/()]' '/Duolingo/ {print $5}' $(func_dir_find blog."$domain")/content/about.md)"
	rank_filename="$(func_dir_find blog."$domain")/content/posts/logging-duolingo-ranks-over-time.md"
	echo -n "Fetching data for $duo_username... "
	page_source="$(curl -s https://duome.eu/$duo_username)"
	rank_lingot="$(printf %s "$page_source" | awk -F"[#><]" '/icon lingot/ {print $15}')"
	rank_streak="$(printf %s "$page_source" | awk -F"[#><]" '/icon streak/{getline;print $15}')'"
	echo -e "$i \e[32mdone\e[39m"
	echo -n "Appending ranks to page... "
	echo "| $(date +%F) | $(date +%H:%M) | $rank_streak | $rank_lingot |" | tr -d \' >> "$rank_filename"
	echo -e "$i \e[32mdone\e[39m"
	echo -n "Amending lastmod value... "
	mod_timestamp="$(date +%FT%H:%M:00)"
	sed -i "s/lastmod: .*/lastmod: $mod_timestamp/g" "$rank_filename"
	echo -e "$i \e[32mdone\e[39m"
}
function func_create_docker {
	cd "$directory_script" || exit
	# write env file, overwriting any existing
	password_manager sync
	{
		printf "DOMAIN=%s\\n" "$domain"
		printf "PUID=%s\\n" "$(id -u)"
		printf "PGID=%s\\n" "$(id -g)"
		printf "TZ=%s\\n" "$(cat /etc/timezone)"
		printf "CONFDIR=%s\\n" "$(func_dir_find config)"
		printf "SYNCDIR=%s\\n" "$(func_dir_find vault)"
		printf "RCLONE_REMOTE_MEDIA=%s\\n" "$(func_rclone_remote media)"
		printf "WG_WEBUI_PASS=%s\\n" "$(password_manager pass 'wireguard admin')"
		printf "WG_PRIVKEY=%s\\n" "$(password_manager pass 'wireguard private key')"
		printf "DBPASSWORD=%s\\n" "$(password_manager pass postgresql)"
	} >"$directory_script/.env"
	# clean up existing stuff
	echo Cleaning up existing docker files
	for i in volume image system network; do
		docker "$i" prune -f
	done
	docker system prune -af
	# make network, if not existing
	if ! printf "%s" "$(docker network ls)" | grep -q "proxy"; then
		echo Creating docker network
		docker network create proxy
	fi
	# start containers
	echo Starting docker containers
	docker-compose up -d --remove-orphans
	# delete temporary env file
	if [[ -f "$directory_script/.env" ]]; then
		echo Deleting detected env file
		rm "$directory_script/.env"
	fi
	# clean up, again
	docker volume prune -f
}
function func_beets {
	# exists for working around quirks with running beets through a docker container
	func_check_running_as_root
	# make directories
	for i in export staging; do mkdir "$(func_dir_find downloads)/$i"; done
	if ! printf "%s" "$(docker ps -a | grep beets)" | grep -q "Up"; then
		echo Starting beets container, and waiting...
		docker start beets
		sleep 5s
	fi
	docker exec -it beets bash
	echo Moving files
	rclone move "$(func_dir_find export)" "$(func_rclone_remote media)"/audio/ --verbose
	echo Resetting permissions
	chown -R "$username":"$username" "$(func_dir_find export)"
	chown -R "$username":"$username" "$(func_dir_find staging)"
	echo Cleaning folders
	find "$(func_dir_find export)" -type d -empty -delete
	find "$(func_dir_find staging)" -type d -empty -delete
	echo Stopping beets container
	docker stop beets
	echo Cleaning old files
	find "$(func_dir_find beets)" -type f -not -name 'config.yaml' -delete
}
function func_logger {
	# specify directories
	git_directory="$(func_dir_find logger)"
	file_git_log="$git_directory/media.log"
	log_remote=$(func_rclone_remote media)
	git_logger="git --git-dir=$git_directory/.git --work-tree=$git_directory"
	# git configuruation
	if [ ! -e "$git_directory" ]; then
		printf "Logger directory not found, quitting...\n"
		exit 1
	fi
	if [ ! -e "$git_directory/.git" ]; then
		printf "Initialising blank git repo...\n"
		$git_logger init
	fi
	if [ -e "$file_git_log.xz" ]; then
		printf "Decompressing existing xz archive...\n"
		xz -d "$file_git_log.xz"
	fi
	if [ -e "$file_git_log" ]; then
		printf "Removing existing log file...\n"
		rm "$file_git_log"
	fi
	printf "Creating log...\n"
	rclone ls "$log_remote" | sort -k2 >"$file_git_log"
	printf "Appending size information...\n"
	rclone size "$log_remote" >>"$file_git_log"
	printf "Commiting log file to repository...\n"
	$git_logger add "$file_git_log"
	$git_logger commit -m "Update: $(date +%F)"
	if [ -e "$file_git_log.xz" ]; then
		printf "Removing xz archive...\n"
		rm "$file_git_log.xz"
	fi
	printf "Compressing log file...\n"
	xz "$file_git_log"
	printf "Compressing repository...\n"
	$git_logger config pack.windowMemory 10m
	$git_logger config pack.packSizeLimit 20m
	$git_logger gc --aggressive --prune
	printf "Log complete!"
}
function func_magnet {
	# sources and destinations
	cd "$(func_dir_find vault)" || exit
	rclone_remote="seedbox-raw:/watch/"
	# check for aria
	if [ ! -x "$(command -v aria2c)" ]; then # not installed
		echo "Aria doesn't seem to be installed. Exiting" && exit
	fi
	# trackers
	trackers_list=(
		"udp://9.rarbg.to:2710/announce"
		"udp://denis.stalker.upeer.me:6969/announce"
		"udp://exodus.desync.com:6969/announce"
		"udp://ipv6.tracker.harry.lu:80/announce"
		"udp://open.demonii.si:1337/announce"
		"udp://open.stealth.si:80/announce"
		"udp://p4p.arenabg.com:1337/announce"
		"udp://retracker.lanta-net.ru:2710/announce"
		"udp://tracker.coppersurfer.tk:6969/announce"
		"udp://tracker.cyberia.is:6969/announce"
		"udp://tracker.leechers-paradise.org:6969/announce"
		"udp://tracker.open-internet.nl:6969/announce"
		"udp://tracker.opentrackr.org:1337/announce"
		"udp://tracker.pirateparty.gr:6969/announce"
		"udp://tracker.tiny-vps.com:6969/announce"
		"udp://tracker.torrent.eu.org:451/announce"
	)
	for i in "${trackers_list[@]}"; do
		trackers="$i,$trackers"
	done
	# magnet loop
	for j in *.magnet; do
		[ -f "$j" ] || break
		aria2c --bt-tracker="$trackers" --bt-metadata-only=true --bt-save-metadata=true "$(cat "$j")" && rm "$j"
	done
	# torrent loop, move to watch
	for k in *.torrent; do
		[ -f "$k" ] || break
		for i in *.torrent; do rclone move "$k" "$rclone_remote"; done
	done
}
function func_payslip {
	# depends on: getmail4 mpack qpdf
	directory_temp="$(mktemp -d)"
	cd "$directory_temp" || exit
	mkdir {cur,new,tmp}
	# write config file
	password_manager sync
	{
		printf "[retriever]\\n"
		printf "type = SimpleIMAPSSLRetriever\\n"
		printf "server = %s\\n" "$(password_manager full email | awk -F: '/Incoming/ {gsub(/ /,""); print $2}')"
		printf "username = %s\\n" "$(password_manager user email)"
		printf "port = 993\\n"
		printf "password = %s\\n\\n" "$(password_manager pass email)"
		printf "[destination]\\n"
		printf "type = Maildir\\n"
		printf "path = %s/\\n" "$directory_temp"
	} >getmailrc
	getmail --getmaildir "$directory_temp"
	cd new || exit
	grep "$(password_manager user payslip)" ./* | cut -f1 -d: | uniq | xargs munpack -f
	for i in *.PDF; do
		mv "$i" "$(func_dir_find paperwork)/"
	done
	# decrypt payslip file
	cd "$(func_dir_find paperwork)" || exit
	for i in *.PDF; do
		fileProtected=0
		qpdf "$i" --check || fileProtected=1
		if [ $fileProtected == 1 ]; then
			parsed_name="$(printf "%s" "$i" | awk -FX '{print substr($3,5,4) "-" substr($3,3,2) "-" substr($3,1,2) ".pdf"}')"
			qpdf --password="$(password_manager pass payslip)" --decrypt "$i" "personal/workplace/wages/$parsed_name" && rm "$i"
		fi
	done
	# clean up temp directory
	rm -r "$directory_temp"
}
function func_permissions {
	func_check_running_as_root
	chown "$username":"$username" "$directory_script/rclone.conf"
}
function func_media_sort {
	func_seedbox_mount
	if [ ! -x "$(command -v media-sort)" ]; then # not installed
		echo media-sort not installed. Installing...
		func_check_running_as_root
		curl https://i.jpillora.com/media-sort | bash
	fi
	dir_import=$(func_dir_find downloads)/
	if [[ -d "$dir_import" ]]; then
		dir_tv=$(func_dir_find media)/videos/television
		dir_mov=$(func_dir_find media)/videos/movies
		temp_tv="{{ .Name }}/{{ .Name }} S{{ printf \"%02d\" .Season }}E{{ printf \"%02d\" .Episode }}{{ if ne .ExtraEpisode -1 }}-{{ printf \"%02d\" .ExtraEpisode }}{{end}}.{{ .Ext }}"
		temp_mov="{{ .Name }} ({{ .Year }})/{{ .Name }}.{{ .Ext }}"
		media-sort --action copy --concurrency 1 --accuracy-threshold 90 --tv-dir "$dir_tv" --movie-dir "$dir_mov" --tv-template "$temp_tv" --movie-template "$temp_mov" --recursive --overwrite-if-larger "$dir_import"

	else
		printf "Import directory not found.\\n"
		exit 0
	fi
}
function func_rclone_mount {
	echo rclone mount checker
	# check allow_other in fuse.conf
	if ! grep -q "^user_allow_other$" /etc/fuse.conf; then
		echo user_allow_other not found in fuse.conf
		func_check_running_as_root
		echo Appending to file.
		echo "user_allow_other" >>/etc/fuse.conf
		echo Please restart the script.
		exit 0
	fi
	for i in media paperwork pictures unsorted; do
		mount_point="$directory_home/$i"
		if [[ ! -d "$mount_point" ]]; then
			echo "Creating empty directory $i"
			mkdir -p "$mount_point"
		fi
		if [[ -f "$mount_point/.mountcheck" ]]; then
			echo "$i" still mounted
		else
			mount_points_remounted=true
			echo "$i" not mounted
			echo force unmounting
			fusermount -uz "$mount_point"
			echo sleeping && sleep 3
			echo mounting
			rclone mount "drive-$i": "$mount_point" --allow-other --allow-non-empty --daemon --log-file "$(func_dir_find config)/logs/rclone-$i.log"
		fi
		if [ "$mount_points_remounted" = true ]; then
			echo restarting docker containers
			for j in "${docker_restart[@]}"; do
				docker restart "$j"
			done
		fi
	done
}
function func_seedbox_mount {
	# variables and checks
	mount_point="$directory_home/downloads"
	rclone_name="seedbox"
	if [[ ! -d "$mount_point" ]]; then
		echo "Creating empty directory $i"
		mkdir -p "$mount_point"
	fi
	printf "Seedbox mount checker... "
	if [[ -f "$mount_point/.mountcheck" ]]; then
		printf "exists.\\n"
	else
		fusermount -uz "$mount_point"
		rclone mount "$rclone_name": "$mount_point" --allow-other --allow-non-empty --daemon --log-file "$(func_dir_find config)/logs/rclone-$rclone_name.log"
	fi
}
function func_status {
	status_uptime=$(($(cut -f1 -d. </proc/uptime) / 86400))
	{
		printf -- "---\\ntitle: Status\\nlayout: single\\n---\\n\\n"
		printf "*Generated on %(%Y-%m-%d at %H:%M)T*\\n\\n" -1
		printf "* Uptime: %s Day%s\\n" "$status_uptime" "$(if (("$status_uptime" > 1)); then echo s; fi)"
		printf "* CPU Load: %s\\n" "$(cut -d" " -f1-3 </proc/loadavg)"
		printf "* Users: %s\\n" "$(uptime | grep -oP '.{3}user' | sed 's/\user//g' | xargs)"
		printf "* RAM Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Mem/ {print $3/$2 * 100.0}')")"
		printf "* Swap Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Swap/ {print $3/$2 * 100.0}')")"
		printf "* Root Usage: %s\\n" "$(df / | awk 'END{print $5}')"
		printf "* Downloads Usage: %s\\n" "$(df | awk '/downloads/ {print $5}')"
		printf "* Cloud Usage: %s\\n" "$(git --git-dir="$(func_dir_find logger)/.git" show | awk 'END{print $3" "$4}')"
		printf "* [Dockers](https://github.com/breadcat/Dockerfiles): %s\\n" "$(docker ps -q | wc -l)/$(docker ps -aq | wc -l)"
		printf "* Packages: %s\\n" "$(dpkg -l | grep ^ii -c)"
		printf "* Monthly Data: %s\\n\\n" "$(vnstat -m --oneline | cut -f11 -d\;)"
		printf "Hardware specifications themselves are covered on the [hardware page](/hardware/#server).\\n"
	} >"$(func_dir_find blog."$domain")/content/status.md"
}
function func_weight {
	# variables
	if [ -n "$2" ]; then
		if [ "$2" = "date" ]; then
			weight_filename="$(func_dir_find blog."$domain")/content/weight.md"
			page_source="$(head -n -1 "$weight_filename")"
			previous_date="$(printf %s "$page_source" | awk -F, 'END{print $1}')"
			sequence_count="$((($(date --date="$(date +%F)" +%s) - $(date --date="$previous_date" +%s)) / (60 * 60 * 24)))"
			# operation
			{
				printf "%s\\n" "$page_source"
				printf "%s" "$(for i in $(seq $sequence_count); do printf "%s,\\n" "$(date -d "$previous_date+$i day" +%F)"; done)"
				printf "\\n</pre></details>"
			} >"$weight_filename"
			exit 0
		else
			year=$2
		fi
	else
		year=$(date +%Y)
	fi
	weight_filename="$(func_dir_find blog."$domain")/content/weight.md"
	# cd to temporary directory
	cd "$(mktemp -d)" || exit
	# pull raw data from source
	weight_rawdata="$(awk '/<pre>/{flag=1; next} /<\/pre>/{flag=0} flag' "$weight_filename" | sort -u)"
	printf "%s" "$weight_rawdata" | grep "^$year-" >temp.dat
	weight_dateinit="$(awk '/date:/ {print $2}' "$weight_filename")"
	# draw graph
	gnuplot <<-EOF
		set grid
		set datafile separator comma
		set xlabel "Month"
		set xdata time
		set timefmt "%Y-%m-%d"
		set xtics format "%b"
		set ylabel "Weight (kg)"
		set key off
		set term svg font 'sans-serif,12'
		set sample 50
		set output "temp.svg"
		plot "temp.dat" using 1:2 smooth cspline with lines
	EOF
	# compress graph
	svgo -i "temp.svg" --multipass -o "temp.min.svg" -q
	# write page
	{
		printf -- "---\\ntitle: Weight\\nlayout: single\\ndate: %s\\nlastmod: %(%Y-%m-%dT%H:%M:00)T\\n---\\n\\n" "$weight_dateinit" -1
		printf "%s\\n\\n%s graph\\n\\n" "$(cat temp.min.svg)" "$year"
		printf "<details><summary>Raw data</summary>\\n<pre>\\n%s\\n</pre></details>" "$weight_rawdata"

	} >"$weight_filename"
	# clean up
	rm -r "$PWD"
}
function func_dedupe_remote {
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq "$dests"); do
		remote=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Deduplicating "$remote"
		rclone dedupe --dedupe-mode newest "$remote" --log-file "$(func_dir_find config)/logs/rclone-dupe-$(date +%F-%H%M).log"
	done
}
function func_refresh_remotes {
	rclone_prefix="backup-"
	echo "Refreshing rclone remote tokens"
	for i in $(func_rclone_remote "$rclone_prefix"); do
		if rclone lsd "$i" &>/dev/null; then
			echo -e "$i \e[32msuccess\e[39m"
		else
			echo -e "$i \e[31mfailed\e[39m"
		fi
	done
}
function func_sync_remotes {
	source=$(func_rclone_remote "$rclone_core" | sed 1q)
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq 2 "$dests"); do
		dest=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Syncing "$source" to "$dest"
		rclone sync "$source" "$dest" --drive-server-side-across-configs --drive-stop-on-upload-limit --verbose --log-file "$(func_dir_find config)/logs/rclone-sync-$(date +%F-%H%M).log"
	done
}
function func_space_clean {
	func_check_running_as_root
	# journals
	journalctl --vacuum-size=75M
	# docker
	for i in volume image; do
		docker "$i" prune -f
	done
	# apt
	apt-get clean
	# temp directory
	rm -rf /tmp/tmp.*
}

function func_update {
	func_check_running_as_root
	if [[ $distro =~ "Debian" ]]; then
		# Update Debian
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get dist-upgrade -y
		apt-get autoremove --purge -y
		apt-get clean
		if [ -x "$(command -v yt-dlp)" ]; then
			yt-dlp -U
		fi
		if [ -x "$(command -v rclone)" ]; then
			curl --silent "https://rclone.org/install.sh" | bash
		fi
	elif [[ $distro =~ "Arch" ]]; then
		# Update Archlinux
		if [ -x "$(command -v paru)" ]; then
			paru -Syu --noconfirm
		else
			pacman -Syu --noconfirm
		fi
	else
		echo "Who knows what you're running"
	fi
	# Update remaining applications
	if [ -f "$directory_home/.config/retroarch/lrcm/lrcm" ]; then
		"$directory_home/.config/retroarch/lrcm/lrcm" update
	fi
	find "$(func_dir_find config)" -maxdepth 2 -name ".git" -type d | sed 's/\/.git//' | xargs -P10 -I{} git -C {} pull
	if [ -x "$(command -v we-get)" ]; then
		echo "Updating we-get..."
		pip3 install --upgrade git+https://github.com/rachmadaniHaryono/we-get
	fi
	if [ -x "$(command -v media-sort)" ]; then
		echo "Updating media-sort..."
		cd "/usr/local/bin" || return
		curl https://i.jpillora.com/media-sort | bash
	fi
	if [ -x "$(command -v duplicacy)" ]; then
		dupli_installed="$(duplicacy | awk '/VERSION/ && $0 != "" { getline; print $1}')"
		dupli_available="$(curl -s https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | jq -r '.tag_name' | tr -d '[:alpha:]')"
		if [ "$dupli_installed" != "$dupli_available" ]; then
			echo Updating Duplicacy
			wget "$(curl -sL https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | jq -r '.assets[].browser_download_url' | grep linux_x64)" -O "/usr/local/bin/duplicacy"
		fi
	fi
	if [ -x "$(command -v plowmod)" ]; then
		echo "Updating plowshare..."
		su -c "plowmod -u" -s /bin/sh "$username"
		chown -R "$username":"$username" "$directory_home/.config/plowshare"
	fi
}
function main {
	export XZ_OPT=-e9
	distro="$(awk -F'"' '/^NAME/ {print $2}' /etc/os-release)"
	username="$(logname)"
	directory_home="/home/$username"
	domain="$(awk -F'"' '/domain/ {print $2}' "$(func_dir_find traefik)/traefik.toml")"
	directory_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	rclone_core="gdrive"
	docker_restart=("syncthing")
	case "$1" in
	archive) func_backup_archive "$@" ;;
	beets) func_beets ;;
	bookmarks) grep -P "\t\t\t\<li\>" "$(func_dir_find startpage)/index.html" | sort -t\> -k3 > "$(func_dir_find startpage)/bookmarks.txt" ;;
	borg) func_backup_borg ;;
	clean) func_space_clean ;;
	dedupe) func_dedupe_remote ;;
	docker) func_create_docker ;;
	duolingo) func_duolingo_streak ;;
	logger) func_logger ;;
	magnet) func_magnet ;;
	payslip) func_payslip ;;
	permissions) func_permissions ;;
	rank) func_duorank ;;
	rclone) func_rclone_mount ;;
	refresh) func_refresh_remotes ;;
	seedbox) func_seedbox_mount ;;
	sort) func_media_sort ;;
	status) func_status ;;
	sync) func_sync_remotes ;;
	update) func_update ;;
	weight) func_weight "$@" ;;
	*) echo "$0" && awk '/^function main/,EOF' "$0" | awk '/case/{flag=1;next}/esac/{flag=0}flag' | awk -F"\t|)" '{print $2}' | tr -d "*" | sort | xargs ;;
	esac
}

main "$@"
